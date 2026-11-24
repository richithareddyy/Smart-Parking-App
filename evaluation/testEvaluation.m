function tests = testEvaluation
tests = functiontests(localfunctions);
end
function setupOnce(testCase)
here = fileparts(mfilename('fullpath'));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture({here,fileparts(here)}));
folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
testCase.TestData.Root = fullfile(folder,'data');
testCase.TestData.Manifest = fullfile(folder,'manifest');
testCase.TestData.Output = fullfile(folder,'results');
makeDataset(testCase.TestData.Root);
evalc('importPKLot(testCase.TestData.Root,testCase.TestData.Manifest,HeldOutCameras="CAMB")');
evalc(['runEvaluation(testCase.TestData.Manifest,testCase.TestData.Root,testCase.TestData.Output,' ...
    'DifferenceThresholds=[.1 .15],OccupancyThresholds=[.18 .5],LearningRates=.1,RoiScales=[1 .5])']);
end
function testMetrics(testCase)
m = parkingMetrics([1 1 1 1 0 0 0 0 0 0],[1 1 1 0 1 1 0 0 0 0]);
verifyEqual(testCase,[m.TrueOccupied m.FalseFree m.FalseOccupied m.TrueFree],[3 1 2 4]);
verifyEqual(testCase,[m.OccupiedPrecision m.OccupiedRecall],[3/5 3/4]);
verifyEqual(testCase,[m.FreePrecision m.FreeRecall],[4/5 4/6]);
verifyEqual(testCase,[m.FalseFreeRate m.FalseOccupiedRate],[1/4 2/6]);
m = parkingMetrics([0 0],[0 0]);
verifyTrue(testCase,isnan(m.OccupiedRecall) && m.FreeRecall==1);
end
function testGrayscaleMatchesDetector(testCase)
image = uint8(reshape(mod(0:36*48*3-1,256),36,48,3));
r = analyzeParking(image,grayFrame(image),[0 0 1 1 1],DifferenceThreshold=1e-12);
verifyFalse(testCase,any(r.Mask,'all'));
end
function testBackgroundUpdate(testCase)
verifyEqual(testCase,updateBackground([.5 .5],[.6 .9],.15,.5),[.55 .5],'AbsTol',1e-12);
end
function testShift(testCase)
stream = RandStream('mt19937ar','Seed',1);
reference = conv2(rand(stream,120,160),ones(5)/25,'same');
verifyEqual(testCase,estimateShift(reference,reference),[0 0]);
verifyEqual(testCase,estimateShift(circshift(reference,[-4 7]),reference),[7 -4]);
end
function testImport(testCase)
m = readManifest(testCase.TestData.Manifest);
verifyEqual(testCase,height(m.frames),40);
verifyEqual(testCase,unique(m.frames.View),["CAMA-1";"CAMA-2";"CAMB-1"]);
verifyEqual(testCase,nnz(isnan(m.labels.Occupied)),1);
a = m.splits(m.splits.Camera=="CAMA",:);
verifyEqual(testCase,a.Split,["train";"train";"train";"validation";"test"]);
b = m.splits(m.splits.Camera=="CAMB",:);
verifyEqual(testCase,b.Split,["setup";"test";"test";"test";"test"]);
verifyFalse(testCase,any(m.references.Split=="test"));
end
function testRejectsLeaks(testCase)
check = @(file,change) verifyError(testCase,@() readManifest(corrupt(testCase,file,change)),'Eval:Manifest');
check('splits.csv',@(t) [t; t(1,:)]);
check('splits.csv',@(t) setValue(t,t.Camera=="CAMB" & t.Split=="test",'Split',"train"));
check('splits.csv',@(t) setValue(t,t.Camera=="CAMA" & t.Split=="validation",'Split',"test"));
check('references.csv',@(t) t(2:end,:));
check('labels.csv',@(t) setValue(t,1,'Space',99));
check('labels.csv',@(t) [t; t(1,:)]);
check('spaces.csv',@(t) setValue(t,1,'X',1.5));
end
function testCleanSceneScoresPerfectly(testCase)
s = readtable(fullfile(testCase.TestData.Output,'summary.csv'),'TextType','string');
verifyEqual(testCase,unique(s.Level),sort(["train";"validation";"test";"held-out test";"stale setup"]));
tuned = s(s.Setting~="Reference default" & s.Level~="stale setup",:);
verifyEqual(testCase,tuned.BalancedAccuracy,ones(height(tuned),1));
stale = s(s.Level=="stale setup",:);
verifyTrue(testCase,any(stale.BalancedAccuracy<1));
end
function testSettingsIgnoreTestLabels(testCase)
folder = corrupt(testCase,'labels.csv',@(t) flipHeldDays(t,testCase.TestData.Manifest));
output = fullfile(folder,'out');
evalc(['runEvaluation(folder,testCase.TestData.Root,output,' ...
    'DifferenceThresholds=[.1 .15],OccupancyThresholds=[.18 .5],LearningRates=.1,RoiScales=[1 .5])']);
verifyEqual(testCase,fileread(fullfile(output,'settings.csv')),...
    fileread(fullfile(testCase.TestData.Output,'settings.csv')));
s = readtable(fullfile(output,'summary.csv'),'TextType','string');
verifyEqual(testCase,s.BalancedAccuracy(s.Setting=="Reference tuned" & s.Level=="test"),0);
end

function folder = corrupt(testCase,file,change)
folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
copyfile(testCase.TestData.Manifest,folder);
t = readtable(fullfile(folder,file),'TextType','string','DatetimeType','text','DurationType','text','Delimiter',',');
writetable(change(t),fullfile(folder,file));
end
function t = setValue(t,rows,name,value)
t.(name)(rows) = value;
end
function t = flipHeldDays(t,manifest)
m = readManifest(manifest);
f = join(m.frames,m.splits(:,{'Camera','Day','Split'}));
in = ismember(t.Frame,f.Frame(f.Split=="test")) & ~isnan(t.Occupied);
t.Occupied(in) = 1-t.Occupied(in);
end
function makeDataset(root)
% Two cameras, five days, four frames per day. Camera A moves on day 4.
stream = RandStream('mt19937ar','Seed',7);
ground = 90+20*rand(stream,80,160);
for camera = ["CAMA" "CAMB"]
    for day = 1:5
        offset = 30*(camera=="CAMA" && day>=4);
        folder = fullfile(root,camera,"Sunny",sprintf('2020-01-%02d',day));
        mkdir(folder);
        for k = 1:4
            occupied = [k>1 && mod(k,2)==0, k==3];
            image = ground; text = '<parking id="x">';
            for s = 1:2
                x = 10+40*(s-1)+offset;
                if occupied(s), image(20:60,x+(1:30)) = 230; end
                tag = 'point'; if day==5, tag = 'Point'; end
                flag = sprintf(' occupied="%d"',occupied(s));
                if camera=="CAMB" && day==5 && k==4 && s==2, flag = ''; end
                points = [x 20; x+30 20; x+30 60; x 60];
                text = [text sprintf('<space id="%d"%s><contour>',s,flag) ...
                    sprintf(['<' tag ' x="%d" y="%d" />'],points') '</contour></space>']; %#ok<AGROW>
            end
            stem = fullfile(folder,sprintf('2020-01-%02d_%02d_00_00',day,8+k));
            imwrite(uint8(image),stem + ".jpg",'Quality',100);
            fid = fopen(stem + ".xml",'w'); fprintf(fid,'%s</parking>',text); fclose(fid);
        end
    end
end
end
