function results=run_transport_tests(previewDir)
%RUN_TRANSPORT_TESTS Actual GUI timer + local UDP sockets; no device commands.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(root));
beforeTimers=timerfindall;
beforeLogs=dir(fullfile(root,'realtime_logs','*.log'));
app=MPPT_Visualizer(); app.Visible='off';
sender1=udpport('datagram','IPV4','LocalHost','127.0.0.1');
sender2=udpport('datagram','IPV4','LocalHost','127.0.0.1');
newLogs={}; created=containers.Map('KeyType','char','ValueType','logical');
prior=fullfile({beforeLogs.folder},{beforeLogs.name});
cleanup=onCleanup(@()finish(app,sender1,sender2,created,prior)); %#ok<NASGU>
mode=findall(app,'Type','uidropdown');
mode=mode(arrayfun(@(h)any(strcmp(h.Items,'实时UDP')),mode));
assert(isscalar(mode)); mode.Value='实时UDP'; mode.ValueChangedFcn(mode,[]);
buttons=findall(app,'Type','uibutton'); listen=buttons(strcmp({buttons.Text},'监听'));
numeric=findall(app,'-isa','matlab.ui.control.NumericEditField');
port=numeric(arrayfun(@(h)h.Value==14552,numeric)); assert(isscalar(port));
probe=udpport('datagram','IPV4','LocalHost','127.0.0.1'); chosenPort=probe.LocalPort; delete(probe);
port.Value=chosenPort;
disconnect=buttons(strcmp({buttons.Text},'断开'));
disconnect=disconnect(1);
hex=['FD09000000019E000000000000001208000403FB1D', ...
    'FD6C000001019E81010000800000674D50505401180001000000004F000000C219AB6487D6120023207B22557074696D655F73223A3132332C224261745F56223A32352E32302C22536F6C61725F56223A32382E31302C22536F6C61725F41223A312E32352C224572726F72466C616773223A307D0A2F35'];
