function [record, isValid, info] = parseTelemetryLine(rawLine)
%PARSETELEMETRYLINE 解析一条 MPPT ThingSet JSON 串口/日志数据行。
%   [record, isValid, info] = mppt.parseTelemetryLine(rawLine)
%   允许空白和可选的“#”前缀；空行、调试文本、半行 JSON、坏 JSON
%   或没有任何数值采样字段的对象都会安全返回 isValid=false。

record = struct();
isValid = false;
info = struct('rawLine', '', 'normalizedLine', '', 'reason', '');

if isstring(rawLine)
    if ~isscalar(rawLine)
        info.reason = '输入不是单行文本';
        return;
    end
    rawLine = char(rawLine);
elseif ~ischar(rawLine)
    info.reason = '输入不是文本';
    return;
end

info.rawLine = rawLine;
line = strtrim(rawLine);
line = erase(line, char(65279)); % UTF-8 BOM
if startsWith(line, '#')
    line = strtrim(extractAfter(line, 1));
end
info.normalizedLine = line;

if isempty(line)
    info.reason = '空行';
    return;
end
if ~startsWith(line, '{') || ~endsWith(line, '}')
    info.reason = '非 JSON 行';
    return;
end

try
    decoded = jsondecode(line);
catch
    info.reason = 'JSON 语法错误或数据不完整';
    return;
end

if ~isstruct(decoded) || ~isscalar(decoded)
    info.reason = 'JSON 顶层不是单个对象';
    return;
end

% 允许字段缺失，但至少要有一个 MPPT 数值采样字段，避免把普通 JSON
% 说明文本误计为有效采样。历史模式和实时模式使用同一判定。
numericFieldNames = { ...
    'Uptime_s', 'Bat_V', 'Bat_A', 'SOC_pct', 'ChgState', 'DCDCState', ...
    'Solar_V', 'Solar_A', 'Load_A', 'LoadInfo', 'LoadBus_V', ...
    'LoadLvdTrip_V', 'LoadOvTrip_V', 'LoadErrFlags', 'ErrorFlags', ...
    'SolarInDay_Wh', 'LoadOutDay_Wh', 'BatChgDay_Wh', 'BatDisDay_Wh', ...
    'Dis_Ah', 'DeepDisCount', 'BatUsable_Ah', 'Vmp', 'MPP_V', 'Vmpp'};
hasNumericSample = false;
for k = 1:numel(numericFieldNames)
    name = numericFieldNames{k};
    if ~isfield(decoded, name)
        continue;
    end
    value = decoded.(name);
    if isnumeric(value) && isscalar(value) && isfinite(double(value))
        hasNumericSample = true;
        break;
    end
end
if ~hasNumericSample
    info.reason = '没有有效数值采样字段';
    return;
end

record = decoded;
isValid = true;
info.reason = 'OK';
end
