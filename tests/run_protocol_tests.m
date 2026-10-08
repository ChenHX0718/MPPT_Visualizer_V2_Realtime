function results = run_protocol_tests()
%RUN_PROTOCOL_TESTS Tests the production byte receiver and original data pipeline.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(root));
groups=0;
hex=['FD09000000019E000000000000001208000403FB1D', ...
    'FD6C000001019E81010000800000674D50505401180001000000004F000000C219AB6487D6120023207B22557074696D655F73223A3132332C224261745F56223A32352E32302C22536F6C61725F56223A32382E31302C22536F6C61725F41223A312E32352C224572726F72466C616773223A307D0A2F35'];
reference=uint8(sscanf(hex,'%2x').');
raw=uint8(sprintf('# {"Uptime_s":123,"Bat_V":25.20,"Solar_V":28.10,"Solar_A":1.25,"ErrorFlags":0}\n'));
assert(numel(raw)==79 && mppt.crc32(raw)==uint32(hex2dec('64AB19C2')));
assert(mppt.crc32(uint8('123456789'))==uint32(hex2dec('CBF43926')));
rng(385);
for sizes={1,2,7,19,[3 1 13 2 27],randi(31,1,40),10000}
    rx=mppt.TelemetryReceiver(); out=chunks(rx,reference,sizes{1});
    assert(numel(out)==1 && out{1}.valid && isequal(out{1}.rawBytes,raw));
    assert(out{1}.meta.record_seq==0 && out{1}.meta.boot_ms==1234567);
    assert(out{1}.meta.sysid==1 && out{1}.meta.compid==158);
    assert(strcmp(rx.Protocol,'MAVLink 2 MPPT'));
end
groups=groups+1;

% Same fields, plot data, append count and totals with both wire formats.
text=uint8([]); binary=uint8([]);
for k=0:10
    record=sample(k); text=[text,record]; %#ok<AGROW>
    frames=pack(record,k,1000*k); binary=[binary,frames{:}]; %#ok<AGROW>
end
rx=mppt.TelemetryReceiver(); a=chunks(rx,text,randi(13,1,30));
rx=mppt.TelemetryReceiver(); b=chunks(rx,binary,randi(47,1,30));
assert(numel(a)==11 && numel(b)==11);
ba=mppt.realtimeBuffer('create'); bb=ba;
for k=1:11
    assert(isequal(a{k}.record,b{k}.record));
    ba=mppt.realtimeBuffer('append',ba,a{k}.record,a{k}.meta);
    bb=mppt.realtimeBuffer('append',bb,b{k}.record,b{k}.meta);
end
da=mppt.realtimeBuffer('data',ba); db=mppt.realtimeBuffer('data',bb);
assert(ba.acceptedCount==11 && bb.acceptedCount==11);
for name={'Bat_V','Solar_A_raw','SolarPower_W','Time_s','Energy_Wh','Capacity_mAh'}
    assert(isequaln(da.(name{1}),db.(name{1})));
end
assert(abs(db.Energy_Wh(end)-800/3600)<1e-12);
assert(abs(db.Capacity_mAh(end)-20000/3600)<1e-12);
assert(db.ErrorFlags(end)==4294967295 && db.rawRecords{end}.LoadErrFlags==4294967295);
assert(db.rawRecords{end}.FutureField==77 && isnan(db.SOC_pct(end)));
groups=groups+1;

% LF / CRLF, BOM, optional #, and half-lines across individual UTF-8 bytes.
unicode=unicode2native(sprintf('# {"Uptime_s":3,"Bat_V":25,"Solar_V":40,"Solar_A":0,"Note":"充电等待"}\r\n'),'UTF-8');
for wire={unicode,[uint8([239 187 191]),unicode],uint8(sprintf(' {"Bat_V":25}\n'))}
    rx=mppt.TelemetryReceiver(); out=chunks(rx,wire{1},1);
    assert(numel(out)==1 && out{1}.valid && strcmp(rx.Protocol,'ThingSet 文本'));
end
rx=mppt.TelemetryReceiver(); assert(isempty(rx.feed(raw(1:30),'serial:test',0)));
out=rx.feed(raw(31:end),'serial:test',1); assert(numel(out)==1 && out{1}.valid);
for line={'{"hello":1}','{"Uptime_s":7}','{"SOC_pct":50}','booting...'}
    rx=mppt.TelemetryReceiver(); out=rx.feed(uint8([line{1},newline]),'serial:test',0);
    assert(~any(cellfun(@(e)e.valid,out)) && strcmp(rx.Protocol,'等待识别'));
end
groups=groups+1;

for n=[104 105 208 2048]
    record=sizedRecord(n); frames=pack(record,4,4000);
    rx=mppt.TelemetryReceiver(); out=chunks(rx,[frames{:}],1);
    assert(numel(out)==1 && isequal(out{1}.rawBytes,record));
    assert(numel(frames)==ceil(n/104));
    assert(all(cellfun(@(f)f(2)<=133,frames)));
    if mod(n,104)>0, assert(any(cellfun(@(f)f(2)<133,frames))); end
end
% Place a 3-byte character astride fragment offset 104.
prefix=uint8('# {"Bat_V":25,"Note":"');
record=[prefix,uint8(repmat('a',1,103-numel(prefix))), ...
    unicode2native('电','UTF-8'),uint8(sprintf('"}\n'))];
frames=pack(record,0,0); rx=mppt.TelemetryReceiver(); out=chunks(rx,[frames{:}],1);
assert(numel(out)==1 && endsWith(out{1}.record.Note,'电'));
groups=groups+1;

record=sizedRecord(350); frames=pack(record,10,10000);
rx=mppt.TelemetryReceiver(); out=chunks(rx,[frames{3},frames{1},frames{1},frames{4},frames{2},frames{:}],10000);
assert(numel(out)==1 && rx.Stats.Duplicates>=5);
rx=mppt.TelemetryReceiver(); rx.feed(frames{1},'serial:test',0); rx.expire(3.1);
assert(rx.Stats.Timeouts==1); assert(isempty(rx.feed([frames{2:end}],'serial:test',3.2)));
next=pack(sample(11),11,11000); out=rx.feed([next{:}],'serial:test',3.3); assert(numel(out)==1);
% Conflicting fragment poisons the entire key even if valid fragments follow.
bad=frames{1}; bad(10+5+24+1)=bitxor(bad(10+5+24+1),uint8(1)); bad=recrc(bad);
rx=mppt.TelemetryReceiver(); out=rx.feed([frames{1},bad,frames{:}],'serial:test',0);
assert(isempty(out) && rx.Stats.BadRecords==1);
groups=groups+1;

% Both CRC layers, malformed metadata, corrupt LEN, noise and resynchronization.
single=pack(raw,0,1234567); good=single{1}; bad=good; bad(end)=bitxor(bad(end),uint8(1));
rx=mppt.TelemetryReceiver(); out=rx.feed([bad,good],'serial:test',0);
assert(numel(out)==1 && rx.Stats.BadFrames==1); % embedded JSON never delivered
rx=mppt.TelemetryReceiver(); assert(isempty(chunks(rx,bad,1)));
bad=good; bad(32)=bitxor(bad(32),uint8(1)); bad=recrc(bad); % record CRC32 field
rx=mppt.TelemetryReceiver(); assert(isempty(rx.feed(bad,'serial:test',0)));
assert(rx.Stats.BadRecords==1);
for position=[15 20 21 22 23 28 30] % payload length / version / header / fragment geometry
    bad=good;
    bad(position)=uint8(255); bad=recrc(bad);
    rx=mppt.TelemetryReceiver(); assert(isempty(rx.feed(bad,'serial:test',0)));
end
bad=good; bad(2)=250;
rx=mppt.TelemetryReceiver(); out=rx.feed([uint8([99 0 4]),bad,good],'serial:test',0);
assert(numel(out)==1 && rx.Stats.BadFrames>=1);
% A forged short LEN must not expose a complete inner ThingSet line.
bad=good; bad(2)=27;
rx=mppt.TelemetryReceiver(); out=rx.feed(bad,'serial:test',0);
assert(~any(cellfun(@(e)e.valid,out)));
rx=mppt.TelemetryReceiver(); rx.feed(uint8([253 250 0 0]),'serial:test',0); rx.expire(3.1);
out=rx.feed(raw,'serial:test',3.2); assert(numel(out)==1 && out{1}.valid);
groups=groups+1;

heartbeat=reference(1:21);
other=frame(uint8(zeros(1,31)),1,124,1,1,2,false);
v1=frame(uint8(zeros(1,36)),147,154,1,1,1,false);
unknown=frame(uint8([35 32 raw]),123,0,1,1,2,false);
signed=frame(uint8([0 128 0 0 0]),385,147,1,158,2,true);
rx=mppt.TelemetryReceiver(); out=rx.feed([heartbeat,other,v1,unknown,signed],'serial:test',0);
assert(isempty(out) && isnan(rx.LastValid_s) && strcmp(rx.Protocol,'等待识别') && rx.MavlinkSeen);
out=rx.feed(good,'serial:test',1); assert(numel(out)==1);
groups=groups+1;

rx=mppt.TelemetryReceiver(); out=rx.feed(raw,'serial:test',0); assert(numel(out)==1);
out=rx.feed(good,'serial:test',1); assert(numel(out)==1 && strcmp(rx.Protocol,'MAVLink 2 MPPT'));
out=rx.feed(raw,'serial:test',2); assert(numel(out)==1 && strcmp(rx.Protocol,'ThingSet 文本'));
rx.reset(); assert(isnan(rx.LastValid_s) && isempty(rx.Source));
out=rx.feed(good,'serial:test',0); assert(numel(out)==1);
rx=mppt.TelemetryReceiver(struct('SourceSystem',42,'SourceComponent',201));
assert(isempty(rx.feed(good,'serial:test',0)));
custom=pack(raw,0,1234567,42,201); out=rx.feed([custom{:}],'serial:test',0); assert(numel(out)==1);
groups=groups+1;

% UDP endpoint, sysid, compid, seq and boot isolation and source pinning.
frames=pack(sizedRecord(350),4,4000);
rx=mppt.TelemetryReceiver(); assert(isempty(rx.feed(frames{1},'udp:127.0.0.1:1',0)));
assert(isempty(rx.feed([frames{2:end}],'udp:127.0.0.1:2',0)));
out=rx.feed([frames{2:end}],'udp:127.0.0.1:1',0); assert(numel(out)==1);
other=pack(sample(5),5,5000,2,158);
assert(isempty(rx.feed([other{:}],'udp:127.0.0.1:1',1)));
assert(isempty(rx.feed(raw,'udp:127.0.0.1:2',1)) && rx.Stats.IgnoredSources>=2);
for variant=1:3
    rx=mppt.TelemetryReceiver(); rx.feed(frames{1},'serial:test',0);
    for k=2:numel(frames)
        f=frames{k};
        if variant==1, f(6)=2; elseif variant==2, f(7)=159; else, f(36)=1; end
        f=recrc(f); assert(isempty(rx.feed(f,'serial:test',0)));
    end
end
groups=groups+1;

% Late completion does not reach metrics; record/boot wrap works in double.
rx=mppt.TelemetryReceiver(); old=pack(sizedRecord(350,10),10,10000);
assert(isempty(rx.feed(old{1},'serial:test',0)));
new=pack(sample(11),11,11000); out=rx.feed([new{:}],'serial:test',1); assert(numel(out)==1);
assert(isempty(rx.feed([old{2:end}],'serial:test',2)) && rx.Stats.LateRecords==1);
rx=mppt.TelemetryReceiver(); a=pack(sample(100),2^32-1,2^32-100);
b=pack(sample(101),0,900);
out=rx.feed([a{:},b{:}],'serial:test',0); assert(numel(out)==2);
groups=groups+1;

% Reboot requires consecutive records; maintain monotone plot time and Wh.
rx=mppt.TelemetryReceiver(); a=pack(sample(100),100,100000); b=pack(sample(101),101,101000);
out=rx.feed([a{:},b{:}],'serial:test',0); buffer=mppt.realtimeBuffer('create');
for k=1:numel(out), buffer=mppt.realtimeBuffer('append',buffer,out{k}.record,out{k}.meta); end
a=pack(sample(0),0,10); assert(isempty(rx.feed([a{:}],'serial:test',1)));
b=pack(sample(1),1,1010); out=rx.feed([b{:}],'serial:test',2);
assert(numel(out)==2 && out{1}.meta.restart);
for k=1:2, buffer=mppt.realtimeBuffer('append',buffer,out{k}.record,out{k}.meta); end
d=mppt.realtimeBuffer('data',buffer); assert(isequal(d.Time_s,[0;1;1;2]));
assert(abs(d.Energy_Wh(end)-160/3600)<1e-12 && d.breakBefore(3));
old=pack(sample(101),101,101000); assert(isempty(rx.feed([old{:}],'serial:test',2.1)));
rx=mppt.TelemetryReceiver(); a=pack(sample(2^32-1),99,1000); b=pack(sample(0),100,2000);
out=rx.feed([a{:},b{:}],'serial:test',0); assert(numel(out)==2 && out{2}.meta.uptimeWrap);
buffer=mppt.realtimeBuffer('create');
for k=1:2, buffer=mppt.realtimeBuffer('append',buffer,out{k}.record,out{k}.meta); end
d=mppt.realtimeBuffer('data',buffer); assert(isequal(d.Time_s,[0;1]));
groups=groups+1;

% Bounded state during floods; silence expiry is independent of the next read.
rx=mppt.TelemetryReceiver(struct('MaxAssemblies',2,'MaxDone',3,'MaxEndpoints',2));
for k=1:10
    f=pack(sizedRecord(350),k,1000*k); rx.feed(f{1},'serial:test',0);
end
rx.expire(4); assert(rx.Stats.Timeouts==2 && rx.Stats.BadRecords==8);
rx.feed(uint8(repmat('a',1,20000)),'endpoint:2',4);
rx.feed(raw,'endpoint:3',4); assert(rx.Stats.BufferDrops>=2);
rx.expire(40); out=rx.feed(raw,'serial:test',40); assert(numel(out)==1 && out{1}.valid);
groups=groups+1;

% Legacy live ordering, reboot, wrap and missing optional measurements.
rx=mppt.TelemetryReceiver(); out=rx.feed([sample(100),sample(101)],'serial:test',0);
assert(numel(out)==2);
assert(isempty(rx.feed(sample(90),'serial:test',1)));
out=rx.feed(sample(102),'serial:test',2); assert(numel(out)==1);
assert(isempty(rx.feed(sample(0),'serial:test',3)));
out=rx.feed(sample(1),'serial:test',4); assert(numel(out)==2 && out{1}.meta.restart);
rx=mppt.TelemetryReceiver(); out=rx.feed([sample(2^32-1),sample(0)],'serial:test',0);
assert(numel(out)==2 && out{2}.meta.uptimeWrap);
rx=mppt.TelemetryReceiver(); partial=uint8(sprintf('{"Solar_V":40,"Solar_A":0}\n'));
out=rx.feed(partial,'serial:test',0); assert(numel(out)==1 && out{1}.valid);
data=mppt.processMPPTData({out{1}.record});
assert(isnan(data.Bat_V) && isnan(data.ErrorFlags) && isnan(data.Time_s));
groups=groups+1;

% Byte-exact decoded log, history/Replay roundtrip and full-field CSV.
tmp=[tempname,'.log']; csv=[tempname,'.csv'];
cleanup=onCleanup(@()cleanFiles({tmp,csv})); %#ok<NASGU>
fid=fopen(tmp,'wb');
fwrite(fid,raw,'uint8'); fwrite(fid,unicode,'uint8'); fclose(fid);
[records,report]=mppt.parseHistoryLog(tmp); assert(report.parsedCount==2);
fid=fopen(tmp,'r','n','UTF-8'); count=0;
while true
    line=fgetl(fid); if ~ischar(line), break; end
    [~,valid]=mppt.parseTelemetryLine(line); count=count+double(valid);
end
fclose(fid); assert(count==2 && numel(records)==2);
mppt.exportCSV(db,csv); c=readtable(csv,'VariableNamingRule','preserve');
assert(height(c)==11 && c.ErrorFlags(end)==4294967295 && c.LoadErrFlags(end)==4294967295);
assert(c.FutureField(end)==77 && abs(c.Energy_Wh(end)-db.Energy_Wh(end))<1e-12);
collision=db; collision.rawRecords{1}.Time_s=999;
mppt.exportCSV(collision,csv); c=readtable(csv,'VariableNamingRule','preserve');
assert(c.Time_s(1)==999 && c.Computed_Time_s(1)==0);
groups=groups+1;
results=struct('groupsPassed',groups,'referenceRecords',1,'equivalentSamples',11, ...
    'maxRecordBytes',2048,'crc32Check','CBF43926','Wh',db.Energy_Wh(end));
disp(results);
end

function out=chunks(rx,bytes,sizes)
out={}; offset=1; k=1;
while offset<=numel(bytes)
    n=sizes(1+mod(k-1,numel(sizes))); last=min(offset+n-1,numel(bytes));
    batch=rx.feed(bytes(offset:last),'serial:test',0);
    out=[out,batch]; offset=last+1; k=k+1; %#ok<AGROW>
end
end
function bytes=sample(t)
bytes=uint8(sprintf(['# {"Uptime_s":%.0f,"Bat_V":25,"Solar_V":40,"Solar_A":-2,' ...
    '"ErrorFlags":4294967295,"LoadErrFlags":4294967295,"ChgState":0,"FutureField":77}\n'],t));
end
function bytes=sizedRecord(n,t)
if nargin<2, t=3; end
prefix=sprintf('# {"Uptime_s":%.0f,"Bat_V":25,"Note":"',t); suffix=sprintf('"}\n');
bytes=uint8([prefix,repmat('x',1,n-numel(prefix)-numel(suffix)),suffix]);
assert(numel(bytes)==n);
end
function frames=pack(raw,seq,boot,sys,comp)
if nargin<4, sys=1; comp=158; end
count=ceil(numel(raw)/104); crc=mppt.crc32(raw); frames=cell(1,count);
for index=0:count-1
    offset=index*104;
    fragment=raw(offset+1:min(offset+104,numel(raw)));
    private=[uint8('MPPT'),uint8([1 24 index count]),encodeLE(seq,4), ...
        encodeLE(numel(raw),2),encodeLE(offset,2),encodeLE(crc,4),encodeLE(boot,4),fragment];
    body=[encodeLE(32768,2),uint8([0 0 numel(private)]),private, ...
        zeros(1,128-numel(private),'uint8')];
    body=body(1:find(body~=0,1,'last'));
    frames{index+1}=frame(body,385,147,sys,comp,2,false);
end
end
function bytes=frame(body,id,extra,sys,comp,version,signed)
if version==2
    header=uint8([253 numel(body) signed 0 0 sys comp double(encodeLE(id,3))]);
else
    header=uint8([254 numel(body) 0 sys comp id]);
end
bytes=[header,body,encodeLE(mppt.mavlinkCRC([header(2:end),body,uint8(extra)]),2)];
if signed, bytes=[bytes,zeros(1,13,'uint8')]; end
end
function bytes=recrc(bytes)
last=10+double(bytes(2));
bytes(last+1:last+2)=encodeLE(mppt.mavlinkCRC([bytes(2:last),uint8(147)]),2);
end
function bytes=encodeLE(value,n)
value=uint32(value); bytes=zeros(1,n,'uint8');
for k=1:n, bytes(k)=uint8(bitand(bitshift(value,-8*(k-1)),uint32(255))); end
end
function cleanFiles(paths)
for k=1:numel(paths), if isfile(paths{k}), delete(paths{k}); end, end
end