bytes=uint8(sscanf(hex,'%2x').');
raw=uint8(sprintf('# {"Uptime_s":123,"Bat_V":25.20,"Solar_V":28.10,"Solar_A":1.25,"ErrorFlags":0}\n'));
for cycle=1:3
    listen.ButtonPushedFcn(listen,[]); drawnow;
    reception=timerfindall('Name','MPPT byte reception'); assert(numel(reception)==1);
    state=snapshot(reception); assert(~isempty(state.udp) && isempty(state.serial));
    newLogs{end+1}=state.logPath; %#ok<AGROW>
    created(state.logPath)=true;
    % HEARTBEAT cannot make a healthy MPPT sample.
    write(sender1,bytes(1:21),'uint8','127.0.0.1',chosenPort); waitTicks(0.4);
    state=snapshot(reception); assert(state.validCount==0 && isnan(state.receiver.LastValid_s));
    % Same frame split across datagrams, with a second endpoint in the middle.
    write(sender1,bytes(22:70),'uint8','127.0.0.1',chosenPort); waitTicks(0.2);
    write(sender2,bytes(71:end),'uint8','127.0.0.1',chosenPort); waitTicks(0.2);
    state=snapshot(reception); assert(state.validCount==0);
    write(sender1,bytes(71:end),'uint8','127.0.0.1',chosenPort); waitTicks(0.5);
    state=snapshot(reception); assert(state.validCount==1 && state.buffer.acceptedCount==1);
    assert(state.data.Bat_V(end)==25.2 && state.data.SolarPower_W(end)==35.125);
    assert(strcmp(state.receiver.Protocol,'MAVLink 2 MPPT'));
    assert(contains(state.receiver.Source,sprintf(':%d',sender1.LocalPort)));
    if cycle==1 && nargin>0
        app.Visible='on'; waitTicks(.6);
        exportapp(app,fullfile(previewDir,'ui_udp_1400.png'));
        app.Position(3:4)=[1200 720]; waitTicks(.6);
        exportapp(app,fullfile(previewDir,'ui_udp_1200.png'));
        mode.Value='实时串口'; mode.ValueChangedFcn(mode,[]); waitTicks(.6);
        exportapp(app,fullfile(previewDir,'ui_serial_1200.png'));
        mode.Value='实时UDP'; mode.ValueChangedFcn(mode,[]);
        app.Position(3:4)=[1400 800]; app.Visible='off';
        % Mode changes intentionally start a new session; reconnect for assertions.
        listen.ButtonPushedFcn(listen,[]); drawnow;
        reception=timerfindall('Name','MPPT byte reception');
        state=snapshot(reception); created(state.logPath)=true; newLogs{end}=state.logPath;
        write(sender1,bytes,'uint8','127.0.0.1',chosenPort); waitTicks(.5);
    end
    write(sender1,bytes,'uint8','127.0.0.1',chosenPort); waitTicks(0.3);
    state=snapshot(reception); assert(state.validCount==1 && state.receiveCount==1);
    if cycle==1
        % Exercise idle maintenance through the actual GUI timer.
        partial=unfinishedFrame();
        write(sender1,partial,'uint8','127.0.0.1',chosenPort); waitTicks(3.3);
        state=snapshot(reception); assert(state.validCount==1 && state.receiver.Stats.Timeouts==1);
        labels=findall(app,'Type','uilabel');
        assert(any(contains(string({labels.Text}),'遥测超时')));
    end
    disconnect.ButtonPushedFcn(disconnect,[]); drawnow;
    assert(isempty(timerfindall('Name','MPPT byte reception')));
    probe=udpport('datagram','IPV4','LocalHost','0.0.0.0','LocalPort',chosenPort); delete(probe);
    fid=fopen(newLogs{end},'rb'); logged=fread(fid,Inf,'*uint8').'; fclose(fid);
    assert(isequal(logged,raw)); % exactly one decoded line; no MAVLink bytes
    [~,report]=mppt.loadHistoryFile(newLogs{end}); assert(report.parsedCount==1);
    pause(1.1); % avoid reusing the same second-resolution logfile in this test
end

% Close while actively listening, and verify that port and timer are released.
listen.ButtonPushedFcn(listen,[]); drawnow;
reception=timerfindall('Name','MPPT byte reception'); state=snapshot(reception);
newLogs{end+1}=state.logPath;
created(state.logPath)=true;
close(app); drawnow;
assert(isempty(timerfindall('Name','MPPT byte reception')));
probe=udpport('datagram','IPV4','LocalHost','0.0.0.0','LocalPort',chosenPort); delete(probe);

assert(numel(timerfindall)==numel(beforeTimers));
results=struct('udpConnectDisconnectCycles',3,'decodedSamplesPerCycle',1, ...
    'endpointIsolation',true,'logByteEquality',true,'portReleasedOnClose',true, ...
    'timerCountRestored',true);
disp(results);
end
function finish(app,sender1,sender2,created,prior)
if isvalid(app), close(app); end
delete(sender1); delete(sender2);
for path=created.keys
    if ~any(strcmp(prior,path{1})) && isfile(path{1}), delete(path{1}); end
end
end
function state=snapshot(t)
workspace=functions(t.TimerFcn).workspace;
state=workspace{1}.state;
end
function waitTicks(seconds)
clock=tic;
while toc(clock)<seconds, pause(0.05); drawnow; end
end
function bytes=unfinishedFrame()
prefix=uint8('# {"Bat_V":25,"Note":"'); suffix=uint8(sprintf('"}\n'));
raw=[prefix,uint8(repmat('x',1,140-numel(prefix)-numel(suffix))),suffix];
p=[uint8('MPPT'),uint8([1 24 0 2]),encodeLE(99,4),encodeLE(140,2), ...
    encodeLE(0,2),encodeLE(mppt.crc32(raw),4),encodeLE(1235567,4),raw(1:104)];
body=[uint8([0 128 0 0 128]),p];
header=uint8([253 numel(body) 0 0 0 1 158 129 1 0]);
bytes=[header,body,encodeLE(mppt.mavlinkCRC([header(2:end),body,uint8(147)]),2)];
end
function bytes=encodeLE(value,n)
value=uint32(value); bytes=zeros(1,n,'uint8');
for k=1:n, bytes(k)=uint8(bitand(bitshift(value,-8*(k-1)),uint32(255))); end
end
