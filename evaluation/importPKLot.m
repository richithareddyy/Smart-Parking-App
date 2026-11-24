function importPKLot(root, output, options)
%IMPORTPKLOT Convert the PKLot release into the evaluation manifest format.
% root is the PKLot/PKLot folder containing UFPR04, UFPR05 and PUCPR. Image
% paths in the manifest are relative to root. Each camera's days are split
% chronologically; held-out cameras get setup and test days only.
arguments
    root (1,:) char
    output (1,:) char
    options.HeldOutCameras (1,:) string = "PUCPR"
    options.TrainFraction (1,1) double = .6
    options.ValidationFraction (1,1) double = .2
    options.SetupFraction (1,1) double = .2
    options.ReferenceCandidates (1,1) double = 60
end
files = dir(fullfile(root,'*','*','*','*.jpg'));
if isempty(files), error('Eval:NoImages','No PKLot images found under %s.',root); end
n = numel(files);
camera = strings(n,1); weather = camera; day = camera; stem = camera; image = camera;
for i = 1:n
    parts = split(string(files(i).folder),filesep);
    camera(i) = parts(end-2); weather(i) = parts(end-1); day(i) = parts(end);
    [~,s] = fileparts(files(i).name); stem(i) = s;
    image(i) = join([parts(end-2:end); string(files(i).name)],"/");
end
% Filenames are timestamps, so camera plus stem orders frames chronologically.
[~,order] = sortrows([camera stem]);
camera = camera(order); weather = weather(order); day = day(order);
stem = stem(order); image = image(order); files = files(order);
frame = camera + "/" + stem;
if numel(unique(frame)) ~= n, error('Eval:Frames','Frame identifiers are not unique.'); end
time = replace(extractAfter(stem,11),"_",":");

view = strings(n,1); keep = true(n,1);
labelRows = cell(n,1); viewLayouts = struct('View',{},'Spaces',{});
signatures = containers.Map(); counts = containers.Map();
for i = 1:n
    xmlFile = fullfile(files(i).folder,stem(i) + ".xml");
    spaces = [];
    if isfile(xmlFile), spaces = parseSpaces(fileread(xmlFile)); end
    if isempty(spaces), keep(i) = false; continue; end
    % A new set of annotated contours means the camera was moved or re-aimed.
    contours = cellfun(@(c) string(mat2str(c)),{spaces.contour});
    key = camera(i) + "|" + join(string([spaces.id]) + ":" + contours,"|");
    if ~isKey(signatures,key)
        k = 1; if isKey(counts,camera(i)), k = counts(camera(i))+1; end
        counts(camera(i)) = k;
        signatures(key) = camera(i) + "-" + k;
        viewLayouts(end+1) = struct('View',signatures(key),'Spaces',spaces); %#ok<AGROW>
    end
    view(i) = signatures(key);
    labelRows{i} = table(repmat(frame(i),numel(spaces),1),[spaces.id]',[spaces.occupied]',...
        'VariableNames',{'Frame','Space','Occupied'});
end
frames = table(frame,camera,view,day,time,weather,image,...
    'VariableNames',{'Frame','Camera','View','Day','Time','Weather','Image'});
frames = frames(keep,:);
labels = vertcat(labelRows{keep});

spaces = cell(numel(viewLayouts),1);
for v = 1:numel(viewLayouts)
    sample = frames.Image(find(frames.View==viewLayouts(v).View,1));
    info = imfinfo(fullfile(root,sample));
    spaces{v} = layoutTable(viewLayouts(v).View,viewLayouts(v).Spaces,info.Width,info.Height);
end
spaces = vertcat(spaces{:});

splits = assignSplits(frames,options);
references = chooseReferences(frames,labels,splits,root,options.ReferenceCandidates);

if ~isfolder(output), mkdir(output); end
writetable(frames,fullfile(output,'frames.csv'));
writetable(labels,fullfile(output,'labels.csv'));
writetable(spaces,fullfile(output,'spaces.csv'));
writetable(splits,fullfile(output,'splits.csv'));
writetable(references,fullfile(output,'references.csv'));
provenance = struct('Dataset','PKLot',...
    'Source','https://web.inf.ufpr.br/vri/databases/parking-lot-database/',...
    'Archive','https://www.inf.ufpr.br/vri/databases/PKLot.tar.gz',...
    'License','CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)',...
    'Citation',['Almeida, P., Oliveira, L. S., Silva Jr, E., Britto Jr, A., Koerich, A. ' ...
        'PKLot - A robust dataset for parking lot classification. ' ...
        'Expert Systems with Applications, 42(11):4937-4949, 2015.'],...
    'Imported',char(datetime('now','Format','yyyy-MM-dd')),...
    'Frames',height(frames),'SkippedFrames',nnz(~keep),...
    'Labels',height(labels),'MissingLabels',nnz(isnan(labels.Occupied)),...
    'HeldOutCameras',options.HeldOutCameras,...
    'SplitRule',sprintf(['Per camera, days sorted by name: first %g train, next %g validation, ' ...
        'rest test. Held-out cameras: first %g setup, rest test.'],...
        options.TrainFraction,options.ValidationFraction,options.SetupFraction),...
    'ReferenceRule',['Per view, among fully labeled all-vacant frames from non-test days, ' ...
        'the frame whose mean brightness is closest to the median of that view''s non-test frames.']);
