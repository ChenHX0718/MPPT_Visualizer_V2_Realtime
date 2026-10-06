function results = run_time_window_tests()
%RUN_TIME_WINDOW_TESTS 时间零点、取窗、异常和累计一致性的定量验收。
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(root));
groups=0;
b=mppt.realtimeBuffer('create',500);
for t=0:1200
    b=mppt.realtimeBuffer('append',b,sample(uint32(10000+t)));
end
d=mppt.realtimeBuffer('data',b);
assert(b.sessionStartUptime_s==10000 && isequal(d.Time_s,(0:1200)'));
assert(numel(b.records)==1201 && isinf(b.maxPoints));
totals=[d.Energy_Wh(end),d.Capacity_mAh(end)];
assert(max(abs(totals-[80*1200/3600,2000*1200/3600]))<1e-9);
[idx,lim]=mppt.timeWindow(d.Time_s,500);
assert(nnz(idx)==501 && isequal(d.Time_s(idx),(700:1200)') && isequal(lim,[700 1200]));
assert(isequal(d.Bat_V(idx),24+d.Time_s(idx)/10000));
[x,y]=mppt.plotSeries(d.Time_s,d.Bat_V,d.breakBefore,idx);
assert(isequal(x,(700:1200)') && numel(y)==501);
groups=groups+1;

for duration=[60,300,500,1800,3600,Inf,123.5,60,500,Inf]
    [idx,lim]=mppt.timeWindow(d.Time_s,duration);
    expected=d.Time_s>=max(0,1200-duration) & d.Time_s<=1200;
    assert(isequal(idx,expected) && all(isfinite(lim)) && lim(2)>lim(1));
    assert(isequal([d.Energy_Wh(end),d.Capacity_mAh(end)],totals));
end
assert(b.sessionStartUptime_s==10000 && nnz(idx)==1201);
groups=groups+1;

for times={0:2:1200,[0 1 5 9 10 30 32 33 499 700 701 999 1200]}
    records=arrayfun(@(t) sample(10000+t),times{1}(:),'UniformOutput',false);
    batch=mppt.processMPPTData(records,1);
    rb=mppt.realtimeBuffer('create');
    for k=1:numel(records), rb=mppt.realtimeBuffer('append',rb,records{k}); end
    streamed=mppt.realtimeBuffer('data',rb);
    assert(isequal(streamed.Time_s,times{1}(:)));
    assert(isequal(streamed.Time_s,batch.Time_s));
    assert(max(abs(streamed.Energy_Wh-batch.Energy_Wh))<1e-9);
    [idx,~]=mppt.timeWindow(streamed.Time_s,500);
    assert(isequal(streamed.Time_s(idx),times{1}(times{1}>=700)'));
end
groups=groups+1;

[idx,lim]=mppt.timeWindow([],500); assert(isempty(idx) && isequal(lim,[0 1]));
[idx,lim]=mppt.timeWindow(0,500); assert(idx && lim(2)>lim(1));
[idx,lim]=mppt.timeWindow((0:60)',500); assert(all(idx) && isequal(lim,[0 60]));
records={sample(10000),sample(10001),sample(10001),rmfield(sample(10002),'Uptime_s'),sample(10005),sample(10006),sample(10030),sample(10031)};
edge=mppt.processMPPTData(records,1);
assert(isequaln(edge.Time_s,[0;1;1;NaN;5;6;30;31]));
assert(max(abs(edge.Energy_Wh-80/3600*[0;1;1;1;1;2;2;3]))<1e-12);
assert(edge.clock.duplicateCount==1 && edge.clock.missingCount==1 && edge.clock.gapCount==1);
[x,y]=mppt.plotSeries(edge.Time_s,edge.Bat_V,edge.breakBefore);
assert(any(isnan(x)) && numel(x)==numel(y));
for bad={[],0,-1,NaN,Inf,1i,'oops'}
    c=mppt.recordTime(); [c,t]=mppt.recordTime(c,bad{1});
    if isequal(bad{1},0), assert(t==0); else, assert(isnan(t)); end
end
groups=groups+1;

records={sample(uint32(10000)),sample(uint32(10001)),sample(uint32(2)),sample(uint32(3)),sample(uint32(10002))};
edge=mppt.processMPPTData(records,1);
rb=mppt.realtimeBuffer('create');
for k=1:numel(records), rb=mppt.realtimeBuffer('append',rb,records{k}); end
streamed=mppt.realtimeBuffer('data',rb);
assert(isequaln(edge.Time_s,[0;1;NaN;NaN;NaN]));
assert(edge.clock.invalidated && rb.clock.invalidated && numel(rb.records)==5);
assert(all(edge.Energy_Wh(2:end)==edge.Energy_Wh(2)));
assert(isequal(edge.Energy_Wh,streamed.Energy_Wh));
rb=mppt.realtimeBuffer('clear',rb); [rb,one]=mppt.realtimeBuffer('append',rb,sample(uint32(3)));
assert(one.Time_s==0 && one.Energy_Wh==0 && rb.sessionStartUptime_s==3);
groups=groups+1;

% Replay的批量到达/刷新频率仅影响显示调用次数，不改变记录时间与积分。
for batchSize=[1,5,10]
    rb=mppt.realtimeBuffer('create');
    for k=1:61
        rb=mppt.realtimeBuffer('append',rb,sample(10000+2*(k-1)));
        if mod(k,batchSize)==0
            snapshot=mppt.realtimeBuffer('data',rb);
            mppt.timeWindow(snapshot.Time_s,60);
        end
    end
    snapshot=mppt.realtimeBuffer('data',rb);
    assert(isequal(snapshot.Time_s,(0:2:120)'));
    assert(abs(snapshot.Energy_Wh(end)-80*120/3600)<1e-10);
    assert(abs(snapshot.Capacity_mAh(end)-2000*120/3600)<1e-10);
end
groups=groups+1;
results=struct('groupsPassed',groups,'window500Points',501,'window500Limits',[700 1200], ...
    'retainedRecords',numel(b.records),'energyWh',totals(1),'capacitymAh',totals(2));
disp(results);
end

function r=sample(uptime)
r=struct('Uptime_s',uptime,'Bat_V',24+(double(uptime)-10000)/10000,'Solar_V',40,'Solar_A',2);
end
