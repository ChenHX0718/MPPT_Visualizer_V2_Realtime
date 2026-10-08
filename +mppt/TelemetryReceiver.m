classdef TelemetryReceiver < handle
    %TELEMETRYRECEIVER One byte consumer for serial and endpoint-isolated UDP.
    % feed(bytes, endpoint, monotonicSeconds) returns complete, validated events.
    % expire() must also run during silence. No transport reads or writes here.
    properties (SetAccess = private)
        Config
        Stats
        Protocol = '等待识别'
        Source = ''
        LastValid_s = NaN
        MavlinkSeen = false
    end
    properties (Access = private)
        Streams
        Assemblies
        Done
        SelectedEndpoint = ''
        SelectedIDs = []
        Order = []
        LegacyOrder = []
    end
    methods
        function obj = TelemetryReceiver(config)
            obj.Config = struct('AssemblyTimeout_s',3,'ByteTimeout_s',3, ...
                'DedupLifetime_s',15,'EndpointLifetime_s',30, ...
                'MaxAssemblies',64,'MaxDone',256,'MaxEndpoints',16, ...
                'MaxBytes',16384,'MaxLineBytes',8192, ...
                'SourceSystem',0,'SourceComponent',0);
            if nargin > 0
                names = fieldnames(config);
                for k = 1:numel(names)
                    assert(isfield(obj.Config,names{k}),'MPPT:Config','Unknown setting');
                    obj.Config.(names{k}) = config.(names{k});
                end
            end
            obj.reset();
        end
        function reset(obj)
            obj.Streams = containers.Map('KeyType','char','ValueType','any');
            obj.Assemblies = containers.Map('KeyType','char','ValueType','any');
            obj.Done = containers.Map('KeyType','char','ValueType','double');
            obj.SelectedEndpoint = ''; obj.SelectedIDs = []; obj.Order = []; obj.LegacyOrder=[];
            obj.Protocol = '等待识别'; obj.Source = ''; obj.LastValid_s = NaN;
            obj.MavlinkSeen = false;
            obj.Stats = struct('BadFrames',0,'BadRecords',0,'Timeouts',0, ...
                'Duplicates',0,'LateRecords',0,'IgnoredSources',0, ...
                'UnsupportedFrames',0,'InvalidLines',0,'BufferDrops',0);
        end
        function expire(obj, now_s)
            keys = obj.Assemblies.keys;
            for k = 1:numel(keys)
                a = obj.Assemblies(keys{k});
                if now_s-a.created >= obj.Config.AssemblyTimeout_s
                    remove(obj.Assemblies,keys{k});
                    obj.remember(keys{k},now_s);
                    obj.Stats.Timeouts = obj.Stats.Timeouts+1;
                end
            end
            keys = obj.Done.keys;
            for k = 1:numel(keys)
                if now_s-obj.Done(keys{k}) >= obj.Config.DedupLifetime_s
                    remove(obj.Done,keys{k});
                end
            end
            keys = obj.Streams.keys;
            for k = 1:numel(keys)
                s = obj.Streams(keys{k});
                if ~isempty(s.bytes) && now_s-s.since >= obj.Config.ByteTimeout_s
                    % Never reinterpret bytes of a stalled binary candidate as text.
                    s.bytes = uint8([]); s.discardLine = false;
                    obj.Stats.BufferDrops = obj.Stats.BufferDrops+1;
                end
                if now_s-s.last >= obj.Config.EndpointLifetime_s
                    remove(obj.Streams,keys{k});
                else
                    obj.Streams(keys{k}) = s;
                end
            end
            if ~isempty(obj.Order) && ~isempty(obj.Order.pending) && ...
                    now_s-obj.Order.pending.at >= obj.Config.AssemblyTimeout_s
                obj.Order.pending = [];
            end
            if ~isempty(obj.LegacyOrder) && ~isempty(obj.LegacyOrder.pending) && ...
                    now_s-obj.LegacyOrder.pending.at >= obj.Config.AssemblyTimeout_s
                obj.LegacyOrder.pending=[];
            end
        end
        function events = feed(obj, bytes, endpoint, now_s)
            obj.expire(now_s);
            events = {};
            bytes = reshape(uint8(bytes),1,[]);
            endpoint = char(endpoint);
            if isempty(bytes), return; end
            if ~isKey(obj.Streams,endpoint)
                if obj.Streams.Count >= obj.Config.MaxEndpoints
                    obj.Stats.BufferDrops = obj.Stats.BufferDrops+1;
                    return;
                end
                s = struct('bytes',uint8([]),'since',now_s,'last',now_s, ...
                    'discardLine',false);
            else
                s = obj.Streams(endpoint);
            end
            % Limit temporary allocations even if a caller passes a huge chunk.
            for start = 1:4096:numel(bytes)
                if isempty(s.bytes), s.since = now_s; end
                s.last = now_s;
                s.bytes = [s.bytes,bytes(start:min(start+4095,numel(bytes)))];
                [s,out] = obj.consume(s,endpoint,now_s);
                events = [events,out]; %#ok<AGROW>
                if numel(s.bytes)>obj.Config.MaxBytes
                    s.bytes = uint8([]); s.discardLine = true;
                    obj.Stats.BufferDrops = obj.Stats.BufferDrops+1;
                end
            end
            obj.Streams(endpoint) = s;
        end
    end
    methods (Access = private)
        function [s,events] = consume(obj,s,endpoint,now_s)
            events = {};
            while ~isempty(s.bytes)
                b = s.bytes;
                if b(1)==253 || b(1)==254
                    [complete,total,id,header,signed] = frameInfo(b);
                    if ~complete
                        % A corrupted LEN cannot indefinitely hide a later CRC-valid frame.
                        next = nextVerifiedFrame(b);
                        if next>0
                            s.bytes = b(next:end); s.since = now_s;
                            obj.Stats.BadFrames = obj.Stats.BadFrames+1;
                            continue;
                        end
                        break;
                    end
                    extra = crcExtra(id);
                    if isempty(extra)
                        % Unknown CRC_EXTRA: skip by framing, never claim CRC success.
                        obj.Stats.UnsupportedFrames = obj.Stats.UnsupportedFrames+1;
                    elseif ~frameCRC(b(1:total),header,extra)
                        obj.Stats.BadFrames = obj.Stats.BadFrames+1;
                        s.discardLine=true;
                        next = nextVerifiedFrame(b);
                        if next>0 && next<=total
                            s.bytes=b(next:end); s.since=now_s; continue;
                        end
                    else
                        obj.MavlinkSeen = true;
                        s.discardLine=false;
                        if b(1)==253 && id==385 && ~signed && b(3)==0
                            out = obj.tunnel(b(header+1:header+double(b(2))), ...
                                endpoint,double(b(6)),double(b(7)),now_s);
                            events=[events,out]; %#ok<AGROW>
                        elseif signed || id~=0
                            obj.Stats.UnsupportedFrames=obj.Stats.UnsupportedFrames+1;
                        end
                    end
                    % Consume bad candidates too: their embedded JSON is quarantined.
                    s.bytes=b(total+1:end); s.since=now_s;
                else
                    magic=find(b==253 | b==254,1);
                    lf=find(b==10,1);
                    if ~isempty(magic) && (isempty(lf) || magic<lf)
                        s.bytes=b(magic:end); s.discardLine=false; s.since=now_s;
                    elseif ~isempty(lf)
                        raw=b(1:lf); s.bytes=b(lf+1:end); s.since=now_s;
                        if ~s.discardLine && numel(raw)<=obj.Config.MaxLineBytes
                            e=obj.textEvent(raw,endpoint,'ThingSet 文本',[],now_s);
                            if ~isempty(e), events=[events,e]; end %#ok<AGROW>
                        end
                        s.discardLine=false;
                    else
                        if numel(b)>obj.Config.MaxLineBytes
                            s.bytes=uint8([]); s.discardLine=true;
                            obj.Stats.BufferDrops=obj.Stats.BufferDrops+1;
                        end
                        break;
                    end
                end
            end
        end
        function events = tunnel(obj,body,endpoint,sys,comp,now_s)
            events={};
            if numel(body)>133, obj.Stats.BadRecords=obj.Stats.BadRecords+1; return; end
            body(end+1:133)=uint8(0); % AFTER CRC: MAVLink 2 trailing-zero restoration.
            if readLE(body(1:2))~=32768, return; end
            if (obj.Config.SourceSystem~=0 && sys~=obj.Config.SourceSystem) || ...
                    (obj.Config.SourceComponent~=0 && comp~=obj.Config.SourceComponent)
                obj.Stats.IgnoredSources=obj.Stats.IgnoredSources+1; return;
            end
            n=double(body(5));
            if n<24 || n>128, obj.Stats.BadRecords=obj.Stats.BadRecords+1; return; end
            p=body(6:5+n);
            if ~isequal(p(1:4),uint8('MPPT')), return; end
            index=double(p(7)); count=double(p(8)); seq=readLE(p(9:12));
            len=double(readLE(p(13:14))); offset=double(readLE(p(15:16)));
            crc=readLE(p(17:20)); boot=readLE(p(21:24));
            key=sprintf('%s|%d|%d|%.0f|%.0f',endpoint,sys,comp,double(seq),double(boot));
            if isKey(obj.Done,key)
                obj.Stats.Duplicates=obj.Stats.Duplicates+1; return;
            end
            valid=p(5)==1 && p(6)==24 && len>=1 && len<=2048 && ...
                count==ceil(len/104) && index<count && offset==index*104 && ...
                n==24+min(104,len-offset);
            if ~valid
                obj.reject(key,now_s); return;
            end
            if ~isempty(obj.SelectedEndpoint) && ...
                    (~strcmp(endpoint,obj.SelectedEndpoint) || ...
                    (~isempty(obj.SelectedIDs) && ~isequal([sys comp],obj.SelectedIDs)))
                obj.Stats.IgnoredSources=obj.Stats.IgnoredSources+1; return;
            end
            if isKey(obj.Assemblies,key)
                a=obj.Assemblies(key);
                if a.len~=len || a.count~=count || a.crc~=crc
                    obj.reject(key,now_s); return;
                end
            else
                if obj.Assemblies.Count>=obj.Config.MaxAssemblies
                    obj.reject(key,now_s); return;
                end
                a=struct('len',len,'count',count,'crc',crc,'created',now_s, ...
                    'parts',{cell(1,count)},'seen',false(1,count));
            end
            fragment=p(25:end);
            if a.seen(index+1)
                if ~isequal(a.parts{index+1},fragment), obj.reject(key,now_s);
                else, obj.Stats.Duplicates=obj.Stats.Duplicates+1; end
                return;
            end
            a.parts{index+1}=fragment; a.seen(index+1)=true;
            obj.Assemblies(key)=a;
            if ~all(a.seen), return; end
            remove(obj.Assemblies,key); obj.remember(key,now_s);
            raw=[a.parts{:}];
            if numel(raw)~=len || raw(end)~=10 || any(raw==0) || ...
                    sum(raw==10)~=1 || mppt.crc32(raw)~=crc
                obj.Stats.BadRecords=obj.Stats.BadRecords+1; return;
            end
            meta=struct('sysid',sys,'compid',comp,'record_seq',seq, ...
                'boot_ms',boot,'restart',false,'uptimeWrap',false,'firstSeen_s',a.created);
            events=obj.textEvent(raw,endpoint,'MAVLink 2 MPPT',meta,now_s);
        end
        function events = textEvent(obj,raw,endpoint,protocol,meta,now_s)
            events={};
            line=native2unicode(raw,'UTF-8');
            % Reject invalid UTF-8 rather than silently replacing damaged bytes.
            utfValid=isequal(reshape(unicode2native(line,'UTF-8'),1,[]),raw);
            [record,valid]=mppt.parseTelemetryLine(line);
            valid=valid && utfValid && (numeric(record,'Bat_V') || numeric(record,'Solar_V'));
            e=struct('record',record,'valid',valid,'rawBytes',raw,'line',line, ...
                'protocol',protocol,'endpoint',endpoint,'meta',meta);
            if ~valid
                if isempty(meta)
                    obj.Stats.InvalidLines=obj.Stats.InvalidLines+1;
                    % Preserve legacy raw-line logging without identifying a protocol.
                    if (~obj.MavlinkSeen || strcmp(obj.Protocol,'ThingSet 文本')) && ...
                            (isempty(obj.SelectedEndpoint) || strcmp(obj.SelectedEndpoint,endpoint))
                        events={e};
                    end
                else
                    obj.Stats.BadRecords=obj.Stats.BadRecords+1;
                end
                return;
            end
            if ~isempty(obj.SelectedEndpoint) && ~strcmp(endpoint,obj.SelectedEndpoint)
                obj.Stats.IgnoredSources=obj.Stats.IgnoredSources+1; return;
            end
            if isempty(obj.SelectedEndpoint), obj.SelectedEndpoint=endpoint; end
            if ~isempty(meta)
                ids=[meta.sysid meta.compid];
                if ~isempty(obj.SelectedIDs) && ~isequal(ids,obj.SelectedIDs)
                    obj.Stats.IgnoredSources=obj.Stats.IgnoredSources+1; return;
                end
                obj.SelectedIDs=ids;
                events=obj.orderEvent(e,now_s);
            else
                events=obj.orderText(e,now_s);
            end
            for k=1:numel(events)
                obj.Protocol=protocol; obj.LastValid_s=now_s;
                obj.Source=endpoint;
                if ~isempty(meta)
                    obj.Source=sprintf('%s / sys %d comp %d',endpoint,meta.sysid,meta.compid);
                end
            end
        end
        function events = orderEvent(obj,e,now_s)
            % Modular arithmetic is performed in double (all uint32 values exact).
            % Two consecutive low-boot, low-sequence records confirm a reboot;
            % one old completion alone must never roll the live clock backwards.
            events={}; m=e.meta;
            if isempty(obj.Order)
                obj.Order=struct('boot',m.boot_ms,'seq',m.record_seq, ...
                    'pending',[],'retired',[],'retiredUntil',-Inf);
            else
                o=obj.Order;
                if ~isempty(o.retired) && now_s<o.retiredUntil && ...
                        abs(double(m.boot_ms)-double(o.retired))<=3000
                    obj.Stats.LateRecords=obj.Stats.LateRecords+1; return;
                end
                db=mod(double(m.boot_ms)-double(o.boot),2^32);
                ds=mod(double(m.record_seq)-double(o.seq),2^32);
                if db<2^31 && ds>0 && ds<2^31
                    e.meta.uptimeWrap=numeric(e.record,'Uptime_s') && ...
                        isfield(o,'uptime') && o.uptime>2^32-60 && double(e.record.Uptime_s)<60;
                    o.pending=[];
                elseif db>=2^31 && double(m.boot_ms)<double(o.boot) && ...
                        (double(m.record_seq)<=double(o.seq) || ~isempty(o.pending)) && ...
                        m.firstSeen_s>=obj.LastValid_s
                    if ~isempty(o.pending)
                        pm=o.pending.event.meta;
                        forwardBoot=mod(double(m.boot_ms)-double(pm.boot_ms),2^32);
                        forwardSeq=mod(double(m.record_seq)-double(pm.record_seq),2^32);
                        if forwardBoot>0 && forwardBoot<10000 && forwardSeq>0 && forwardSeq<100
                            first=o.pending.event; first.meta.restart=true;
                            events={first}; o.retired=o.boot;
                            o.retiredUntil=now_s+obj.Config.DedupLifetime_s;
                            o.pending=[];
                        else
                            o.pending=struct('event',e,'at',now_s);
                            obj.Order=o; obj.Stats.LateRecords=obj.Stats.LateRecords+1; return;
                        end
                    else
                        o.pending=struct('event',e,'at',now_s);
                        obj.Order=o; obj.Stats.LateRecords=obj.Stats.LateRecords+1; return;
                    end
                else
                    obj.Stats.LateRecords=obj.Stats.LateRecords+1; return;
                end
                obj.Order=o;
            end
            obj.Order.boot=m.boot_ms; obj.Order.seq=m.record_seq;
            if numeric(e.record,'Uptime_s'), obj.Order.uptime=double(e.record.Uptime_s); end
            events{end+1}=e;
            if numeric(e.record,'Uptime_s')
                obj.LegacyOrder=struct('uptime',double(e.record.Uptime_s),'pending',[]);
            end
        end
        function events=orderText(obj,e,now_s)
            events={};
            if ~numeric(e.record,'Uptime_s'), events={e}; return; end
            uptime=double(e.record.Uptime_s);
            if isempty(obj.LegacyOrder)
                obj.LegacyOrder=struct('uptime',uptime,'pending',[]);
            else
                o=obj.LegacyOrder;
                if uptime<o.uptime
                    if o.uptime>2^32-60 && uptime<60
                        e.meta=struct('restart',false,'uptimeWrap',true);
                    elseif ~isempty(o.pending) && now_s-o.pending.at<obj.Config.AssemblyTimeout_s && ...
                            uptime>double(o.pending.event.record.Uptime_s)
                        first=o.pending.event;
                        first.meta=struct('restart',true,'uptimeWrap',false);
                        events={first};
                    else
                        o.pending=struct('event',e,'at',now_s);
                        obj.LegacyOrder=o;
                        obj.Stats.LateRecords=obj.Stats.LateRecords+1; return;
                    end
                end
            end
            obj.LegacyOrder=struct('uptime',uptime,'pending',[]);
            events{end+1}=e;
        end
        function reject(obj,key,now_s)
            if isKey(obj.Assemblies,key), remove(obj.Assemblies,key); end
            obj.remember(key,now_s);
            obj.Stats.BadRecords=obj.Stats.BadRecords+1;
        end
        function remember(obj,key,now_s)
            if obj.Done.Count>=obj.Config.MaxDone && ~isKey(obj.Done,key)
                keys=obj.Done.keys; values=cell2mat(obj.Done.values);
                [~,old]=min(values); remove(obj.Done,keys{old});
            end
            obj.Done(key)=now_s;
        end
    end
