function varargout = realtimeBuffer(action, varargin)
%REALTIMEBUFFER 本次完整记录缓存；显示窗口由 timeWindow 独立控制。
%   buffer = mppt.realtimeBuffer('create', maxPoints)
%   [buffer, data] = mppt.realtimeBuffer('append', buffer, record)
%   data = mppt.realtimeBuffer('data', buffer)

switch lower(char(action))
    case 'create'
        maxPoints = Inf; % 兼容旧 create(maxPoints) 调用，但不再截断记录。
        buffer = struct('maxPoints', maxPoints, 'records', {cell(0, 1)}, ...
            'clock', mppt.recordTime(), 'sessionStartUptime_s', NaN, ...
            'sessionBreakBefore', false(0, 1), 'sessionTimeStatus', {cell(0, 1)}, ...
            'liveTimeOffset_s', 0, 'acceptedCount', 0, 'signFactor', NaN, 'signFactorLocked', false, ...
            'sessionTime_s', zeros(0, 1), 'sessionSolarV', zeros(0, 1), ...
            'sessionSolarA_raw', zeros(0, 1), ...
            'sessionEnergy_Wh', zeros(0, 1), ...
            'sessionCapacity_mAh', zeros(0, 1));
        varargout{1} = buffer;

    case 'append'
        buffer = varargin{1};
        record = varargin{2};
        buffer.records{end+1, 1} = record;
        buffer.acceptedCount = buffer.acceptedCount + 1;

        % 时钟只随有效记录前进，窗口切换不调用 append/clear。
        meta = [];
        if numel(varargin) >= 3, meta = varargin{3}; end
        segment = ~isempty(meta) && (meta.restart || meta.uptimeWrap);
        if segment
            previous = buffer.sessionTime_s(isfinite(buffer.sessionTime_s));
            if ~isempty(previous), buffer.liveTimeOffset_s = previous(end); end
            if meta.uptimeWrap
                buffer.liveTimeOffset_s = buffer.liveTimeOffset_s + ...
                    mod(localRecordNumeric(record,'Uptime_s')-buffer.clock.lastUptime_s,2^32);
            end
            buffer.clock = mppt.recordTime();
        end
        [buffer.clock, time_s, breakBefore, timeStatus] = ...
            mppt.recordTime(buffer.clock, localRecordNumeric(record, 'Uptime_s'));
        time_s = time_s + buffer.liveTimeOffset_s;
        if segment
            breakBefore = true; timeStatus = '验证的启动时钟新段（不跨段积分）';
        end
        if ~isfinite(buffer.sessionStartUptime_s)
            buffer.sessionStartUptime_s = buffer.clock.sessionStartUptime_s;
        end
        buffer.sessionTime_s(end+1, 1) = time_s;
        buffer.sessionBreakBefore(end+1, 1) = breakBefore;
        buffer.sessionTimeStatus{end+1, 1} = timeStatus;
        buffer.sessionSolarV(end+1, 1) = localRecordNumeric(record, 'Solar_V');
        buffer.sessionSolarA_raw(end+1, 1) = localRecordNumeric(record, 'Solar_A');

        % 至少观察 5 个有效太阳能样本后锁定符号方向，避免只依赖一个点。
        wasLocked = buffer.signFactorLocked;
        if ~buffer.signFactorLocked
            solarV = buffer.sessionSolarV;
            solarA = buffer.sessionSolarA_raw;
            valid = isfinite(solarV) & isfinite(solarA) & solarV >= 0;
            if sum(valid) >= 5
                negativeCount = sum(solarA(valid) < 0);
                positiveCount = sum(solarA(valid) > 0);
                if negativeCount > positiveCount && negativeCount > 0
                    buffer.signFactor = -1;
                    buffer.signFactorLocked = true;
                elseif positiveCount > negativeCount && positiveCount > 0
                    buffer.signFactor = 1;
                    buffer.signFactorLocked = true;
                end
            end
        end

        if buffer.signFactorLocked && ~wasLocked
            [buffer.sessionEnergy_Wh, buffer.sessionCapacity_mAh] = ...
                localIntegrateSession(buffer.sessionTime_s, buffer.sessionSolarV, ...
                buffer.sessionSolarA_raw, buffer.signFactor, buffer.sessionBreakBefore);
        elseif buffer.signFactorLocked
            previousIndex = numel(buffer.sessionTime_s) - 1;
            currentIndex = previousIndex + 1;
            [powerPrevious, currentPrevious] = localGenerationValues( ...
                buffer.sessionSolarV(previousIndex), buffer.sessionSolarA_raw(previousIndex), buffer.signFactor);
            [powerCurrent, currentCurrent] = localGenerationValues( ...
                buffer.sessionSolarV(currentIndex), buffer.sessionSolarA_raw(currentIndex), buffer.signFactor);
            dt = buffer.sessionTime_s(currentIndex) - buffer.sessionTime_s(previousIndex);
            previousEnergy = buffer.sessionEnergy_Wh(previousIndex);
            previousCapacity = buffer.sessionCapacity_mAh(previousIndex);
            if ~buffer.sessionBreakBefore(currentIndex) && isfinite(dt) && dt > 0
                buffer.sessionEnergy_Wh(end+1, 1) = previousEnergy + ...
                    0.5 * (powerPrevious + powerCurrent) * dt / 3600;
                buffer.sessionCapacity_mAh(end+1, 1) = previousCapacity + ...
                    0.5 * (currentPrevious + currentCurrent) * dt * 1000 / 3600;
            else
                buffer.sessionEnergy_Wh(end+1, 1) = previousEnergy;
                buffer.sessionCapacity_mAh(end+1, 1) = previousCapacity;
            end
        else
            signFactor = localInferSignFactor(buffer.sessionSolarV, buffer.sessionSolarA_raw);
            [buffer.sessionEnergy_Wh, buffer.sessionCapacity_mAh] = ...
                localIntegrateSession(buffer.sessionTime_s, buffer.sessionSolarV, ...
                buffer.sessionSolarA_raw, signFactor, buffer.sessionBreakBefore);
        end
        varargout{1} = buffer;
        if nargout > 1
            data = mppt.processMPPTData(buffer.records, buffer.signFactor);
            varargout{2} = localOverlaySessionTotals(data, buffer);
        end

    case 'data'
        buffer = varargin{1};
        data = mppt.processMPPTData(buffer.records, buffer.signFactor);
        varargout{1} = localOverlaySessionTotals(data, buffer);

    case 'clear'
        maxPoints = varargin{1}.maxPoints;
        varargout{1} = mppt.realtimeBuffer('create', maxPoints);

    otherwise
        error('MPPT:RealtimeBufferAction', '未知实时缓存操作：%s', action);
