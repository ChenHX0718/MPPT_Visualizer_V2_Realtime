function data = processMPPTData(records, signFactorOverride)
%PROCESSMPPTDATA 将 JSON 记录转换成历史/实时模式共用的数据结构。
%   Solar_A_raw 保留固件原始符号；Solar_A_generation 和 SolarPower_W
%   是仅供可视化使用的标准化太阳能发电量。

n = numel(records);
data = struct();
data.rawRecords = records;
data.Uptime_s = localNumericField(records, 'Uptime_s');
data.Bat_V = localNumericField(records, 'Bat_V');
data.Bat_A = localNumericField(records, 'Bat_A');
data.SOC_pct = localNumericField(records, 'SOC_pct');
data.ChgState = localNumericField(records, 'ChgState');
data.DCDCState = localNumericField(records, 'DCDCState');
data.Solar_V = localNumericField(records, 'Solar_V');
data.Solar_A_raw = localNumericField(records, 'Solar_A');
data.Solar_A = data.Solar_A_raw; % 兼容性别名：仍代表原始 Solar_A
data.SolarInDay_Wh = localNumericField(records, 'SolarInDay_Wh');
data.Load_A = localNumericField(records, 'Load_A');
data.LoadBus_V = localNumericField(records, 'LoadBus_V');
data.ErrorFlags = localNumericField(records, 'ErrorFlags');

% 以后若日志提供明确的 Vmp 字段，保留并优先用于峰值电压标签。
explicitNames = {'Vmp', 'MPP_V', 'Vmpp'};
data.Vmp_explicit = NaN(n, 1);
data.Vmp_field_name = '';
for k = 1:numel(explicitNames)
    candidate = localNumericField(records, explicitNames{k});
    if any(isfinite(candidate))
        data.Vmp_explicit = candidate;
        data.Vmp_field_name = explicitNames{k};
        break;
    end
end

validTime = find(isfinite(data.Uptime_s));
if isempty(validTime)
    data.Time_s = (0:n-1)';
    data.timeIsFallback = true;
else
    data.Time_s = data.Uptime_s - data.Uptime_s(validTime(1));
    data.timeIsFallback = false;
end

validSolar = isfinite(data.Solar_V) & isfinite(data.Solar_A_raw) & data.Solar_V >= 0;
if nargin >= 2 && isnumeric(signFactorOverride) && isscalar(signFactorOverride) && ...
        isfinite(signFactorOverride) && signFactorOverride ~= 0
    signFactor = sign(signFactorOverride);
    if signFactor < 0
        data.solarSignRule = '实时缓存已基于多个有效样本判定 Solar_A < 0 表示太阳能输入。';
    else
        data.solarSignRule = '实时缓存已基于多个有效样本判定 Solar_A > 0 表示太阳能输入。';
    end
else
    negativeCount = sum(data.Solar_A_raw(validSolar) < 0);
    positiveCount = sum(data.Solar_A_raw(validSolar) > 0);
    if negativeCount > positiveCount && negativeCount > 0
        signFactor = -1;
        data.solarSignRule = '检测到 Solar_A < 0 表示太阳能输入，已取反用于发电功率显示。';
    elseif positiveCount > negativeCount && positiveCount > 0
        signFactor = 1;
        data.solarSignRule = '检测到 Solar_A > 0 表示太阳能输入，按原符号用于发电功率显示。';
    elseif any(validSolar)
        rawPowerMedian = median(data.Solar_V(validSolar) .* data.Solar_A_raw(validSolar), 'omitnan');
        if rawPowerMedian < 0
            signFactor = -1;
            data.solarSignRule = 'Solar_A 符号混合，按主导功率方向取反用于显示。';
        else
            signFactor = 1;
            data.solarSignRule = 'Solar_A 符号混合，按主导功率方向保留用于显示。';
        end
    else
        signFactor = 1;
        data.solarSignRule = '缺少有效 Solar_V / Solar_A，无法判断符号规则。';
    end
end

data.Solar_A_generation = signFactor .* data.Solar_A_raw;
data.SolarPower_W = data.Solar_V .* data.Solar_A_generation;

rawEnergyValid = isfinite(data.SolarInDay_Wh);
if any(rawEnergyValid)
    data.Energy_Wh = data.SolarInDay_Wh;
    data.energyIsComputed = false;
    data.energySource = '原始字段 SolarInDay_Wh';
else
    powerForIntegration = data.SolarPower_W;
    powerForIntegration(~isfinite(powerForIntegration)) = 0;
    powerForIntegration = max(powerForIntegration, 0);
    if n < 2
        data.Energy_Wh = zeros(n, 1);
    else
        data.Energy_Wh = cumtrapz(data.Time_s, powerForIntegration) ./ 3600;
    end
    data.energyIsComputed = true;
    data.energySource = '由 SolarPower_W 积分计算';
end

data.report = localReport(records, data);
data.metrics = mppt.calculateMetrics(data);
end

function values = localNumericField(records, name)
values = NaN(numel(records), 1);
for k = 1:numel(records)
    fieldName = localMatchingField(records{k}, name);
    if isempty(fieldName)
        continue;
    end
    try
        value = records{k}.(fieldName);
        if isnumeric(value) && isscalar(value)
            values(k) = double(value);
        end
    catch
    end
end
end

function fieldName = localMatchingField(record, requested)
fieldName = '';
names = fieldnames(record);
idx = find(strcmp(names, requested), 1);
if isempty(idx)
    idx = find(strcmpi(names, requested), 1);
end
if ~isempty(idx)
    fieldName = names{idx};
end
end

function report = localReport(records, data)
names = cell(0, 1);
for k = 1:numel(records)
    names = union(names, fieldnames(records{k}));
end
names = names(:);
fieldCounts = struct();
for k = 1:numel(names)
    safeName = matlab.lang.makeValidName(names{k});
    fieldCounts.(safeName) = sum(cellfun(@(r) ~isempty(localMatchingField(r, names{k})), records));
end
report = struct('fieldNames', {names}, 'fieldCounts', fieldCounts, ...
    'missingFields', {{}}, 'startUptime_s', NaN, 'endUptime_s', NaN);
required = {'Uptime_s', 'Bat_V', 'Solar_V', 'Solar_A', 'SolarInDay_Wh', ...
    'ChgState', 'DCDCState', 'ErrorFlags'};
missing = cell(0, 1);
for k = 1:numel(required)
    safeName = matlab.lang.makeValidName(required{k});
    if ~isfield(fieldCounts, safeName) || fieldCounts.(safeName) < numel(records)
        missing{end+1} = required{k}; %#ok<AGROW>
    end
end
report.missingFields = missing;
valid = data.Uptime_s(isfinite(data.Uptime_s));
if ~isempty(valid)
    report.startUptime_s = valid(1);
    report.endUptime_s = valid(end);
end
end
