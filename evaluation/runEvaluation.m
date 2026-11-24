function runEvaluation(manifest, root, output, options)
%RUNEVALUATION Compare the fixed-reference detector with an adaptive baseline.
% Settings are chosen on training days only. Validation days check them, then
% test days and held-out cameras are scored. Later views of a moved camera
% are also scored with the camera's first reference and layout.
arguments
    manifest (1,:) char
    root (1,:) char
    output (1,:) char
    options.DifferenceThresholds (1,:) double = [.05 .075 .1 .125 .15 .2 .25 .3]
    options.OccupancyThresholds (1,:) double = (1:45)/50
    options.LearningRates (1,:) double = [.02 .05 .1 .2]
    options.RoiScales (1,:) double = [1 .75 .5]
    options.Predictions (1,:) char = ''
end
if ~ismember(.15,options.DifferenceThresholds) || ~ismember(.18,options.OccupancyThresholds) ...
        || ~ismember(1,options.RoiScales)
    error('Eval:Grid','The grids must include the app defaults 0.15 and 0.18, and ROI scale 1.');
end
m = readManifest(manifest);
if ~isfolder(output), mkdir(output); end
obs = observations(m);
references = containers.Map();
for v = 1:height(m.references)
    references(m.references.View(v)) = imread(fullfile(root,m.references.Image(v)));
end

d = options.DifferenceThresholds(:);
[dd,aa] = ndgrid(d,options.LearningRates(:));
detectors = table([repmat("Reference",numel(d),1); repmat("Adaptive",numel(dd),1)],...
    [d; dd(:)],[zeros(numel(d),1); aa(:)],...
    'VariableNames',{'Method','DifferenceThreshold','LearningRate'});
train = obs(obs.Group=="train",:);
fprintf('Tuning on %d training frames\n',numel(unique(train.Frame)));
[trainFractions,~,grid] = scoreFrames(train,detectors,options.RoiScales,m,references,root,false);
[tuning,settings] = tune(train.Occupied,trainFractions,grid,options.OccupancyThresholds);
writetable(tuning,fullfile(output,'tuning.csv'));
writetable(settings,fullfile(output,'settings.csv'));
disp(settings);
key = {'Method','DifferenceThreshold','LearningRate','RoiScale'};
[~,column] = ismember(settings(:,key),grid(:,key));
trainPredictions = trainFractions(:,column) >= settings.OccupancyThreshold';
clear trainFractions

scored = [obs(ismember(obs.Group,["validation" "test" "held-out test"]),:); staleSetup(obs,m)];
chosen = unique(settings(:,key(1:3)),'stable');
fprintf('Scoring %d frames\n',numel(unique(scored.Frame)));
[fractions,stats,grid] = scoreFrames(scored,chosen,options.RoiScales,m,references,root,true);
[~,column] = ismember(settings(:,key),grid(:,key));
fractions = fractions(:,column);
predictions = fractions >= settings.OccupancyThreshold';

scored = addFactors(join(scored,stats));
all = [train(:,{'Camera','Day','Group','Occupied'}); scored(:,{'Camera','Day','Group','Occupied'})];
allPredictions = [trainPredictions; predictions];
writetable(dayIntervals(groupMetrics(all,allPredictions,settings,"Group"),all,allPredictions,settings),...
    fullfile(output,'summary.csv'));
writetable(byDay(all,allPredictions,settings),fullfile(output,'per_day.csv'));
test = ismember(scored.Group,["test" "held-out test"]);
conditions = table();
for group = ["test" "held-out test"]
    in = scored.Group==group;
    part = groupMetrics(scored(in,:),predictions(in,:),settings,...
        ["Camera" "Weather" "Hour" "Lighting" "Shift" "Overlap" "Size"]);
    conditions = [conditions; addvars(part,repmat(group,height(part),1),...
        'Before','Factor','NewVariableNames','Group')]; %#ok<AGROW>
