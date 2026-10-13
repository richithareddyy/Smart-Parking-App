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
