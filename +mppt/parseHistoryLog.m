function [records, report] = parseHistoryLog(filePath)
%PARSEHISTORYLOG 通过共用单行解析器逐行读取 MPPT 历史日志。
%   坏行、空行、串口提示和不完整 JSON 只会被跳过，不会中止整个文件。

[fid, message] = fopen(filePath, 'r', 'n', 'UTF-8');
if fid < 0
    error('MPPT:OpenFile', '无法打开文件：%s\n%s', filePath, message);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

records = cell(0, 1);
totalLines = 0;
skippedLines = 0;
invalidLines = [];

while true
    rawLine = fgetl(fid);
    if ~ischar(rawLine)
        break;
    end
    totalLines = totalLines + 1;
    [record, isValid] = mppt.parseTelemetryLine(rawLine);
    if isValid
        records{end+1, 1} = record; %#ok<AGROW>
    else
        skippedLines = skippedLines + 1;
        invalidLines(end+1, 1) = totalLines; %#ok<AGROW>
    end
end

report = struct();
report.filePath = filePath;
report.totalLines = totalLines;
report.parsedCount = numel(records);
report.skippedCount = skippedLines;
report.invalidLines = invalidLines;
report.fieldNames = localUnionFieldNames(records);
report.fieldCounts = localFieldCounts(records, report.fieldNames);
report.requiredFields = {'Uptime_s', 'Bat_V', 'Solar_V', 'Solar_A', ...
    'SolarInDay_Wh', 'ChgState', 'DCDCState', 'ErrorFlags'};
report.missingFields = report.requiredFields(cellfun( ...
    @(name) localFieldCount(report.fieldCounts, name) < report.parsedCount, report.requiredFields));

uptime = localNumericField(records, 'Uptime_s');
uptime = uptime(isfinite(uptime));
if isempty(uptime)
    report.startUptime_s = NaN;
    report.endUptime_s = NaN;
else
    report.startUptime_s = uptime(1);
    report.endUptime_s = uptime(end);
end
end

function names = localUnionFieldNames(records)
names = cell(0, 1);
for k = 1:numel(records)
    names = union(names, fieldnames(records{k}));
end
names = names(:);
end

function counts = localFieldCounts(records, names)
counts = struct();
for k = 1:numel(names)
    safeName = matlab.lang.makeValidName(names{k});
    counts.(safeName) = sum(cellfun(@(r) isfield(r, names{k}), records));
end
end

function count = localFieldCount(counts, name)
safeName = matlab.lang.makeValidName(name);
if isfield(counts, safeName)
    count = counts.(safeName);
else
    count = 0;
end
end

function values = localNumericField(records, name)
values = NaN(numel(records), 1);
for k = 1:numel(records)
    if isfield(records{k}, name)
        try
            value = records{k}.(name);
            if isnumeric(value) && isscalar(value)
                values(k) = double(value);
            end
        catch
        end
    end
end
end
