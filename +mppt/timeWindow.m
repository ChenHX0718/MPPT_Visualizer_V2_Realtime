function [index, limits, label] = timeWindow(time_s, duration_s)
%TIMEWINDOW 共用时间索引；Inf 表示本次全部有效时间记录。
if ~(isnumeric(duration_s) && isreal(duration_s) && isscalar(duration_s) && ...
        duration_s > 0 && ~isnan(duration_s))
    error('MPPT:TimeWindow', '显示时长必须为正数。');
end
index = false(size(time_s));
limits = [0 1];
if isinf(duration_s)
    label = '本次全部记录';
else
    label = sprintf('最近%g s', duration_s);
end
last = find(isfinite(time_s), 1, 'last');
if isempty(last)
    return;
end
tEnd = time_s(last);
index = isfinite(time_s) & time_s >= max(0, tEnd-duration_s) & time_s <= tEnd;
selected = time_s(index);
if ~isempty(selected)
    limits = [min(selected), tEnd];
    if limits(1) == limits(2)
        limits = [max(0, tEnd-0.5), tEnd+0.5];
    end
end
end