end
end

function value = localRecordNumeric(record, name)
value = NaN;
names = fieldnames(record);
idx = find(strcmp(names, name), 1);
if isempty(idx)
    idx = find(strcmpi(names, name), 1);
end
if isempty(idx)
    return;
end
candidate = record.(names{idx});
if isnumeric(candidate) && isscalar(candidate)
    value = double(candidate);
end
end

function signFactor = localInferSignFactor(solarV, solarA)
valid = isfinite(solarV) & isfinite(solarA) & solarV >= 0;
negativeCount = sum(solarA(valid) < 0);
positiveCount = sum(solarA(valid) > 0);
if negativeCount > positiveCount && negativeCount > 0
    signFactor = -1;
elseif positiveCount > negativeCount && positiveCount > 0
    signFactor = 1;
elseif any(valid)
    rawPowerMedian = median(solarV(valid) .* solarA(valid), 'omitnan');
    signFactor = -1 + 2 * (rawPowerMedian >= 0);
else
    signFactor = 1;
end
end

function [energy, capacity] = localIntegrateSession(time_s, solarV, solarA_raw, signFactor, breakBefore)
n = numel(time_s);
energy = zeros(n, 1);
capacity = zeros(n, 1);
if n < 2
    return;
end
for k = 2:n
    [powerPrevious, currentPrevious] = localGenerationValues( ...
        solarV(k-1), solarA_raw(k-1), signFactor);
    [powerCurrent, currentCurrent] = localGenerationValues( ...
        solarV(k), solarA_raw(k), signFactor);
    dt = time_s(k) - time_s(k-1);
    if ~breakBefore(k) && isfinite(dt) && dt > 0
        energy(k) = energy(k-1) + ...
            0.5 * (powerPrevious + powerCurrent) * dt / 3600;
        capacity(k) = capacity(k-1) + ...
            0.5 * (currentPrevious + currentCurrent) * dt * 1000 / 3600;
    else
        energy(k) = energy(k-1);
        capacity(k) = capacity(k-1);
    end
end
end

function [power, current] = localGenerationValues(solarV, solarA_raw, signFactor)
if ~isfinite(signFactor)
    signFactor = 1;
end
if ~isfinite(solarV) || ~isfinite(solarA_raw)
    power = 0;
    current = 0;
    return;
end
current = max(signFactor * solarA_raw, 0);
power = max(solarV * signFactor * solarA_raw, 0);
end

function data = localOverlaySessionTotals(data, buffer)
if isempty(buffer.records) || isempty(buffer.sessionEnergy_Wh)
    return;
end
data.Time_s = buffer.sessionTime_s;
data.breakBefore = buffer.sessionBreakBefore;
data.timeStatus = buffer.sessionTimeStatus;
data.clock = buffer.clock;
data.metrics.lastIndex = numel(buffer.records); % Latest measurement, even when Uptime_s is absent.
startIndex = 1;
data.Energy_Wh = buffer.sessionEnergy_Wh(startIndex:end);
data.Capacity_mAh = buffer.sessionCapacity_mAh(startIndex:end);
data.energyIsComputed = true;
data.energySource = '由实时 SolarPower_W 梯形积分计算';
data.capacityIsComputed = true;
data.capacitySource = '由实时 Solar_A_generation 梯形积分计算';
end
