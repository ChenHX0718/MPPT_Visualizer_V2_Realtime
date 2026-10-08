function results=run_replay_gui_tests()
%RUN_REPLAY_GUI_TESTS Run the real Replay callbacks/timer with a scripted chooser.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(root));
folder=tempname; mkdir(folder); file=fullfile(folder,'replay.log');
fid=fopen(file,'w','n','UTF-8');
for t=0:2
    fprintf(fid,'# {"Uptime_s":%d,"Bat_V":25,"Solar_V":40,"Solar_A":-2}\n',t);
end
fprintf(fid,'startup message\n'); fclose(fid);
fid=fopen(fullfile(folder,'uigetfile.m'),'w');
fprintf(fid,['function [name,folder]=uigetfile(varargin)\n' ...
    '[folder,base,ext]=fileparts(getenv(''MPPT_TEST_REPLAY_PATH''));\nname=[base,ext];\nend\n']);
fclose(fid);
oldEnv=getenv('MPPT_TEST_REPLAY_PATH'); setenv('MPPT_TEST_REPLAY_PATH',file);
oldPath=path; addpath(folder,'-begin');
app=MPPT_Visualizer(); app.Visible='off'; before=timerfindall;
cleanup=onCleanup(@()finish(app,folder,oldEnv,oldPath)); %#ok<NASGU>
buttons=findall(app,'Type','uibutton'); selector=buttons(strcmp({buttons.Text},'选择日志'));
selector.ButtonPushedFcn(selector,[]);
speed=findall(app,'Type','uidropdown'); speed=speed(arrayfun(@(h)any(strcmp(h.Items,'10x')),speed));
speed.Value='10x'; speed.ValueChangedFcn(speed,[]);
startButton=buttons(strcmp({buttons.Text},'开始')); stopButton=buttons(strcmp({buttons.Text},'停止'));
for cycle=1:3
    startButton.ButtonPushedFcn(startButton,[]); waitTicks(1.2);
    state=snapshot(startButton.ButtonPushedFcn);
    assert(state.validCount==3 && state.invalidCount==1 && state.buffer.acceptedCount==3);
    assert(isequal(state.data.Time_s,[0;1;2]) && isempty(state.replayTimer) && state.replayFID==-1);
    assert(abs(state.data.Energy_Wh(end)-160/3600)<1e-12);
end
startButton.ButtonPushedFcn(startButton,[]); stopButton.ButtonPushedFcn(stopButton,[]);
state=snapshot(stopButton.ButtonPushedFcn); assert(isempty(state.replayTimer) && state.replayFID==-1);
startButton.ButtonPushedFcn(startButton,[]); close(app); drawnow;
assert(numel(timerfindall)==numel(before));
results=struct('replayCycles',3,'validSamplesPerCycle',3,'skippedLines',1, ...
    'Wh',160/3600,'stopAndCloseReleasedTimer',true); disp(results);
end
function state=snapshot(callback)
w=functions(callback).workspace; state=w{1}.state;
end
function waitTicks(seconds)
clock=tic; while toc(clock)<seconds, pause(.05); drawnow; end
end
function finish(app,folder,oldEnv,oldPath)
if isvalid(app), close(app); end
path(oldPath); setenv('MPPT_TEST_REPLAY_PATH',oldEnv);
delete(fullfile(folder,'replay.log')); delete(fullfile(folder,'uigetfile.m')); rmdir(folder);
end
