function results = run_mppt_tests(validFile, invalidFile)
%RUN_MPPT_TESTS 对解析、符号处理、指标和坏文件路径做实际回归测试。

if nargin < 1 || isempty(validFile)
    candidates = dir(fullfile(fileparts(fileparts(mfilename('fullpath'))), '..', 'Serial*.txt'));
    assert(~isempty(candidates), '未找到样例历史文件。');
    validFile = fullfile(candidates(1).folder, candidates(1).name);
end
if nargin < 2 || isempty(invalidFile)
    invalidFile = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
        'testdata', 'invalid.log');
end
partialFile = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    'testdata', 'partial.log');

[data, report] = mppt.loadHistoryFile(validFile);
assert(report.totalLines == 275, '文件总行数与实际样例不符。');
assert(report.parsedCount == 274, '有效 JSON 数据数与实际样例不符。');
assert(report.skippedCount == 1, '无效行数与实际样例不符。');
assert(numel(data.Uptime_s) == numel(data.Bat_V), 'Uptime_s 与 Bat_V 数量不一致。');
assert(numel(data.Uptime_s) == numel(data.Solar_V), 'Uptime_s 与 Solar_V 数量不一致。');
assert(numel(data.Uptime_s) == numel(data.Solar_A_raw), 'Uptime_s 与 Solar_A 数量不一致。');
assert(numel(data.Uptime_s) == numel(data.SolarInDay_Wh), 'Uptime_s 与 SolarInDay_Wh 数量不一致。');
assert(all(data.SolarPower_W(isfinite(data.SolarPower_W)) >= 0), ...
    '太阳能功率仍出现负值，请检查 Solar_A 符号处理。');
assert(abs(data.metrics.Pmax_W - 197.6068) < 1e-8, 'Pmax 计算不符。');
assert(abs(data.metrics.V_at_Pmax_V - 43.24) < 1e-8, 'Pmax 对应电压不符。');
assert(abs(data.metrics.I_at_Pmax_A - 4.57) < 1e-8, 'Pmax 对应发电电流不符。');
assert(data.metrics.Uptime_at_Pmax_s == 344, 'Pmax 对应 Uptime 不符。');
assert(strcmp(data.energySource, '原始字段 SolarInDay_Wh'), '能量图未优先使用原始累计字段。');

[partialData, ~] = mppt.loadHistoryFile(partialFile);
assert(partialData.energyIsComputed, '缺少 SolarInDay_Wh 时未走积分回退。');
assert(numel(partialData.Energy_Wh) == 2 && partialData.Energy_Wh(end) > 0, ...
    '积分回退能量值不正确。');

invalidCaught = false;
try
    mppt.loadHistoryFile(invalidFile);
catch ME
    invalidCaught = strcmp(ME.identifier, 'MPPT:NoValidData');
end
assert(invalidCaught, '无效日志未按预期返回清晰错误。');

results = struct('validFile', validFile, 'invalidFile', invalidFile, ...
    'partialFile', partialFile, ...
    'totalLines', report.totalLines, 'parsedCount', report.parsedCount, ...
    'skippedCount', report.skippedCount, 'uptimeStart', report.startUptime_s, ...
    'uptimeEnd', report.endUptime_s, 'solarSignRule', data.solarSignRule, ...
    'Pmax_W', data.metrics.Pmax_W, 'V_at_Pmax_V', data.metrics.V_at_Pmax_V, ...
    'I_at_Pmax_A', data.metrics.I_at_Pmax_A, ...
    'Uptime_at_Pmax_s', data.metrics.Uptime_at_Pmax_s, ...
    'lastBat_V', data.Bat_V(end), 'lastSolar_V', data.Solar_V(end), ...
    'lastSolarPower_W', data.SolarPower_W(end), ...
    'lastDCDCState', data.DCDCState(end), 'lastChgState', data.ChgState(end), ...
    'lastErrorFlags', data.ErrorFlags(end), 'lastSolarInDay_Wh', data.SolarInDay_Wh(end));
disp(results);
end
