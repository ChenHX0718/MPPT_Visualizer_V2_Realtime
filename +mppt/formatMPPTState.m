function state = formatMPPTState(chgState, dcdcState, errorFlags)
%FORMATMPPTSTATE 将 v21.0-branch 的状态枚举格式化为可读文本。

state = struct();
state.dcdcText = localDcdc(dcdcState);
state.chgText = localCharge(chgState);
state.errorText = localRaw(errorFlags);
state.hasError = isfinite(errorFlags) && errorFlags ~= 0;
if state.hasError
    state.mainText = '检测到告警';
else
    state.mainText = ['DCDC ', state.dcdcText];
end
end

function text = localOnOff(value)
if ~isfinite(value)
    text = '—';
elseif value ~= 0
    text = 'ON';
else
    text = 'OFF';
end

function text = localDcdc(value)
if ~isfinite(value)
    text = '—';
    return;
end
names = {'OFF', 'MPPT', 'CC_HS', 'CC_LS', 'CV_HS', 'CV_LS'};
index = round(value) + 1;
if index >= 1 && index <= numel(names) && abs(value - round(value)) < eps(max(1, abs(value)))
    text = sprintf('%s (%d)', names{index}, round(value));
else
    text = sprintf('未知 (%s)', localRaw(value));
end
end

function text = localCharge(value)
if ~isfinite(value)
    text = '—';
    return;
end
names = {'IDLE', 'BULK', 'TOPPING', 'TRICKLE'};
index = round(value) + 1;
if index >= 1 && index <= numel(names) && abs(value - round(value)) < eps(max(1, abs(value)))
    text = sprintf('%s (%d)', names{index}, round(value));
else
    text = sprintf('未知 (%s)', localRaw(value));
end
end
end

function text = localRaw(value)
if ~isfinite(value)
    text = '—';
elseif abs(value - round(value)) < eps(max(1, abs(value)))
    text = sprintf('%d', round(value));
else
    text = sprintf('%.3g', value);
end
end