end
writetable(conditions,fullfile(output,'conditions.csv'));
writetable(perSpace(scored(test,:),predictions(test,:),settings),fullfile(output,'per_space.csv'));
writetable(benchmark(scored(test,:),settings,m,references,root),fullfile(output,'runtime.csv'));
writeEnvironment(fullfile(output,'environment.json'),m,obs,options);
if ~isempty(options.Predictions)
    out = scored;
    for s = 1:height(settings)
        name = matlab.lang.makeValidName(settings.Setting(s));
        out.(name + "Fraction") = fractions(:,s);
        out.(name + "Predicted") = predictions(:,s);
    end
    writetable(out,options.Predictions);
end
end

function obs = observations(m)
frames = join(m.frames,m.splits(:,{'Camera','Day','Split'}));
heldOut = unique(m.splits.Camera(m.splits.Split=="setup"));
frames.Group = frames.Split;
frames.Group(frames.Split=="test" & ismember(frames.Camera,heldOut)) = "held-out test";
obs = innerjoin(m.labels(~isnan(m.labels.Occupied),:),frames,'Keys','Frame');
obs.Occupied = logical(obs.Occupied);
obs.SetupView = obs.View;
obs = addSpaceInfo(obs,m);
end

function stale = staleSetup(obs,m)
% Score later views of a camera with its first view's reference and layout.
ordered = sortrows(m.frames,{'Camera','Day','Time'});
[cameras,first] = unique(ordered.Camera);
stale = obs(obs.Group=="test",:);
[~,where] = ismember(stale.Camera,cameras);
stale.SetupView = ordered.View(first(where));
stale = stale(stale.SetupView ~= stale.View,:);
stale.Group(:) = "stale setup";
stale = addSpaceInfo(removevars(stale,{'Area','NeighborOverlap'}),m);
end

function obs = addSpaceInfo(obs,m)
obs = innerjoin(obs,m.spaces,'LeftKeys',{'SetupView','Space'},'RightKeys',{'View','Space'},...
    'RightVariables',{'Area','NeighborOverlap'});
obs = sortrows(obs,{'SetupView','Day','Time','Space'});
end