end

function yes=numeric(record,name)
yes=isfield(record,name) && isnumeric(record.(name)) && ...
    isscalar(record.(name)) && isreal(record.(name)) && isfinite(double(record.(name)));
end
function value=readLE(bytes)
value=uint32(0);
for k=1:numel(bytes), value=bitor(value,bitshift(uint32(bytes(k)),8*(k-1))); end
end
function [complete,total,id,header,signed]=frameInfo(b)
complete=false; total=Inf; id=-1; signed=false;
if b(1)==253, header=10; else, header=6; end
if numel(b)<header, return; end
if header==10
    signed=bitand(b(3),uint8(1))~=0;
    id=double(readLE(b(8:10))); total=double(b(2))+12+13*double(signed);
else
    id=double(b(6)); total=double(b(2))+8;
end
complete=numel(b)>=total;
end
function extra=crcExtra(id)
% Only known definitions are CRC-validated; other dialect messages are skipped.
switch id
    case 0, extra=50;
    case 1, extra=124;
    case 147, extra=154;
    case 385, extra=147;
    otherwise, extra=[];
end
end
function yes=frameCRC(b,header,extra)
last=header+double(b(2));
yes=mppt.mavlinkCRC([b(2:last),uint8(extra)])==uint16(readLE(b(last+1:last+2)));
end
function index=nextVerifiedFrame(b)
index=0;
positions=find(b==253 | b==254);
for p=positions(positions>1)
    [complete,total,id,header]=frameInfo(b(p:end));
    extra=crcExtra(id);
    if complete && ~isempty(extra) && frameCRC(b(p:p+total-1),header,extra)
        index=p; return;
    end
end
end

