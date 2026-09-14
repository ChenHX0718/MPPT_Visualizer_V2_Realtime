function varargout = realtimeBuffer(action, varargin)
%REALTIMEBUFFER 固定长度 MPPT 实时记录缓存。
%   buffer = mppt.realtimeBuffer('create', maxPoints)
%   [buffer, data] = mppt.realtimeBuffer('append', buffer, record)
%   data = mppt.realtimeBuffer('data', buffer)

switch lower(char(action))
    case 'create'
        maxPoints = 500;
        if ~isempty(varargin) && isnumeric(varargin{1}) && isscalar(varargin{1})
            maxPoints = max(10, round(varargin{1}));
        end
        buffer = struct('maxPoints', maxPoints, 'records', {cell(0, 1)}, ...
            'acceptedCount', 0, 'signFactor', NaN, 'signFactorLocked', false);
        varargout{1} = buffer;

    case 'append'
        buffer = varargin{1};
        record = varargin{2};
        buffer.records{end+1, 1} = record;
        if numel(buffer.records) > buffer.maxPoints
            buffer.records = buffer.records(end-buffer.maxPoints+1:end);
        end
        buffer.acceptedCount = buffer.acceptedCount + 1;

        % 至少观察 5 个有效太阳能样本后锁定符号方向，避免只依赖一个点。
        if ~buffer.signFactorLocked
            [solarV, solarA] = localSolarValues(buffer.records);
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
        data = mppt.processMPPTData(buffer.records, buffer.signFactor);
        varargout{1} = buffer;
        varargout{2} = data;

    case 'data'
        buffer = varargin{1};
        varargout{1} = mppt.processMPPTData(buffer.records, buffer.signFactor);

    case 'clear'
        maxPoints = varargin{1}.maxPoints;
        varargout{1} = mppt.realtimeBuffer('create', maxPoints);

    otherwise
        error('MPPT:RealtimeBufferAction', '未知实时缓存操作：%s', action);
end
end

function [solarV, solarA] = localSolarValues(records)
solarV = NaN(numel(records), 1);
solarA = NaN(numel(records), 1);
for k = 1:numel(records)
    record = records{k};
    if isfield(record, 'Solar_V') && isnumeric(record.Solar_V) && isscalar(record.Solar_V)
        solarV(k) = double(record.Solar_V);
    end
    if isfield(record, 'Solar_A') && isnumeric(record.Solar_A) && isscalar(record.Solar_A)
        solarA(k) = double(record.Solar_A);
    end
end
end
