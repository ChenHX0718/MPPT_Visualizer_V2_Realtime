function [x, y] = plotSeries(time_s, values, breakBefore, index)
%PLOTSERIES 只在显示层插入 NaN 断线符；每条已有记录仅出现一次。
if nargin < 4
    index = true(size(time_s));
end
indices = find(index);
breaks = breakBefore(indices);
if ~isempty(indices)
    breaks(1) = false;
    breaks(2:end) = breaks(2:end) | diff(indices) > 1;
end
positions = (1:numel(indices))' + cumsum(breaks(:));
x = NaN(numel(indices) + nnz(breaks), 1);
y = x;
x(positions) = time_s(indices);
y(positions) = values(indices);
end
