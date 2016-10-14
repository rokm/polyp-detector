function fig = visualize_detections_as_points (I, polygon, annotations, detections, varargin)
    % fig = VISUALIZE_DETECTIONS_AS_POINTS (I, polygon, annotations, detections, varargin)
    %
    % Visualizes detection/region proposal centroids.

    parser = inputParser();
    parser.addParameter('fig', [], @ishandle);
    parser.addParameter('prefix', '', @ischar);
    parser.addParameter('threshold', 32, @isnumeric);
    parser.addParameter('evaluate_against', '', @ischar);
    parser.parse(varargin{:});

    fig = parser.Results.fig;
    prefix = parser.Results.prefix;
    threshold = parser.Results.threshold;
    evaluate_against = parser.Results.evaluate_against;

    % Create mask
    mask = poly2mask(polygon(:,1), polygon(:,2), size(I, 1), size(I,2));

    if isempty(fig),
        fig = figure();
    else
        set(groot, 'CurrentFigure', fig);
    end
    clf(fig);

    % Show image
    Im = uint8( bsxfun(@times, double(I), 0.50*mask + 0.50) );

    imshow(Im);
    hold on;
    
    if ~isempty(evaluate_against),
        % Evaluate against selected set of manual annotations
        idx = find(ismember(annotations(:,1), evaluate_against));
        name = annotations{idx, 1};
        gt = annotations{idx, 2};
        
        % Evaluate
        [ gt, dt ] = evaluate_detections_as_points(detections, gt, 'threshold', threshold);
        
        % Draw ground-truth; TP and FN
        gt_assigned = gt(:,end) ~= 0;
        plot(gt(gt_assigned,1), gt(gt_assigned, 2), '+', 'Color', 'cyan'); % TP
        plot(gt(~gt_assigned,1), gt(~gt_assigned, 2), '+', 'Color', 'yellow'); % FN
        
        % Draw detections; TP and FP
        dt_assigned = dt(:,end) ~= 0;
        plot(dt(dt_assigned,1), dt(dt_assigned, 2), 'x', 'Color', 'green'); % TP
        plot(dt(~dt_assigned,1), dt(~dt_assigned, 2), 'x', 'Color', 'red'); % FP

        % Create fake plots for legend entries
        h = [];
        h(end+1) = plot([0,0], [0,0], '+', 'Color', 'cyan', 'LineWidth', 2);
        h(end+1) = plot([0,0], [0,0], '+', 'Color', 'yellow', 'LineWidth', 2);
        h(end+1) = plot([0,0], [0,0], 'x', 'Color', 'green', 'LineWidth', 2);
        h(end+1) = plot([0,0], [0,0], 'x', 'Color', 'red', 'LineWidth', 2);
        legend(h, 'TP (annotated)', 'FN', 'TP (det)', 'FP');
    else
        % Draw all manual annotations
        h = [];
        legend_entries = {};

        if ~isempty(annotations),
            num_annotations = size(annotations, 1);
            colors = lines(num_annotations);
            for i = 1:num_annotations,
                annotation_id = annotations{i, 1};
                annotation_points = annotations{i, 2};

                h(end+1) = plot(annotation_points(:,1), annotation_points(:,2), 'ko', 'MarkerFaceColor', colors(i,:));
                legend_entries{end+1} = sprintf('%s (%d)', annotation_id, size(annotation_points, 1));
            end
        end

        % Draw all detections
        detection_points = detections(:,1:2) + detections(:,3:4)/2;
        h(end+1) = plot(detection_points(:,1), detection_points(:,2), 'gx', 'MarkerSize', 8, 'LineWidth', 2);
        legend_entries{end+1} = sprintf('Detector (%d)', size(detections, 1));
        
        % Legend
        legend(h, legend_entries, 'Location', 'NorthEast', 'Interpreter', 'none');
    end
    
    % Set title    
    title = prefix;
    set(fig, 'Name', title);
    
    % Display as text as well
    h = text(0, 0, title, 'Color', 'white', 'FontSize', 20, 'Interpreter', 'none');
    h.Position(1) = size(I, 2)/2 - h.Extent(3)/2;
    h.Position(2) = h.Extent(4);
    
    % Draw
    drawnow();
end