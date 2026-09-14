function [data, report] = loadHistoryFile(filePath)
%LOADHISTORYFILE 读取并标准化一份 MPPT 历史日志。

if nargin < 1 || ~(ischar(filePath) || isstring(filePath))
    error('MPPT:InvalidFile', '请提供历史日志文件路径。');
end
filePath = char(filePath);
if ~isfile(filePath)
    error('MPPT:InvalidFile', '文件不存在：%s', filePath);
end

[records, report] = mppt.parseHistoryLog(filePath);
if isempty(records)
    error('MPPT:NoValidData', ...
        '文件中没有可解析的 JSON 数据行（共检查 %d 行）。', report.totalLines);
end

data = mppt.processMPPTData(records);
% JSON 语法正确但完全没有数值采样字段时，按“无有效数据”处理，
% 这样用户误选串口说明或结构错误的 JSON 文件时会得到清晰提示。
hasNumericSample = any(isfinite(data.Uptime_s)) || ...
    any(isfinite(data.Bat_V)) || any(isfinite(data.Solar_V)) || ...
    any(isfinite(data.Solar_A_raw)) || any(isfinite(data.SolarInDay_Wh));
if ~hasNumericSample
    error('MPPT:NoValidData', ...
        '文件中没有可用于显示的数值采样字段（共解析 %d 条 JSON）。', report.parsedCount);
end
report.startUptime_s = data.report.startUptime_s;
report.endUptime_s = data.report.endUptime_s;
report.missingFields = data.report.missingFields;
report.fieldCounts = data.report.fieldCounts;
end
