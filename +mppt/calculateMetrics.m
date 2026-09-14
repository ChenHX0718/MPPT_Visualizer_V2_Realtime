function metrics = calculateMetrics(data)
%CALCULATEMETRICS 计算历史最大功率点及最后采样点索引。

metrics = struct('Pmax_W', NaN, 'V_at_Pmax_V', NaN, 'I_at_Pmax_A', NaN, ...
    'Uptime_at_Pmax_s', NaN, 'indexAtPmax', NaN, 'vmpSource', '无有效功率数据', ...
    'lastIndex', NaN);

validPower = find(isfinite(data.SolarPower_W));
if ~isempty(validPower)
    [metrics.Pmax_W, localIndex] = max(data.SolarPower_W(validPower));
    idx = validPower(localIndex);
    metrics.indexAtPmax = idx;
    metrics.V_at_Pmax_V = data.Solar_V(idx);
    metrics.I_at_Pmax_A = data.Solar_A_generation(idx);
    metrics.Uptime_at_Pmax_s = data.Uptime_s(idx);
    if isfield(data, 'Vmp_explicit') && isfinite(data.Vmp_explicit(idx))
        metrics.V_at_Pmax_V = data.Vmp_explicit(idx);
        metrics.vmpSource = ['明确字段 ', data.Vmp_field_name];
    else
        metrics.vmpSource = '历史功率最大样本估算';
    end
end

if isfield(data, 'Uptime_s')
    idx = find(isfinite(data.Uptime_s), 1, 'last');
else
    idx = [];
end
if isempty(idx)
    idx = numel(data.SolarPower_W);
end
if ~isempty(idx) && idx > 0
    metrics.lastIndex = idx;
end
end
