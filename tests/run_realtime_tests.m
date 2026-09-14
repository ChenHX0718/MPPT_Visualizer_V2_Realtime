function results = run_realtime_tests(validFile)
%RUN_REALTIME_TESTS Replay、共用解析器、滚动缓存和日志回读测试。

projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(projectRoot));
if nargin < 1 || isempty(validFile)
    candidates = dir(fullfile(fileparts(projectRoot), 'Serial*.txt'));
    assert(~isempty(candidates), '未找到样例历史文件。');
    validFile = fullfile(candidates(1).folder, candidates(1).name);
end

[historyData, historyReport] = mppt.loadHistoryFile(validFile);
assert(historyReport.parsedCount == 274, '历史样例有效行数不符。');
assert(historyReport.skippedCount == 1, '历史样例坏行数不符。');
assert(abs(historyData.metrics.Pmax_W - 197.6068) < 1e-8, '历史 Pmax 回归失败。');
assert(abs(historyData.metrics.V_at_Pmax_V - 43.24) < 1e-8, '历史 Pmax 电压回归失败。');
assert(all(historyData.SolarPower_W(isfinite(historyData.SolarPower_W)) >= 0), ...
    'Solar_A 符号处理后仍有负功率。');

[record, isValid, info] = mppt.parseTelemetryLine( ...
    '# {"Uptime_s":1,"Solar_V":40,"Solar_A":-2}');
assert(isValid && isfield(record, 'Solar_A') && strcmp(info.reason, 'OK'), ...
    '正常 ThingSet JSON 解析失败。');
[~, isValid] = mppt.parseTelemetryLine('调试文本');
assert(~isValid, '非 JSON 文本没有被跳过。');
[~, isValid] = mppt.parseTelemetryLine('# {"Uptime_s":1');
assert(~isValid, '半行 JSON 没有被跳过。');
[~, isValid] = mppt.parseTelemetryLine('# {"Uptime_s":"坏数据"}');
assert(~isValid, '字段类型错误没有被跳过。');
[record, isValid] = mppt.parseTelemetryLine('# {"Uptime_s":10}');
assert(isValid && record.Uptime_s == 10, '字段缺失的合法采样不应被拒绝。');

fid = fopen(validFile, 'r', 'n', 'UTF-8');
assert(fid >= 0, '无法打开 Replay 样例。');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
buffer = mppt.realtimeBuffer('create', 10);
validCount = 0;
invalidCount = 0;
rawLines = cell(0, 1);
while true
    rawLine = fgetl(fid);
    if ~ischar(rawLine)
        break;
    end
    rawLines{end+1, 1} = rawLine; %#ok<AGROW>
    [record, isValid] = mppt.parseTelemetryLine(rawLine);
    if isValid
        [buffer, replayData] = mppt.realtimeBuffer('append', buffer, record); %#ok<ASGLU>
        validCount = validCount + 1;
    else
        invalidCount = invalidCount + 1;
    end
end
assert(validCount == 274 && invalidCount == 1, 'Replay 逐行计数失败。');
assert(numel(buffer.records) == 10, '滚动缓存没有限制到 10 点。');
assert(isfinite(replayData.SolarPower_W(end)) && replayData.SolarPower_W(end) > 0, ...
    'Replay 实时功率没有正确更新。');

% 用原始接收行写出一份临时实时日志，再走历史入口回读。
tempLog = [tempname, '.log'];
writeFid = fopen(tempLog, 'w', 'n', 'UTF-8');
assert(writeFid >= 0, '无法创建临时实时日志。');
cleanupWrite = onCleanup(@() localDeleteFile(tempLog)); %#ok<NASGU>
fprintf(writeFid, '%s\n', rawLines{1});
fprintf(writeFid, '%s\n', '串口助手提示文本');
fprintf(writeFid, '%s\n', rawLines{2});
fclose(writeFid);
[roundTripData, roundTripReport] = mppt.loadHistoryFile(tempLog); %#ok<ASGLU>
assert(roundTripReport.parsedCount == 2 && roundTripReport.skippedCount == 1, ...
    '实时日志回读失败。');

results = struct('validFile', validFile, 'historyParsed', historyReport.parsedCount, ...
    'historySkipped', historyReport.skippedCount, 'replayValid', validCount, ...
    'replaySkipped', invalidCount, 'rollingPoints', numel(buffer.records), ...
    'roundTripParsed', roundTripReport.parsedCount, ...
    'lastReplaySolarPower_W', replayData.SolarPower_W(end), ...
    'historyPmax_W', historyData.metrics.Pmax_W);
disp(results);
end

function localDeleteFile(pathValue)
if isfile(pathValue)
    delete(pathValue);
end
end
