function y = vec(x)
% Compatibility helper for CVX and legacy code that expect vec(x) = x(:).
y = x(:);
end
