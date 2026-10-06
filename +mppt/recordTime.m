function [clock, time_s, breakBefore, status] = recordTime(clock, uptime)
%RECORDTIME 板端时钟；不推算缺失时间，不自动认定复位或拼接时钟。
% 空参数创建会话。>10 s 的缺口不连线、不积分；该阈值不是采样周期。
if nargin == 0
    clock = struct('sessionStartUptime_s', NaN, 'lastUptime_s', NaN, ...
        'previousValid', false, 'invalidated', false, 'maxGap_s', 10, ...
        'missingCount', 0, 'duplicateCount', 0, 'gapCount', 0, ...
        'unresolvedCount', 0);
    return;
end
time_s = NaN;
breakBefore = true;
status = '时间未知';
valid = isnumeric(uptime) && isreal(uptime) && isscalar(uptime) && ...
    isfinite(double(uptime)) && double(uptime) >= 0 && ...
    double(uptime) <= double(intmax('uint32')) && fix(double(uptime)) == double(uptime);
if ~valid
    clock.missingCount = clock.missingCount + 1;
    clock.previousValid = false;
    return;
end
uptime = double(uptime);
if clock.invalidated || (isfinite(clock.lastUptime_s) && uptime < clock.lastUptime_s)
    clock.invalidated = true;
    clock.previousValid = false;
    clock.unresolvedCount = clock.unresolvedCount + 1;
    status = '时间倒退（复位/乱序未确认）；清空曲线开始新记录';
    return;
end
if ~isfinite(clock.sessionStartUptime_s)
    clock.sessionStartUptime_s = uptime;
end
time_s = double(uptime) - double(clock.sessionStartUptime_s);
dt = uptime - clock.lastUptime_s;
breakBefore = ~clock.previousValid || dt > clock.maxGap_s;
status = '板端Uptime_s';
if dt == 0
    clock.duplicateCount = clock.duplicateCount + 1;
    status = '重复秒时间（保留记录，dt=0）';
elseif dt > clock.maxGap_s
    clock.gapCount = clock.gapCount + 1;
    status = '时间缺口超过10 s（断线显示，不跨缺口积分）';
end
clock.lastUptime_s = uptime;
clock.previousValid = true;
end
