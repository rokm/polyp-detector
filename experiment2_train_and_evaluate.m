function experiment2_train_and_evaluate (varargin)
    % EXPERIMENT2_TRAIN_AND_EVALUATE (varargin)
    %
    % Performs Experiment 2, by running the detection pipeline on Sara's
    % images, and comparing the detections to Sara's manual annotations.
    % It should be noted that the latter cannot really be considered 
    % ground-truth (i.e., it may not include all polyps), so this may be
    % more of an illustration of how the pipeline is used in practice, as
    % well as a rough comparison to the human annotator.
    %
    % The function creates a result file in the output directory; its
    % contents can be printed in a tabular format using the
    % EXPERIMENT2_DISPLAY_RESULTS() function. The results structures also
    % contain raw detections (both in form of proposals and the final
    % detections), should they be needed. In addition, visualization of
    % results can be enabled, which produces figures illustrating input
    % images with detections and manual annotations, as well as assignments
    % between them for the purpose of automatic evaluation (also stored in
    % output directory).
    %
    % Input: optional key/value pairs
    %  - output_dir: output directory (default: experiment2-martin-sara)
    %  - training_dataset_dir: path to training images directory (default:
    %    dataset-martin)
    %  - training_images: list of training images (default: {}; use
    %    all .jpg files found in training_dataset_dir)
    %  - acf_detector_file: path to pre-trained ACF detector (default: ''; 
    %    train from scratch with acf_training_images)
    %  - acf_training_images: list of images to train ACF detector with
    %    (default: {}; use training images from Kristjan's dataset)
    %  - negative_folders: list of folders with negative images to use
    %    when training the ACF detector (default: {}; use the cropped 
    %    negatives from Kristjan's dataset)
    %  - mix_negatives_with_positives: when training an ACF detector, put
    %    the negative images into folder with labelled images to perform
    %    hard negative mining on all images (default: false)
    %  - acf_window_size: base window size for ACF detector (default: 30
    %    pixels)
    %  - test_dataset_dir: path to test images directory (default:
    %    dataset-sara)
    %  - visualize_proposals: create .fig files with visualization of ACF
    %    proposals vs annotations (default: false)
    %  - visualize_detections: create .fig files with visualization of 
    %    final detections vs annotations (default: false)
    %  - enhance_images: enhance images with CLAHE (default: false)
    %  - dynamic_scale_factor: estimate image scale from the few typical
    %    polyp boxes (default: true)
    %  - manual_scale_override: use manual scale overrides to compensate
    %    for large image size variations (default: true)
    %
    % Note: the Matlab figures generated by visualize_proposals and
    % visualize_detections flags are created with visible setting set to
    % false. Therefore, when loading the figure, it needs to be forced 
    % to become visible, i.e., using openfig(..., 'visible')
    
    % Input parameters
    parser = inputParser();
    parser.addParameter('output_dir', 'experiment2-martin-sara', @ischar);
    
    parser.addParameter('training_dataset_dir', 'dataset-martin', @ischar);
    parser.addParameter('training_images', {}, @iscell);
    
    parser.addParameter('acf_detector_file', '', @ischar);
    parser.addParameter('acf_training_images', {}, @iscell);
    parser.addParameter('negative_folders', {}, @iscell);
    parser.addParameter('mix_negatives_with_positives', false, @islogical);
    parser.addParameter('acf_window_size', 30, @isnumeric);
    
    parser.addParameter('classifier_file', '', @ischar);
    
    parser.addParameter('test_dataset_dir', 'dataset-sara', @ischar);
    
    parser.addParameter('visualize_proposals', false, @islogical);
    parser.addParameter('visualize_detections', false, @islogical);
    parser.addParameter('enhance_images', false, @islogical);

    parser.addParameter('dynamic_scale_factor', true, @islogical);
    parser.addParameter('manual_scale_override', true, @islogical);
    parser.parse(varargin{:});
    
    
    output_dir = parser.Results.output_dir;
    
    training_dataset_dir = parser.Results.training_dataset_dir;
    training_images = parser.Results.training_images;

    acf_detector_file = parser.Results.acf_detector_file;
    
    acf_training_images = parser.Results.acf_training_images;
    negative_folders = parser.Results.negative_folders;
    mix_negatives_with_positives = parser.Results.mix_negatives_with_positives;
    acf_window_size = parser.Results.acf_window_size;
    
    classifier_file = parser.Results.classifier_file;
    
    test_dataset_dir = parser.Results.test_dataset_dir;
    
    visualize_proposals = parser.Results.visualize_proposals;
    visualize_detections = parser.Results.visualize_detections;
    enhance_images = parser.Results.enhance_images;

    dynamic_scale_factor = parser.Results.dynamic_scale_factor;
    manual_scale_override = parser.Results.manual_scale_override;
    
    % ACF training images: use the training images from Kristjan's dataset
    % as they have tighter bounding boxes that result in better region
    % proposals... Plus, this way we avoid overfitting SVM samples in the
    % second stage (TODO: implement leave-one-out sample gathering scheme
    % for use with a single training dataset!)
    if isempty(acf_training_images)
        acf_training_images = { '07.03.jpg', '13.01.jpg', '13.03.jpg', '13.04.jpg', '13.05.jpg' };
        acf_training_images = cellfun(@(x) fullfile('dataset-kristjan', x), acf_training_images, 'UniformOutput', false);
    end
    
    % Additional cropped negatives from Kristjan's dataset (for ACF
    % training, if applicable)
    if isempty(negative_folders)
        negative_folders = { 'dataset-kristjan/negatives' };
    end
            
            
    % Training images for second-stage classifier: take all images from 
    % Martin's dataset (7 used in Experiment 1 + 11 additional images 
    % with annotations in smaller ROIs)
    if isempty(training_images)
        files = dir(fullfile(training_dataset_dir, '*.jpg'));
        training_images = arrayfun(@(x) fullfile(training_dataset_dir, x.name), files, 'UniformOutput', false);
    end
    
    % Cache directory
    cache_dir = fullfile(output_dir, 'cache');
    
    
    %% Create polyp detector
    polyp_detector = vicos.PolypDetector();
    polyp_detector.enhance_image = enhance_images; % Set globally, so that it is applied at all processing steps
    
    
    %% Phase 1: train ACF detector
    if ~isempty(acf_detector_file)
        % Use pre-trained detector
        assert(exist(acf_detector_file, 'file') ~= 0, 'Pre-trained ACF detector does not exist!');
        
        fprintf(' >> Using pre-trained ACF detector: %s\n', acf_detector_file);
    else
        % Train ACF detector
        acf_detector_file = fullfile(output_dir, 'acf_detector.mat');
        
        if ~exist(acf_detector_file, 'file')
            % Prepare training dataset
            acf_training_dataset_dir = fullfile(output_dir, 'acf_training_dataset');
            if ~exist(acf_training_dataset_dir, 'dir')
                fprintf('>> Preparing ACF training dataset...\n');
                vicos.AcfDetector.training_prepare_dataset(acf_training_images, acf_training_dataset_dir, 'negative_folders', negative_folders, 'mix_negatives_with_positives', mix_negatives_with_positives, 'enhance_images', enhance_images);
            else
                fprintf('ACF training dataset already exists!\n');
            end
        
            % Train ACF detector
            fprintf('Training ACF detector...\n');
            vicos.AcfDetector.training_train_detector(acf_training_dataset_dir, 'window_size', [ acf_window_size, acf_window_size ], 'output_file', acf_detector_file);
        else
            % We already have ACF detector
            fprintf(' >> ACF detector already trained!\n');
        end
    end
    
    % Set/load the ACF detector
    polyp_detector.load_acf_detector(acf_detector_file);
    
    
    %% Phase 2: train SVM
    if ~isempty(classifier_file)
        % Use pre-trained classifier
        assert(exist(classifier_file, 'file') ~= 0, 'Pre-trained SVM classifier does not exist!');
        
        fprintf(' >> Using pre-trained SVM classifier: %s\n', classifier_file);
    else
        % Train SVM classifier
        classifier_file = fullfile(output_dir, sprintf('classifier-%s.mat', polyp_detector.construct_classifier_identifier()));
        if ~exist(classifier_file, 'file')
            fprintf('Training SVM classifier...\n');
            t = tic();
            classifier = polyp_detector.train_svm_classifier('train_images', training_images, 'cache_dir', cache_dir); %#ok<NASGU>
            training_time = toc(t); %#ok<NASGU>
            save(classifier_file, '-v7.3', 'classifier', 'training_time');
        else
            fprintf('SVM classifier has already been trained!\n');
        end
    end
        
    % Set/load the classifier
    polyp_detector.load_classifier(classifier_file);
    
    
    %% Phase 3: evaluate
    % Gather all test images
    test_images = dir(fullfile(test_dataset_dir, '*.jpg'));
    
    % Load the polyp size information. In each image, Martin annotated few
    % representative polyps; we use these boxes to estimate the average
    % polyp size, which is used for distance threshold in automatic
    % evaluation. If dynamic_scale_factor is turned on, the estimated
    % average size is also used to estimate the scale factor for the image.
    info = load(fullfile(test_dataset_dir, 'info.mat'));
    info = info.info;
    
    % Manual scale factor override; as the test images were not taken with
    % automatic processing in mind, the effective scale (size) of polyps in
    % the images may drastically vary. In a practical application, the user
    % should estimate this scale factor manually prior to processing. Here,
    % we allow the scale factors to be overriden with values obtained by a
    % quick examination of the images used.
    if manual_scale_override
        scale_override = get_scale_override();
    else
        scale_override = containers.Map();
    end
        
    
    % Pre-allocate results structure
    results = struct(...
        'image_name', '', ...
        'num_annotations', nan, ...
        'distance_threshold', nan, ...
        'scale_factor', nan, ...
        'proposal_precision', nan, ...
        'proposal_recall', nan, ...
        'proposal_number', nan, ...
        'detection_precision', nan, ...
        'detection_recall', nan, ...
        'detection_number', 0);
    results = repmat(results, 1, numel(test_images));
    
    for i = 1:numel(test_images)
        % Get image name
        test_image = fullfile(test_dataset_dir, test_images(i).name);
        
        %% Load data
        [ I, basename, polygon, ~, annotations ] = vicos.PolypDetector.load_data(test_image);
        fprintf('Test image #%d: %s\n', i, basename);
        
        % Validate the format of annotations, just to be sure
        assert(size(annotations, 1) == 1 && size(annotations, 2) == 2, 'Invalid annotations!');
        assert(isequal(annotations{1, 1}, 'Sara'), 'Invalid annotations!');
        
        annotations = annotations{1, 2}; % Take only points
        
        %% Process external info for image
        % Find the info for this image
        info_mask = ismember({ info.image_name }, basename);
        assert(sum(info_mask) == 1, 'Invalid information for image given!');
        boxes = info(info_mask).boxes;
        diagonals = sqrt(boxes(:,3).^2 + boxes(:,4).^2);
        
        % Determine scale factor: a crude heuristic for automatic 
        % estimation of image scale factor - does not work for cases when
        % images should be downscaled (i.e., close-up images)!
        if dynamic_scale_factor
            min_size = min(diagonals) / sqrt(2);
            fprintf(' >> minimum diagonal: %g, minimum size: %g\n', min(diagonals), min_size);

            scale_factor = ceil(acf_window_size / min_size);
        else
            scale_factor = 1;
        end
        fprintf(' >> scale factor: %g\n', scale_factor);
                
        % Manual overrides for scale factor, if applicable
        if manual_scale_override && scale_override.isKey(basename)
            scale_factor = scale_override(basename);
            fprintf(' >> override scale factor: %g\n', scale_factor);
        end
        
        % Distance threshold for evaluation
        distance_threshold = median(diagonals);
        fprintf(' >> distance threshold: %g\n', distance_threshold);

        %% Process the image
        % Validity mask for evaluation (filter out points outside the ROI)
        mask = poly2mask(polygon(:,1), polygon(:,2), size(I, 1), size(I,2));
                 
        % First, get only proposals regions
        regions = polyp_detector.process_image(test_image, 'cache_dir', cache_dir, 'rescale_image', scale_factor, 'regions_only', true);
        
        % Full detection pipeline
        detections = polyp_detector.process_image(test_image, 'cache_dir', cache_dir, 'rescale_image', scale_factor);
        
        fprintf(' >> %d regions, %d detections; %d annotations\n', size(regions, 1), size(detections, 1), size(annotations, 1));
        
        %% Evaluation
        % Evaluate proposals
        [ gt, dt ] = vicos.PolypDetector.evaluate_detections_as_points(regions, annotations, 'validity_mask', mask, 'threshold', distance_threshold);
        
        tp  = sum( gt(:,end) > 0);
        fn  = sum( gt(:,end) == 0);
        tp2 = sum( dt(:,end) > 0);
        fp  = sum( dt(:,end) == 0);
        
        assert(tp == tp2, 'Sanity check failed!');
        
        num_annotations = tp + fn;
        proposal_precision = tp / (tp + fp);
        proposal_recall = tp / (tp + fn);
        proposal_f_score = 2*(proposal_precision*proposal_recall)/(proposal_precision + proposal_recall);
        proposal_number = tp + fp;

        fprintf('proposals; precision: %.2f %%, recall: %.2f %%, number detected: %d, number annotated: %d, ratio: %.2f %%\n', 100*proposal_precision, 100*proposal_recall, proposal_number, num_annotations, 100*proposal_number/num_annotations);
        
        tmp_proposals.dt = dt;
        tmp_proposals.gt = gt;
        
        % Evaluate final detections
        [ gt, dt ] = vicos.PolypDetector.evaluate_detections_as_points(detections, annotations, 'validity_mask', mask, 'threshold', distance_threshold);
        
        tp  = sum( gt(:,end) > 0);
        fn  = sum( gt(:,end) == 0);
        tp2 = sum( dt(:,end) > 0);
        fp  = sum( dt(:,end) == 0);
        
        assert(tp == tp2, 'Sanity check failed!');
        
        num_annotations = tp + fn;
        detection_precision = tp / (tp + fp);
        detection_recall = tp / (tp + fn);
        detection_number = tp + fp;
        detection_f_score = 2*(detection_precision*detection_recall)/(detection_precision + detection_recall);
        
        fprintf('detections; precision: %.2f %%, recall: %.2f %%, number detected: %d, number annotated: %d, ratio: %.2f %%\n', 100*detection_precision, 100*detection_recall, detection_number, num_annotations, 100*detection_number/num_annotations);
        
        tmp_detections.dt = dt;
        tmp_detections.gt = gt;
        
        % Store results
        results(i).image_name = basename;
        results(i).num_annotations = num_annotations;
        results(i).distance_threshold = distance_threshold;
        results(i).scale_factor = scale_factor;
        results(i).proposal_precision = proposal_precision;
        results(i).proposal_recall = proposal_recall;
        results(i).proposal_f_score = proposal_f_score;
        results(i).proposal_number = proposal_number;
        results(i).detection_precision = detection_precision;
        results(i).detection_recall = detection_recall;
        results(i).detection_f_score = detection_f_score;
        results(i).detection_number = detection_number;
        
        results(i).image_size = size(I);
        results(i).proposals = tmp_proposals;
        results(i).detections = tmp_detections;
        
        %% Visualization (optional)
        if visualize_proposals
            fig = figure('Visible', 'off');
            vicos.PolypDetector.visualize_detections_as_points(I, polygon, { 'Sara', annotations }, regions, 'fig', fig, 'distance_threshold', distance_threshold, 'prefix', sprintf('%s: ACF proposals', basename));
            savefig(fig, fullfile(output_dir, sprintf('%s-proposals.fig', basename)), 'compact');
            delete(fig);
        end
        
        if visualize_detections
            fig = figure('Visible', 'off');
            vicos.PolypDetector.visualize_detections_as_points(I, polygon, { 'Sara', annotations }, detections, 'fig', fig, 'distance_threshold', distance_threshold, 'prefix', sprintf('%s: final detections', basename));
            savefig(fig, fullfile(output_dir, sprintf('%s-detection.fig', basename)), 'compact');
            delete(fig);
        end
    end
    
    %% Save results
    results_filename = fullfile(output_dir, sprintf('results-%s.mat', polyp_detector.construct_classifier_identifier()));
    save(results_filename, '-v7.3', 'results');
    
    %% Display results again (for copy & paste purposes)
    experiment2_display_results(results);
end

function scale_override = get_scale_override ()
    % scale_override = GET_SCALE_OVERRIDE ()
    %
    % Retrieves manual scale override for Sara's dataset. The scale values
    % were determined by a quick examination of the images. In practice,
    % same information should be provided by the user before the images are
    % processed.
    
    scale_override = containers.Map();
    
    scale_override('sample1-2012-05') = 0.75; % Close-up; downscale!
    scale_override('sample1-2012-11') = 0.50; % Close-up; downscale!
    scale_override('sample1-2012-12') = 3.00;
    scale_override('sample2-2012-03') = 0.75; % Close-up; downscale!
    scale_override('sample3-2012-12') = 3.00;
    scale_override('sample4-2012-06') = 0.75; % Close-up; downscale!
    scale_override('sample4-2012-12') = 3.00;
    scale_override('sample5-2012-04') = 3.00;
    scale_override('sample5-2012-12') = 4.00;
    scale_override('sample5-2013-01') = 1.00; % Force 1.0 to override the heuristic
end

