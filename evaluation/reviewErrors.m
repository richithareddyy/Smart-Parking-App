function reviewErrors(predictions, manifest, root, output, count)
%REVIEWERRORS Write contact sheets of sampled test errors for manual tagging.
% Draws up to count errors per setting, group and error type, at most one per
% camera day. Each tile shows the space in the frame beside its reference.
arguments
    predictions (1,:) char
    manifest (1,:) char
    root (1,:) char
    output (1,:) char
    count (1,1) double = 10
end
m = readManifest(manifest);
p = readtable(predictions,'TextType','string','DatetimeType','text','DurationType','text','Delimiter',',');
stream = RandStream('mt19937ar','Seed',1);
index = table();
for setting = ["ReferenceTuned" "AdaptiveTuned"]
    predicted = p.(setting + "Predicted")==1; truth = p.Occupied==1;
    for group = ["test" "held-out test"]
        for type = ["false free" "false occupied"]
            if type=="false free", wrong = truth & ~predicted; else, wrong = ~truth & predicted; end
            rows = find(wrong & p.Group==group);
            rows = rows(randperm(stream,numel(rows)));
            [~,first] = unique(p(rows,{'Camera','Day'}),'stable');
            rows = rows(first(1:min(count,numel(first))));
            part = p(rows,{'Frame','Space','Camera','View','Day','Time','Weather','Image','Group'});
            part.Setting(:) = setting; part.Error(:) = type;
            part.ChangedFraction = p.(setting + "Fraction")(rows);
            index = [index; part]; %#ok<AGROW>
        end
    end
end
index.Tile = (1:height(index))';
index.Cause(:) = "";
if ~isfolder(output), mkdir(output); end
writetable(index,fullfile(output,'review.csv'));
perSheet = 20;
for sheet = 1:ceil(height(index)/perSheet)
    page = zeros(5*210,4*420,3,'uint8');
    for k = 1:perSheet
        i = (sheet-1)*perSheet+k;
        if i > height(index), break; end
        space = m.spaces(m.spaces.View==index.View(i) & m.spaces.Space==index.Space(i),:);
        reference = m.references.Image(m.references.View==index.View(i));
        tile = [crop(imread(fullfile(root,index.Image(i))),space) crop(imread(fullfile(root,reference)),space)];
        y = floor((k-1)/4)*210; x = mod(k-1,4)*420;
        page(y+(1:200),x+(1:400),:) = tile;
    end
    imwrite(page,fullfile(output,sprintf('sheet%d.png',sheet)));
end
end

function tile = crop(image,space)
% Square crop around the space with the annotation box drawn in yellow.
[h,w,~] = size(image);
box = [space.X*w space.Y*h space.Width*w space.Height*h];
side = 1.8*max(box(3:4)); center = box(1:2)+box(3:4)/2;
x = round(min(max(linspace(center(1)-side/2,center(1)+side/2,200),1),w));
y = round(min(max(linspace(center(2)-side/2,center(2)+side/2,200),1),h));
tile = image(y,x,:);
scale = 200/side; left = round((box(1)-center(1)+side/2)*scale)+1; top = round((box(2)-center(2)+side/2)*scale)+1;
right = min(200,left+round(box(3)*scale)); bottom = min(200,top+round(box(4)*scale));
left = max(1,left); top = max(1,top);
edges = false(200); edges([top bottom],left:right) = true; edges(top:bottom,[left right]) = true;
for c = 1:3
    plane = tile(:,:,c); plane(edges) = 255*(c<3); tile(:,:,c) = plane;
end
end