fid = fopen(fullfile(output,'dataset.json'),'w');
fprintf(fid,'%s\n',jsonencode(provenance,'PrettyPrint',true)); fclose(fid);
fprintf('%d frames, %d views, %d labels (%d missing), %d frames skipped\n',height(frames),...
    numel(viewLayouts),height(labels),nnz(isnan(labels.Occupied)),nnz(~keep));
end

function spaces = parseSpaces(text)
blocks = regexpi(text,'<space\s[^>]*>.*?</space>','match');
spaces = struct('id',{},'occupied',{},'contour',{});
for b = blocks
    head = regexpi(b{1},'<space\s[^>]*>','match','once');
    id = str2double(regexpi(head,'id="(\d+)"','tokens','once'));
    occupied = str2double(regexpi(head,'occupied="(\d)"','tokens','once'));
    if isempty(occupied), occupied = NaN; end
    points = regexpi(b{1},'<point x="(-?\d+)" y="(-?\d+)"','tokens');
    contour = str2double(vertcat(points{:}));
    if isempty(id) || isnan(id) || size(contour,1) < 3, continue; end
    spaces(end+1) = struct('id',id,'occupied',occupied,'contour',contour); %#ok<AGROW>
end
[~,order] = sort([spaces.id]); spaces = spaces(order);
end

function t = layoutTable(view,spaces,width,height)
n = numel(spaces); box = zeros(n,4); contour = strings(n,1);
for s = 1:n
    c = spaces(s).contour;
    x = min(max(c(:,1),0),width); y = min(max(c(:,2),0),height);
    box(s,:) = [min(x)/width min(y)/height (max(x)-min(x))/width (max(y)-min(y))/height];
    contour(s) = join(compose("%d %d",c),";");
end
[overlap,area] = boxOverlap(box,width,height);
t = table(repmat(view,n,1),[spaces.id]',box(:,1),box(:,2),box(:,3),box(:,4),ones(n,1),...
    area,overlap,contour,'VariableNames',{'View','Space','X','Y','Width','Height','Lane',...
    'Area','NeighborOverlap','Contour'});
end

function [overlap,area] = boxOverlap(box,width,height)
% Pixel bounds follow analyzeParking: partially covered edge pixels count.
n = size(box,1); masks = false(height,width,n);
for s = 1:n
    x1 = max(1,floor(box(s,1)*width)+1); x2 = min(width,ceil((box(s,1)+box(s,3))*width));
    y1 = max(1,floor(box(s,2)*height)+1); y2 = min(height,ceil((box(s,2)+box(s,4))*height));
    masks(y1:y2,x1:x2,s) = true;
end
coverage = sum(masks,3);
area = zeros(n,1); overlap = zeros(n,1);
for s = 1:n
    inside = masks(:,:,s);
    area(s) = nnz(inside);
    overlap(s) = nnz(coverage(inside) > 1)/area(s);
end
end

function splits = assignSplits(frames,options)
[keys,~,group] = unique(frames(:,{'Camera','Day'}));
keys.Frames = accumarray(group,1);
keys.Weather = splitapply(@(w) join(unique(w),";"),frames.Weather,group);
keys.Split = strings(height(keys),1);
for c = unique(keys.Camera)'
    rows = find(keys.Camera==c);
    [~,order] = sort(keys.Day(rows)); rows = rows(order);
    n = numel(rows);
    if ismember(c,options.HeldOutCameras)
        nSetup = max(1,round(options.SetupFraction*n));
        keys.Split(rows) = [repmat("setup",nSetup,1); repmat("test",n-nSetup,1)];
    else
        nTrain = max(1,round(options.TrainFraction*n));
        nVal = max(1,round(options.ValidationFraction*n));
        if nTrain+nVal >= n, error('Eval:Split','Camera %s has too few days to split.',c); end
        keys.Split(rows) = [repmat("train",nTrain,1); repmat("validation",nVal,1);...
            repmat("test",n-nTrain-nVal,1)];
    end
end
splits = keys(:,{'Camera','Day','Split','Frames','Weather'});
end

function references = chooseReferences(frames,labels,splits,root,candidates)
frames = join(frames,splits(:,{'Camera','Day','Split'}));
[g,ids] = findgroups(labels.Frame);
vacant = splitapply(@(o) all(o==0),labels.Occupied,g);
views = unique(frames.View);
rows = cell(numel(views),1);
for v = 1:numel(views)
    pool = frames(frames.View==views(v) & frames.Split~="test",:);
    if isempty(pool), error('Eval:Reference','View %s has no non-test frames.',views(v)); end
    vacantPool = pool(ismember(pool.Frame,ids(vacant)),:);
    if isempty(vacantPool), error('Eval:Reference','View %s has no fully vacant non-test frame.',views(v)); end
    typical = median(arrayfun(@(i) brightness(root,i),sample(pool.Image,candidates)));
    picks = sample(vacantPool.Frame,candidates);
    level = arrayfun(@(f) brightness(root,vacantPool.Image(vacantPool.Frame==f)),picks);
    [~,best] = min(abs(level-typical));
    chosen = vacantPool(vacantPool.Frame==picks(best),:);
    rows{v} = table(views(v),chosen.Frame,chosen.Image,chosen.Day,chosen.Split,level(best),typical,...
        'VariableNames',{'View','Frame','Image','Day','Split','Brightness','PoolMedianBrightness'});
end
references = vertcat(rows{:});
end

function values = sample(values,k)
if numel(values) > k, values = values(unique(round(linspace(1,numel(values),k)))); end
end

function value = brightness(root,image)
value = mean(grayFrame(imread(fullfile(root,image))),'all');
end