function [fractions,stats,grid] = scoreFrames(obs,detectors,scales,m,references,root,measure)
% One column per detector and ROI scale. The background only depends on the
% detector, so all scales are measured in a single analyzeParking call.
nd = height(detectors); ns = numel(scales);
grid = repmat(detectors,ns,1);
grid.RoiScale = repelem(scales(:),nd);
fractions = NaN(height(obs),nd*ns);
[g,keys] = findgroups(obs(:,{'SetupView','Day','Time','Frame'}));
rowsByFrame = splitapply(@(i) {i},(1:height(obs))',g);
[~,where] = ismember(keys.Frame,m.frames.Frame);
images = m.frames.Image(where);
n = height(keys);
stats = keys(:,{'Frame','SetupView'});
stats.Brightness = NaN(n,1); stats.ReferenceBrightness = NaN(n,1);
stats.ShiftX = NaN(n,1); stats.ShiftY = NaN(n,1);
sequence = ""; started = tic;
for k = 1:n
    if keys.SetupView(k) + "|" + keys.Day(k) ~= sequence
        sequence = keys.SetupView(k) + "|" + keys.Day(k);
        reference = grayFrame(references(keys.SetupView(k)));
        spaces = m.spaces(m.spaces.View==keys.SetupView(k),:);
        layout = scaledLayout(spaces,scales);
        backgrounds = repmat({reference},nd,1);
    end
    frame = grayFrame(imread(fullfile(root,images(k))));
    rows = rowsByFrame{k};
    [~,index] = ismember(obs.Space(rows),spaces.Space);
    for c = 1:nd
        threshold = detectors.DifferenceThreshold(c);
        r = analyzeParking(frame,backgrounds{c},layout,DifferenceThreshold=threshold);
        if detectors.LearningRate(c) > 0
            backgrounds{c} = updateBackground(backgrounds{c},frame,threshold,detectors.LearningRate(c));
        end
        changed = reshape(r.Spaces.ChangedFraction,height(spaces),ns);
        fractions(rows,c:nd:end) = changed(index,:);
    end
    if measure
        stats.Brightness(k) = mean(frame,'all');
        stats.ReferenceBrightness(k) = mean(reference,'all');
        shift = estimateShift(frame,reference);
        stats.ShiftX(k) = shift(1); stats.ShiftY(k) = shift(2);
    end
    if mod(k,250)==0 || k==n, fprintf('  %d/%d frames, %.0f s\n',k,n,toc(started)); end
end
end

function layout = scaledLayout(spaces,scales)
layout = [];
for s = scales
    layout = [layout; spaces.X+spaces.Width*(1-s)/2 spaces.Y+spaces.Height*(1-s)/2 ...
        spaces.Width*s spaces.Height*s spaces.Lane]; %#ok<AGROW>
end
end

function [tuning,settings] = tune(truth,fractions,grid,occupancy)
rows = cell(height(grid),numel(occupancy));
for c = 1:height(grid)
    for o = 1:numel(occupancy)
        rows{c,o} = [grid(c,:) table(occupancy(o),'VariableNames',{'OccupancyThreshold'}) ...
            parkingMetrics(truth,fractions(:,c) >= occupancy(o))];
    end
end
tuning = vertcat(rows{:});
default = tuning(tuning.Method=="Reference" & tuning.DifferenceThreshold==.15 & ...
    tuning.OccupancyThreshold==.18,:);
settings = [default(default.RoiScale==1,:); best(default); ...
    best(tuning(tuning.Method=="Reference",:)); best(tuning(tuning.Method=="Adaptive",:))];
settings = settings(:,{'Method','DifferenceThreshold','LearningRate','RoiScale',...
    'OccupancyThreshold','BalancedAccuracy'});
settings.Properties.VariableNames{end} = 'TrainBalancedAccuracy';
settings = addvars(settings,["Reference default"; "Reference default thresholds, tuned ROI"; ...
    "Reference tuned"; "Adaptive tuned"],'Before',1,'NewVariableNames','Setting');
end

function row = best(t)
% Ties go to fewer false-free errors, then lower settings.
t.Score = -round(t.BalancedAccuracy,12);
t = sortrows(t,{'Score','FalseFreeRate','DifferenceThreshold','LearningRate',...
    'OccupancyThreshold','RoiScale'});
row = removevars(t(1,:),'Score');
end

function t = groupMetrics(obs,predictions,settings,factors)
rows = {};
for s = 1:height(settings)
    for factor = factors
        [g,levels] = findgroups(obs.(factor));
        for k = 1:numel(levels)
            in = g==k;
            rows{end+1,1} = [table(settings.Setting(s),factor,levels(k),...
                'VariableNames',{'Setting','Factor','Level'}) ...
                parkingMetrics(obs.Occupied(in),predictions(in,s))]; %#ok<AGROW>
        end
    end
end
t = vertcat(rows{:});
end

function t = byDay(obs,predictions,settings)
[g,keys] = findgroups(obs(:,{'Group','Camera','Day'}));
rows = {};
for s = 1:height(settings)
    for k = 1:height(keys)
        in = g==k;
        rows{end+1,1} = [table(settings.Setting(s),'VariableNames',{'Setting'}) keys(k,:) ...
            parkingMetrics(obs.Occupied(in),predictions(in,s))]; %#ok<AGROW>
    end
end
t = vertcat(rows{:});
end

function summary = dayIntervals(summary,obs,predictions,settings)
% Percentile intervals from resampling whole camera days, because frames a
% few minutes apart are far from independent.
days = byDay(obs,predictions,settings);
summary.Days = zeros(height(summary),1);
summary.BalancedAccuracyLow = NaN(height(summary),1);
summary.BalancedAccuracyHigh = NaN(height(summary),1);
for i = 1:height(summary)
    d = days(days.Setting==summary.Setting(i) & days.Group==summary.Level(i),:);
    summary.Days(i) = height(d);
    counts = [d.TrueOccupied d.FalseFree d.TrueFree d.FalseOccupied];
    stream = RandStream('mt19937ar','Seed',1);
    value = NaN(2000,1);
    for b = 1:2000
        c = sum(counts(randi(stream,height(d),height(d),1),:),1);
        value(b) = (c(1)/(c(1)+c(2))+c(3)/(c(3)+c(4)))/2;
    end
    value = sort(value(~isnan(value)));
    if ~isempty(value)
        summary.BalancedAccuracyLow(i) = value(max(1,round(.025*numel(value))));
        summary.BalancedAccuracyHigh(i) = value(max(1,round(.975*numel(value))));
    end
end
end

function obs = addFactors(obs)
hour = str2double(extractBefore(obs.Time,3));
obs.Hour = binLabels(hour,[0 9 12 15 18 24],["before 09" "09-12" "12-15" "15-18" "18 and later"]);
change = obs.Brightness-obs.ReferenceBrightness;
obs.Lighting = binLabels(change,[-Inf -.1 -.05 .05 .1 Inf],...
    ["darker by >0.10" "darker by 0.05-0.10" "within 0.05" "brighter by 0.05-0.10" "brighter by >0.10"]);
obs.Shift = binLabels(hypot(obs.ShiftX,obs.ShiftY),[0 .5 2.5 5.5 Inf],["0 px" "1-2 px" "3-5 px" ">5 px"]);
obs.Overlap = binLabels(obs.NeighborOverlap,[0 1e-9 .25 .5 Inf],["none" "<25%" "25-50%" ">=50%"]);
obs.Size = binLabels(obs.Area,[0 2500 5000 10000 Inf],["<2500 px" "2500-5000 px" "5000-10000 px" ">=10000 px"]);
end

function labels = binLabels(values,edges,names)
labels = reshape(names(discretize(values,edges)),[],1);
end

function t = perSpace(obs,predictions,settings)
[g,keys] = findgroups(obs(:,{'Group','View','Space','Area','NeighborOverlap'}));
rows = {};
for s = 1:height(settings)
    for k = 1:height(keys)
        in = g==k;
        rows{end+1,1} = [table(settings.Setting(s),'VariableNames',{'Setting'}) keys(k,:) ...
            parkingMetrics(obs.Occupied(in),predictions(in,s))]; %#ok<AGROW>
    end
end
t = vertcat(rows{:});
end

function t = benchmark(obs,settings,m,references,root)
% Time the app's own call on RGB images, one layout, up to 200 frames.
[frames,first] = unique(obs.Frame);
pick = unique(round(linspace(1,numel(frames),min(200,numel(frames)))));
tuned = settings(settings.Method=="Adaptive",:);
ms = NaN(numel(pick),3);
for k = 1:numel(pick)
    row = obs(first(pick(k)),:);
    spaces = m.spaces(m.spaces.View==row.View,:);
    layout = [spaces.X spaces.Y spaces.Width spaces.Height spaces.Lane];
    reference = references(row.View); background = grayFrame(reference);
    t0 = tic; image = imread(fullfile(root,row.Image)); ms(k,1) = toc(t0)*1000;
    t0 = tic; analyzeParking(image,reference,layout); ms(k,2) = toc(t0)*1000;
    t0 = tic; gray = grayFrame(image);
    analyzeParking(gray,background,layout,DifferenceThreshold=tuned.DifferenceThreshold);
    updateBackground(background,gray,tuned.DifferenceThreshold,tuned.LearningRate);
    ms(k,3) = toc(t0)*1000;
end
ms = sort(ms,1);
t = table(["Image read"; "Reference detector"; "Adaptive baseline"],median(ms,1)',...
    ms(max(1,ceil(.95*size(ms,1))),:)',repmat(numel(pick),3,1),...
    'VariableNames',{'Step','MedianMs','P95Ms','Frames'});
end

function writeEnvironment(file,m,obs,options)
[~,cpu] = system('sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m');
info = struct('MATLAB',version,'Computer',computer,'CPU',strtrim(cpu),...
    'Threads',maxNumCompThreads,'Run',char(datetime('now','Format','yyyy-MM-dd HH:mm')),...
    'Dataset',m.dataset.Dataset,'Frames',numel(unique(obs.Frame)),'LabeledObservations',height(obs),...
    'DifferenceThresholds',options.DifferenceThresholds,'OccupancyThresholds',options.OccupancyThresholds,...
    'LearningRates',options.LearningRates,'RoiScales',options.RoiScales);
fid = fopen(file,'w'); fprintf(fid,'%s\n',jsonencode(info,'PrettyPrint',true)); fclose(fid);
end
