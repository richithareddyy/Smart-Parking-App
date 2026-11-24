function tests = testParking
tests = functiontests(localfunctions);
assert(~isempty(tests),'Parking:NoTests','No tests found in testParking.m.');
end
function testEmptyAndFull(testCase)
layout = [0 0 .5 1 1; .5 0 .5 1 2];
background = zeros(60,80,'uint8');
r = analyzeParking(background,background,layout);
verifyEqual(testCase,r.Available,2);
verifyEqual(testCase,r.RecommendedLane,2);
r = analyzeParking(255*ones(60,80,'uint8'),background,layout);
verifyEqual(testCase,r.Available,0);
verifyEmpty(testCase,r.RecommendedLane);
end
function testOneOccupiedAndDeterministic(testCase)
b = zeros(60,80,'uint8'); a = b; a(:,1:40)=255;
l = [0 0 .5 1 1; .5 0 .5 1 2];
r = analyzeParking(a,b,l); s = analyzeParking(a,b,l);
verifyEqual(testCase,r.Spaces.Occupied,[true;false]);
verifyEqual(testCase,r.Spaces,s.Spaces);
verifyEqual(testCase,r.Occupied+r.Available,r.Total);
end
function testValidation(testCase)
b = zeros(30,40,'uint8'); l = [0 0 1 1 1];
verifyError(testCase,@() analyzeParking(b,zeros(10,'uint8'),l),'Parking:Size');
verifyError(testCase,@() analyzeParking(b,b,[0 0 2 1 1]),'Parking:Layout');
verifyError(testCase,@() analyzeParking(2*ones(30,40),b,l),'Parking:Range');
r = analyzeParking(b,zeros(10,'uint8'),l,ResizeReference=true);
verifyTrue(testCase,r.ReferenceResized);
end
function testGrayscaleAndRgb(testCase)
b = zeros(30,40,'uint8'); l = [0 0 1 1 1];
r = analyzeParking(repmat(b,1,1,3),b,l);
verifyEqual(testCase,r.Available,1);
end
function testIsolatedNoiseAndBoundary(testCase)
b = zeros(9,'uint8'); a = b; a(5,5)=255;
r = analyzeParking(a,b,[0 0 1 1 1]);
verifyFalse(testCase,any(r.Mask,'all'));
a(:)=255;
r = analyzeParking(a,b,[0 0 1 1 1]);
verifyTrue(testCase,all(r.Mask,'all'));
end
function testSingletonReference(testCase)
a = zeros(8,10,'uint8');
r = analyzeParking(a,uint8(0),[0 0 1 1 1],ResizeReference=true);
verifyEqual(testCase,r.Available,1);
end
function testRoiPixelBounds(testCase)
% A 40-pixel-wide ROI from x = 0.25 to 0.5 covers columns 11 through 20.
b = zeros(20,40,'uint8'); l = [.25 0 .25 1 1];
a = b; a(:,9:10) = 255;
r = analyzeParking(a,b,l);
verifyEqual(testCase,r.Spaces.ChangedFraction,0);
a = b; a(:,19:22) = 255;
r = analyzeParking(a,b,l);
verifyEqual(testCase,r.Spaces.ChangedFraction,2/10);
% Partially covered edge pixels are included: x = 10.4 to 18.4 spans 11 to 19.
a = b; a(:,11:12) = 255;
r = analyzeParking(a,b,[.26 0 .2 1 1]);
verifyEqual(testCase,r.Spaces.ChangedFraction,2/9);
end
function testRoiOrderAndLanes(testCase)
b = zeros(20,40,'uint8'); a = b; a(:,21:40) = 255;
l = [.5 0 .5 1 7; 0 0 .5 1 3];
r = analyzeParking(a,b,l);
verifyEqual(testCase,r.Spaces.Space,[1;2]);
verifyEqual(testCase,r.Spaces.Lane,[7;3]);
verifyEqual(testCase,r.Spaces.Occupied,[true;false]);
verifyEqual(testCase,r.RecommendedLane,3);
end
function testDifferenceThresholdEdge(testCase)
% Pixels must exceed the difference threshold; equality is unchanged.
b = zeros(20,10,'uint8'); a = b; a(:,1:2) = 38; l = [0 0 1 1 1];
r = analyzeParking(a,b,l,DifferenceThreshold=38/255);
verifyFalse(testCase,any(r.Mask,'all'));
r = analyzeParking(a,b,l,DifferenceThreshold=37/255);
verifyEqual(testCase,r.Spaces.ChangedFraction,.2);
r = analyzeParking(255*ones(20,10,'uint8'),b,l,DifferenceThreshold=1);
verifyEqual(testCase,r.Available,1);
end
function testOccupancyThresholdEdge(testCase)
% A space is occupied once its changed fraction reaches the threshold.
b = zeros(20,10,'uint8'); a = b; a(:,1:2) = 255; l = [0 0 1 1 1];
r = analyzeParking(a,b,l,OccupancyThreshold=.2);
verifyEqual(testCase,r.Spaces.ChangedFraction,.2);
verifyTrue(testCase,r.Spaces.Occupied);
r = analyzeParking(a,b,l,OccupancyThreshold=.21);
verifyFalse(testCase,r.Spaces.Occupied);
r = analyzeParking(255*ones(20,10,'uint8'),b,l,OccupancyThreshold=1);
verifyTrue(testCase,r.Spaces.Occupied);
end
function testInvalidThresholds(testCase)
b = zeros(10,'uint8'); l = [0 0 1 1 1];
for value = [0 -.1 1.01 NaN Inf]
    verifyError(testCase,@() analyzeParking(b,b,l,DifferenceThreshold=value),?MException);
    verifyError(testCase,@() analyzeParking(b,b,l,OccupancyThreshold=value),?MException);
