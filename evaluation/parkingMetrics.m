function m = parkingMetrics(truth, predicted)
%PARKINGMETRICS Per-space occupancy metrics; the positive class is occupied.
% A false-free error reports an occupied space as available. A false-occupied
% error hides an available space.
truth = logical(truth(:)); predicted = logical(predicted(:));
tp = nnz(truth & predicted); fo = nnz(~truth & predicted);
ff = nnz(truth & ~predicted); tn = nnz(~truth & ~predicted);
m = table(numel(truth),tp,tn,fo,ff,ratio(tp,tp+fo),ratio(tp,tp+ff),...
    ratio(tn,tn+ff),ratio(tn,tn+fo),ratio(ff,tp+ff),ratio(fo,tn+fo),...
    'VariableNames',{'Observations','TrueOccupied','TrueFree','FalseOccupied','FalseFree',...
    'OccupiedPrecision','OccupiedRecall','FreePrecision','FreeRecall',...
    'FalseFreeRate','FalseOccupiedRate'});
m.BalancedAccuracy = (m.OccupiedRecall+m.FreeRecall)/2;
m.Accuracy = ratio(tp+tn,numel(truth));
end

function r = ratio(a,b)
r = NaN; if b > 0, r = a/b; end
end
