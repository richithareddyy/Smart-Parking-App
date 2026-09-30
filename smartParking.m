function smartParking
%SMARTPARKING Interactive parking occupancy demonstration.
root = fileparts(mfilename('fullpath'));
mode = questdlg('Choose an image set.','Smart Parking','Bundled demo','Choose images','Cancel','Bundled demo');
if isempty(mode) || strcmp(mode,'Cancel'), return; end
try
    resizeReference = false;
    if strcmp(mode,'Bundled demo')
        current = imread(fullfile(root,'car.jpeg'));
        reference = imread(fullfile(root,'bg.jpeg'));
        % Supplied illustrations depict the same layout at different sizes.
        resizeReference = true;
        layout = demoLayout();
    else
        current = chooseImage('Choose the current parking image');
        if isempty(current), return; end
        reference = chooseImage('Choose an EMPTY reference from the same viewpoint');
        if isempty(reference), return; end
        if size(current,1)~=size(reference,1) || size(current,2)~=size(reference,2)
            answer = questdlg('Image sizes differ. Resize ONLY if both show the same framing and viewpoint.',...
                'Reference size','Resize reference','Cancel','Cancel');
            if ~strcmp(answer,'Resize reference'), return; end
            resizeReference = true;
        end
        choice = questdlg('Mark parking spaces or load a saved layout for this camera.',...
            'Parking layout','Mark spaces','Load layout','Cancel','Mark spaces');
        if isempty(choice) || strcmp(choice,'Cancel'), return; end
        if strcmp(choice,'Load layout')
            [f,p] = uigetfile('*.mat','Load parking layout');
            if isequal(f,0), return; end
            saved = load(fullfile(p,f),'layout');
            if ~isfield(saved,'layout'), error('Layout file does not contain layout.'); end
            layout = saved.layout;
        else
            layout = markSpaces(reference);
            if isempty(layout), return; end
            [f,p] = uiputfile('*.mat','Save layout for reuse','parking_layout.mat');
            if ~isequal(f,0), save(fullfile(p,f),'layout'); end
        end
    end
    settings = inputdlg({'Pixel difference threshold (0–1):','Occupied fraction threshold (0–1):'},...
        'Detection settings',[1 55],{'0.15','0.18'});
    if isempty(settings), return; end
    result = analyzeParking(current,reference,layout,...
        DifferenceThreshold=str2double(settings{1}),...
        OccupancyThreshold=str2double(settings{2}),ResizeReference=resizeReference);
    showResults(current,layout,result);
catch problem
    errordlg(problem.message,'Smart Parking');
end
end

function value = chooseImage(prompt)
[f,p] = uigetfile({'*.jpg;*.jpeg;*.png;*.bmp;*.tif;*.tiff','Image files'},prompt);
value = [];
if ~isequal(f,0)
    [value,map] = imread(fullfile(p,f));
    if ~isempty(map), value = ind2rgb(value,map); end
end
end

function layout = demoLayout()
% Six lanes, six spaces per lane. Gutters exclude the black lane dividers.
xEdges = [0 .512 1]; yEdges = [0 .335 .704 1];
layout = zeros(36,5); i = 0;
for row = 1:3
    for col = 1:2
        lane = (row-1)*2+col;
        step = (xEdges(col+1)-xEdges(col))/6;
        for slot = 1:6
            i = i+1;
            layout(i,:) = [xEdges(col)+(slot-1)*step+.008,...
                yEdges(row)+.02, step-.016,...
                yEdges(row+1)-yEdges(row)-.04,lane];
        end
    end
end
end

function layout = markSpaces(reference)
fig = figure('Name','Mark parking spaces','NumberTitle','off');
cleanup = onCleanup(@() closeIfOpen(fig));
ax = axes(fig); displayImage(ax,reference);
title(ax,'Click two opposite corners per space. Press Enter to finish.');
layout = zeros(0,5); [h,w,~] = size(reference);
while isgraphics(fig)
    figure(fig); axes(ax);
    try
        [x,y,buttons] = ginput(2);
    catch problem
        if ~isgraphics(fig), return; end
        rethrow(problem);
    end
    if numel(x)<2, break; end
    if any(buttons~=1), continue; end
    position = [min(x) min(y) abs(diff(x)) abs(diff(y))];
    if any(position(3:4)<=0), continue; end
    roi = rectangle(ax,'Position',position,'EdgeColor',[0 .7 .5]);
    lane = inputdlg('Lane number (positive integer):','Space lane',1,{'1'});
    if isempty(lane), delete(roi); break; end
    number = str2double(lane{1});
    if ~isfinite(number) || number<1 || number~=fix(number)
        errordlg('Lane must be a positive integer.'); delete(roi); continue;
    end
    % MATLAB image pixel centers start at one; clamp to image boundaries.
    left = max(0,(position(1)-.5)/w); top = max(0,(position(2)-.5)/h);
    right = min(1,(position(1)+position(3)-.5)/w);
    bottom = min(1,(position(2)+position(4)-.5)/h);
    if right<=left || bottom<=top, delete(roi); continue; end
    layout(end+1,:) = [left top right-left bottom-top number]; %#ok<AGROW>
    text(ax,position(1),position(2),sprintf('Space %d | Lane %d',size(layout,1),number),...
        'Color',[0 .5 .3],'BackgroundColor','w','VerticalAlignment','top');
    answer = questdlg('Add another parking space?','Layout','Add space','Finish','Finish');
    if ~strcmp(answer,'Add space'), break; end
end
end

function showResults(current,layout,result)
fig = figure('Name','Smart Parking | Occupancy results','NumberTitle','off','Color','w');
tiledlayout(fig,1,2,'Padding','compact');
ax = nexttile; displayImage(ax,current); hold(ax,'on');
[h,w,~] = size(current);
for i=1:result.Total
    color = [0 .55 .35]; label = 'FREE';
    if result.Spaces.Occupied(i), color = [.85 .18 .18]; label = 'OCC'; end
    p = layout(i,1:4).*[w h w h]; p(1:2) = p(1:2)+.5;
    rectangle(ax,'Position',p,'EdgeColor',color,'LineWidth',2);
    text(ax,p(1),p(2),sprintf('%d %s',i,label),'Color','w',...
        'BackgroundColor',color,'FontSize',8,'VerticalAlignment','top');
end
title(ax,sprintf('%d available / %d spaces',result.Available,result.Total));
axMask = nexttile; displayImage(axMask,result.Mask); title('Changed pixels against empty reference');
if isempty(result.RecommendedLane)
    message = 'No available spaces detected';
else
    message = sprintf('Recommended lane: %d',result.RecommendedLane);
end
sgtitle(sprintf('%s | Image-based estimate',message));
disp(result.Lanes); disp(result.Spaces);
answer = questdlg('Export per-space results as CSV?','Export','Export CSV','Close','Close');
if strcmp(answer,'Export CSV')
    [f,p] = uiputfile('*.csv','Export results','parking_results.csv');
    if ~isequal(f,0), writetable(result.Spaces,fullfile(p,f)); end
end
end

function closeIfOpen(fig)
if isgraphics(fig), close(fig); end
end

function displayImage(ax,value)
% Display grayscale and truecolor images without toolbox functions.
if ismatrix(value)
    limits = [0 1];
    if isinteger(value)
        limits = [double(intmin(class(value))) double(intmax(class(value)))];
    end
    imagesc(ax,value,limits); colormap(ax,gray(256));
else
    image(ax,value);
end
axis(ax,'image'); axis(ax,'off');
set(ax,'YDir','reverse');
end
