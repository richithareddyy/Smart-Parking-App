function result = analyzeParking(current, reference, layout, options)
%ANALYZEPARKING Compare marked spaces against an empty, aligned reference.
% Layout columns: normalized x, y, width, height, positive integer lane.
arguments
    current
    reference
    layout (:,5) double
    options.DifferenceThreshold (1,1) double = 0.15
    options.OccupancyThreshold (1,1) double = 0.18
    options.ResizeReference (1,1) logical = false
end
validateattributes(layout, {'double'}, {'nonempty','finite','real'});
if any(layout(:,1:2)<0,'all') || any(layout(:,3:4)<=0,'all') || ...
        any(layout(:,1:2)+layout(:,3:4)>1+1e-10,'all') || ...
        any(layout(:,5)<1 | layout(:,5)~=fix(layout(:,5)))
    error('Parking:Layout','Regions must fit inside the image; lanes must be positive integers.');
end
validateattributes(options.DifferenceThreshold, {'double'}, {'finite','>',0,'<=',1});
validateattributes(options.OccupancyThreshold, {'double'}, {'finite','>',0,'<=',1});
a = grayImage(current); b = grayImage(reference);
if ~isequal(size(a),size(b))
    if ~options.ResizeReference
        error('Parking:Size','Image sizes differ. Use aligned images or explicitly enable reference resizing.');
    end
    % Pixel-center bilinear resampling using base MATLAB interpolation.
    [bh,bw] = size(b); [ah,aw] = size(a);
    x = min(bw,max(1,((1:aw)-.5)*bw/aw+.5));
    y = min(bh,max(1,((1:ah)-.5)*bh/ah+.5));
    % Duplicate singleton dimensions so interp2 always has a 2-D grid.
    if bh==1, b = [b;b]; end
    if bw==1, b = [b b]; end
    [xx,yy] = meshgrid(x,y);
    b = interp2(b,xx,yy,'linear');
end
% A small median filter suppresses isolated compression and sensor artifacts.
difference = abs(a-b);
binary = difference > options.DifferenceThreshold;
% A binary 3-by-3 median is a majority vote. Replicate boundary pixels.
[rows,cols] = size(binary);
padded = binary([1 1:rows rows],[1 1:cols cols]);
mask = conv2(double(padded),ones(3),'valid') >= 5;
[h,w] = size(a);
n = size(layout,1); fraction = zeros(n,1);
for i = 1:n
    x1 = max(1,floor(layout(i,1)*w)+1);
    y1 = max(1,floor(layout(i,2)*h)+1);
    x2 = min(w,ceil((layout(i,1)+layout(i,3))*w));
    y2 = min(h,ceil((layout(i,2)+layout(i,4))*h));
    region = mask(y1:y2,x1:x2);
    fraction(i) = nnz(region)/numel(region);
end
occupied = fraction >= options.OccupancyThreshold;
result.Spaces = table((1:n)',layout(:,5),fraction,occupied,...
    'VariableNames',{'Space','Lane','ChangedFraction','Occupied'});
result.Total = n;
result.Occupied = nnz(occupied);
result.Available = n-result.Occupied;
result.Mask = mask;
result.ReferenceResized = ~isequal(size(grayImage(reference)),size(a));
lanes = unique(layout(:,5));
free = arrayfun(@(lane) nnz(~occupied & layout(:,5)==lane),lanes);
result.Lanes = table(lanes,free,'VariableNames',{'Lane','Available'});
% Preserve the original preference for the highest numbered available lane.
result.RecommendedLane = [];
if any(free>0), result.RecommendedLane = max(lanes(free>0)); end
end

function gray = grayImage(input)
if ~(isnumeric(input) || islogical(input)) || isempty(input) || ~isreal(input) || ...
        any(~isfinite(input),'all') || ~(ismatrix(input) || (ndims(input)==3 && size(input,3)==3))
    error('Parking:Image','Use a nonempty grayscale or RGB image.');
end
if isfloat(input) && (any(input<0,'all') || any(input>1,'all'))
    error('Parking:Range','Floating-point images must be in the range 0 to 1.');
end
if ~isa(input,'uint8') && ~isa(input,'uint16') && ~isa(input,'int16') && ...
        ~isfloat(input) && ~islogical(input)
    error('Parking:Image','Supported image types: uint8, uint16, int16, single, double, logical.');
end
gray = double(input);
if isinteger(input)
    low = double(intmin(class(input))); high = double(intmax(class(input)));
    gray = (gray-low)/(high-low);
end
if size(gray,3)==3
    gray = .298936021293775*gray(:,:,1) + .587043074451121*gray(:,:,2) + ...
        .114020904255103*gray(:,:,3);
end
end
