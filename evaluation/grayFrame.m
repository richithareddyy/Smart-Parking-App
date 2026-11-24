function gray = grayFrame(image)
%GRAYFRAME Grayscale in [0,1] using the same conversion as analyzeParking.
gray = double(image);
if isinteger(image)
    low = double(intmin(class(image))); high = double(intmax(class(image)));
    gray = (gray-low)/(high-low);
end
if size(gray,3)==3
    gray = .298936021293775*gray(:,:,1) + .587043074451121*gray(:,:,2) + ...
        .114020904255103*gray(:,:,3);
end
end
