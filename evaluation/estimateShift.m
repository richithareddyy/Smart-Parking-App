function shift = estimateShift(image, reference)
%ESTIMATESHIFT Integer [dx dy] translation of image relative to reference.
% Phase correlation with a Hann window; used to flag camera movement.
[h,w] = size(image);
window = hann(h)*hann(w)';
a = fft2((image-mean(image,'all')).*window);
b = fft2((reference-mean(reference,'all')).*window);
cross = a.*conj(b);
surface = real(ifft2(cross./max(abs(cross),eps)));
[~,k] = max(surface(:));
[dy,dx] = ind2sub([h w],k);
shift = [dx dy]-1;
extent = [w h]; wrap = shift > extent/2;
shift(wrap) = shift(wrap)-extent(wrap);
end

function v = hann(n)
v = .5-.5*cos(2*pi*(0:n-1)'/max(n-1,1));
end