end
end
function testDimensions(testCase)
l = [0 0 .5 1 1; .5 0 .5 1 1];
tall = zeros(50,7,'uint8');
r = analyzeParking(tall,tall,l);
verifyEqual(testCase,size(r.Mask),[50 7]);
verifyFalse(testCase,r.ReferenceResized);
verifyError(testCase,@() analyzeParking(tall,tall',l),'Parking:Size');
r = analyzeParking(repmat(tall,1,1,3),zeros(25,4,'uint8'),l,ResizeReference=true);
verifyEqual(testCase,size(r.Mask),[50 7]);
verifyTrue(testCase,r.ReferenceResized);
verifyError(testCase,@() analyzeParking(zeros(5,5,4,'uint8'),zeros(5,5,4,'uint8'),l),'Parking:Image');
verifyError(testCase,@() analyzeParking(zeros(0,5,'uint8'),zeros(0,5,'uint8'),l),'Parking:Image');
% Regions may end exactly on the image border but not beyond it.
analyzeParking(tall,tall,[.25 .5 .75 .5 1]);
verifyError(testCase,@() analyzeParking(tall,tall,[.25 .5 .76 .5 1]),'Parking:Layout');
end
function testEmptyFullAndPartialLot(testCase)
b = zeros(30,120,'uint8');
x = (0:11)'/12;
l = [x zeros(12,1) ones(12,1)/12 ones(12,1) repelem((1:3)',4)];
r = analyzeParking(b,b,l);
verifyEqual(testCase,[r.Total r.Occupied r.Available],[12 0 12]);
verifyEqual(testCase,r.Lanes.Available,[4;4;4]);
verifyEqual(testCase,r.RecommendedLane,3);
r = analyzeParking(255*ones(30,120,'uint8'),b,l);
verifyEqual(testCase,[r.Total r.Occupied r.Available],[12 12 0]);
verifyEqual(testCase,r.Lanes.Available,[0;0;0]);
verifyEmpty(testCase,r.RecommendedLane);
% Filling lane 3 moves the recommendation to lane 2.
a = b; a(:,81:120) = 255;
r = analyzeParking(a,b,l);
verifyEqual(testCase,r.Lanes.Available,[4;4;0]);
verifyEqual(testCase,r.RecommendedLane,2);
verifyEqual(testCase,r.Occupied+r.Available,r.Total);
end
