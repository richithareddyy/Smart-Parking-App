function background = updateBackground(background, frame, threshold, rate)
%UPDATEBACKGROUND Selective running average for the adaptive baseline.
% Only pixels within the difference threshold of the background are blended
% in, so parked cars are not absorbed while gradual lighting changes are.
still = abs(frame-background) <= threshold;
background(still) = background(still) + rate*(frame(still)-background(still));
end
