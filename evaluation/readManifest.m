function m = readManifest(folder)
%READMANIFEST Load and validate an evaluation manifest folder.
% See evaluation/README.md for the format. Errors with Eval:Manifest when a
% file is missing or a split, label, layout or reference rule is violated.
required = struct(...
    'frames',{{'Frame','Camera','View','Day','Time','Weather','Image'}},...
    'labels',{{'Frame','Space','Occupied'}},...
    'spaces',{{'View','Space','X','Y','Width','Height','Lane','Area','NeighborOverlap'}},...
    'splits',{{'Camera','Day','Split'}},...
    'references',{{'View','Frame','Image'}});
for name = string(fieldnames(required))'
    file = fullfile(folder,name + ".csv");
    if ~isfile(file), fail('Missing %s.',file); end
    t = readtable(file,'TextType','string','DatetimeType','text','DurationType','text',...
        'Delimiter',',');
    missing = setdiff(required.(name),t.Properties.VariableNames);
    if ~isempty(missing), fail('%s.csv lacks columns: %s.',name,strjoin(missing,', ')); end
    for column = intersect({'Frame','Camera','View','Day','Time','Weather','Image','Split'},...
            t.Properties.VariableNames)
        t.(column{1}) = string(t.(column{1}));
    end
    m.(name) = t;
end
datasetFile = fullfile(folder,'dataset.json');
if ~isfile(datasetFile), fail('Missing %s.',datasetFile); end
m.dataset = jsondecode(fileread(datasetFile));

f = m.frames; l = m.labels; s = m.spaces; p = m.splits; r = m.references;
if numel(unique(f.Frame)) ~= height(f), fail('Frame identifiers must be unique.'); end
if ~all(ismember(l.Frame,f.Frame)), fail('Labels refer to unknown frames.'); end
if height(unique(l(:,{'Frame','Space'}))) ~= height(l), fail('Duplicate labels.'); end
if ~all(ismember(l.Occupied(~isnan(l.Occupied)),[0 1])), fail('Occupied must be 0, 1 or empty.'); end
if height(unique(s(:,{'View','Space'}))) ~= height(s), fail('Duplicate spaces.'); end
box = [s.X s.Y s.Width s.Height];
if any(box(:,1:2)<0,'all') || any(box(:,3:4)<=0,'all') || any(box(:,1:2)+box(:,3:4)>1+1e-10,'all')
    fail('Space regions must lie inside the image.');
end
[~,where] = ismember(l.Frame,f.Frame);
if ~all(ismember(table(f.View(where),l.Space,'VariableNames',{'View','Space'}),s(:,{'View','Space'})))
    fail('Labels refer to spaces missing from their view.');
end

if height(unique(p(:,{'Camera','Day'}))) ~= height(p), fail('Each camera day needs exactly one split.'); end
if ~all(ismember(p.Split,["train" "validation" "test" "setup"])), fail('Unknown split name.'); end
if ~all(ismember(f(:,{'Camera','Day'}),p(:,{'Camera','Day'}))), fail('Some frames have no split.'); end
heldOut = unique(p.Camera(p.Split=="setup"));
if any(ismember(p.Camera(ismember(p.Split,["train" "validation"])),heldOut))
    fail('A held-out camera also has training or validation days.');
end

views = unique(f.View);
if numel(unique(r.View)) ~= height(r) || ~all(ismember(views,r.View))
    fail('Each view needs exactly one reference.');
end
[known,where] = ismember(r.Frame,f.Frame);
if ~all(known), fail('References must be manifest frames.'); end
refFrames = f(where,:);
if ~all(refFrames.View==r.View), fail('A reference comes from a different view.'); end
refSplit = join(refFrames(:,{'Camera','Day'}),p);
if any(refSplit.Split=="test"), fail('References must not come from test days.'); end
refLabels = l(ismember(l.Frame,r.Frame),:);
if any(refLabels.Occupied ~= 0), fail('References must be labeled fully vacant.'); end
end

function fail(varargin)
error('Eval:Manifest',varargin{:});
end
