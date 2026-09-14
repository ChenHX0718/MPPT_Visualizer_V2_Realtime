function app = MPPT_Visualizer()
%MPPT_VISUALIZER MPPT 历史 / 实时串口 / Replay 共用可视化仪表盘。
%   运行 MPPT_Visualizer 后，可在顶部选择三种模式：
%   历史文件、实时串口、模拟实时。实时串口只读取，不向设备发送命令。

projectRoot = fileparts(mfilename('fullpath'));
addpath(genpath(projectRoot));
fontName = localPickFont();
colors = localColors();

fig = uifigure( ...
    'Name', 'MPPT 数据监控 / 历史与实时', ...
    'Color', colors.background, ...
    'Position', [55 45 1540 930], ...
    'AutoResizeChildren', 'on', ...
    'CloseRequestFcn', @onClose);

state = struct();
state.mode = '历史文件';
state.lastFile = '';
state.serial = [];
state.serialPort = '';
state.serialBaud = 115200;
state.logFID = -1;
state.logPath = '';
state.replayFID = -1;
state.replayFile = '';
state.replayTimer = [];
state.replayFactor = 1;
state.buffer = mppt.realtimeBuffer('create', 500);
state.validCount = 0;
state.invalidCount = 0;
state.totalCount = 0;
state.lastValidDateTime = NaT;
state.data = [];
state.report = [];
state.closing = false;

rootGrid = uigridlayout(fig, [3 1]);
rootGrid.RowHeight = {128, '1x', 24};
rootGrid.ColumnWidth = {'1x'};
rootGrid.Padding = [22 16 22 10];
rootGrid.RowSpacing = 12;
rootGrid.BackgroundColor = colors.background;

header = uipanel(rootGrid, 'BorderType', 'none', 'BackgroundColor', colors.background);
header.Layout.Row = 1;
headerGrid = uigridlayout(header, [3 1]);
headerGrid.RowHeight = {42, 48, 24};
headerGrid.Padding = [0 0 0 0];
headerGrid.RowSpacing = 5;
headerGrid.BackgroundColor = colors.background;

topGrid = uigridlayout(headerGrid, [1 4]);
topGrid.Layout.Row = 1;
topGrid.ColumnWidth = {'1x', 230, 125, 175};
topGrid.Padding = [0 0 0 0];
topGrid.ColumnSpacing = 12;
topGrid.BackgroundColor = colors.background;

titleLabel = uilabel(topGrid, 'Text', 'MPPT 数据监控 / 历史与实时', ...
    'FontName', fontName, 'FontSize', 22, 'FontWeight', 'bold', ...
    'FontColor', colors.ink, 'HorizontalAlignment', 'left');
titleLabel.Layout.Column = 1;

modeHint = uilabel(topGrid, 'Text', '工作模式', 'FontName', fontName, ...
    'FontSize', 12, 'FontWeight', 'bold', 'FontColor', colors.muted, ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'center');
modeHint.Layout.Column = 2;

modeDrop = uidropdown(topGrid, 'Items', {'历史文件', '实时串口', '模拟实时'}, ...
    'Value', '历史文件', 'FontName', fontName, 'FontSize', 12, ...
    'ValueChangedFcn', @onModeChanged);
modeDrop.Layout.Column = 3;

modeLabel = uilabel(topGrid, 'Text', '历史文件模式', 'FontName', fontName, ...
    'FontSize', 12, 'FontWeight', 'bold', 'FontColor', colors.primary, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
    'BackgroundColor', colors.primarySoft);
modeLabel.Layout.Column = 4;

controlGrid = uigridlayout(headerGrid, [1 3]);
controlGrid.Layout.Row = 2;
controlGrid.ColumnWidth = {'1x', '2.15x', '1.75x'};
controlGrid.Padding = [0 0 0 0];
controlGrid.ColumnSpacing = 10;
controlGrid.BackgroundColor = colors.background;

historyPanel = uipanel(controlGrid, 'Title', '历史文件', 'FontName', fontName, ...
    'FontSize', 10, 'ForegroundColor', colors.muted, 'BorderColor', colors.border, ...
    'BackgroundColor', colors.surface);
historyPanel.Layout.Column = 1;
historyGrid = uigridlayout(historyPanel, [1 2]);
historyGrid.ColumnWidth = {'1.2x', '1x'};
historyGrid.Padding = [6 2 6 4];
historyGrid.ColumnSpacing = 6;
historyGrid.BackgroundColor = colors.surface;
openButton = uibutton(historyGrid, 'push', 'Text', '打开文件', ...
    'FontName', fontName, 'FontSize', 11, 'FontWeight', 'bold', ...
    'FontColor', [1 1 1], 'BackgroundColor', colors.primary, ...
    'ButtonPushedFcn', @openFile);
reloadButton = uibutton(historyGrid, 'push', 'Text', '重新载入', ...
    'FontName', fontName, 'FontSize', 11, 'FontColor', colors.ink, ...
    'BackgroundColor', colors.surfaceAlt, 'ButtonPushedFcn', @reloadFile);

serialPanel = uipanel(controlGrid, 'Title', '实时串口（只读）', 'FontName', fontName, ...
    'FontSize', 10, 'ForegroundColor', colors.muted, 'BorderColor', colors.border, ...
    'BackgroundColor', colors.surface);
serialPanel.Layout.Column = 2;
serialGrid = uigridlayout(serialPanel, [1 7]);
serialGrid.ColumnWidth = {42, '1.15x', 58, 78, 58, 58, 70};
serialGrid.Padding = [6 2 6 4];
serialGrid.ColumnSpacing = 5;
serialGrid.BackgroundColor = colors.surface;
uilabel(serialGrid, 'Text', 'COM', 'FontName', fontName, 'FontSize', 10, ...
    'FontColor', colors.muted, 'HorizontalAlignment', 'center');
portDrop = uidropdown(serialGrid, 'Items', {'正在检测…'}, 'FontName', fontName, ...
    'FontSize', 10, 'Value', '正在检测…');
refreshButton = uibutton(serialGrid, 'push', 'Text', '刷新', 'FontName', fontName, ...
    'FontSize', 10, 'ButtonPushedFcn', @refreshPorts);
baudDrop = uidropdown(serialGrid, 'Items', {'9600', '19200', '38400', '57600', '115200', '230400'}, ...
    'Value', '115200', 'FontName', fontName, 'FontSize', 10);
connectButton = uibutton(serialGrid, 'push', 'Text', '连接', 'FontName', fontName, ...
    'FontSize', 10, 'FontWeight', 'bold', 'FontColor', [1 1 1], ...
    'BackgroundColor', colors.green, 'ButtonPushedFcn', @connectSerial);
disconnectButton = uibutton(serialGrid, 'push', 'Text', '断开', 'FontName', fontName, ...
    'FontSize', 10, 'BackgroundColor', colors.surfaceAlt, 'ButtonPushedFcn', @disconnectSerial);
clearButton = uibutton(serialGrid, 'push', 'Text', '清空曲线', 'FontName', fontName, ...
    'FontSize', 10, 'BackgroundColor', colors.surfaceAlt, 'ButtonPushedFcn', @clearRealtime);

replayPanel = uipanel(controlGrid, 'Title', '模拟实时 / Replay', 'FontName', fontName, ...
    'FontSize', 10, 'ForegroundColor', colors.muted, 'BorderColor', colors.border, ...
    'BackgroundColor', colors.surface);
replayPanel.Layout.Column = 3;
replayGrid = uigridlayout(replayPanel, [1 5]);
replayGrid.ColumnWidth = {42, '1.35x', 62, 58, 58};
replayGrid.Padding = [6 2 6 4];
replayGrid.ColumnSpacing = 5;
replayGrid.BackgroundColor = colors.surface;
uilabel(replayGrid, 'Text', '文件', 'FontName', fontName, 'FontSize', 10, ...
    'FontColor', colors.muted, 'HorizontalAlignment', 'center');
replayFileButton = uibutton(replayGrid, 'push', 'Text', '选择日志', ...
    'FontName', fontName, 'FontSize', 10, 'ButtonPushedFcn', @selectReplayFile);
speedDrop = uidropdown(replayGrid, 'Items', {'1x', '5x', '10x'}, 'Value', '1x', ...
    'FontName', fontName, 'FontSize', 10, 'ValueChangedFcn', @onReplaySpeedChanged);
replayStartButton = uibutton(replayGrid, 'push', 'Text', '开始', 'FontName', fontName, ...
    'FontSize', 10, 'FontWeight', 'bold', 'FontColor', [1 1 1], ...
    'BackgroundColor', colors.primary, 'ButtonPushedFcn', @startReplay);
replayStopButton = uibutton(replayGrid, 'push', 'Text', '停止', 'FontName', fontName, ...
    'FontSize', 10, 'BackgroundColor', colors.surfaceAlt, 'ButtonPushedFcn', @stopReplay);

headerStatusGrid = uigridlayout(headerGrid, [1 3]);
headerStatusGrid.Layout.Row = 3;
headerStatusGrid.ColumnWidth = {'1.3x', '1.4x', '1x'};
headerStatusGrid.Padding = [0 0 0 0];
headerStatusGrid.ColumnSpacing = 12;
headerStatusGrid.BackgroundColor = colors.background;
connectionLabel = uilabel(headerStatusGrid, 'Text', '未连接', 'FontName', fontName, ...
    'FontSize', 11, 'FontColor', colors.muted, 'HorizontalAlignment', 'left');
fileLabel = uilabel(headerStatusGrid, 'Text', '文件：尚未载入', 'FontName', fontName, ...
    'FontSize', 11, 'FontColor', colors.muted, 'HorizontalAlignment', 'left');
reportLabel = uilabel(headerStatusGrid, 'Text', '等待数据', 'FontName', fontName, ...
    'FontSize', 11, 'FontColor', colors.muted, 'HorizontalAlignment', 'right');

content = uigridlayout(rootGrid, [2 3]);
content.Layout.Row = 2;
content.ColumnWidth = {286, '1x', '1x'};
content.RowHeight = {'1x', '1.03x'};
content.Padding = [0 0 0 0];
content.RowSpacing = 14;
content.ColumnSpacing = 14;
content.BackgroundColor = colors.background;

statusPanel = uipanel(content, 'BorderType', 'line', 'BorderColor', colors.border, ...
    'BackgroundColor', colors.surface);
statusPanel.Layout.Row = [1 2];
statusPanel.Layout.Column = 1;
statusGrid = uigridlayout(statusPanel, [10 1]);
statusGrid.RowHeight = {30, 30, 30, 30, 30, 30, 30, 30, 30, '1x'};
statusGrid.Padding = [14 12 14 12];
statusGrid.RowSpacing = 7;
statusGrid.BackgroundColor = colors.surface;
statusHeading = uilabel(statusGrid, 'Text', '实时状态 / 最后有效采样', ...
    'FontName', fontName, 'FontSize', 14, 'FontWeight', 'bold', ...
    'FontColor', colors.ink, 'HorizontalAlignment', 'left');
statusHeading.Layout.Row = 1;
[batteryValue, batteryUnit] = localMakeMetricRow(statusGrid, 2, 'Battery Voltage');
[solarVoltageValue, solarVoltageUnit] = localMakeMetricRow(statusGrid, 3, 'Solar Voltage');
[solarCurrentValue, solarCurrentUnit] = localMakeMetricRow(statusGrid, 4, 'Solar Current');
[solarPowerValue, solarPowerUnit] = localMakeMetricRow(statusGrid, 5, 'Solar Power');
[socValue, socUnit] = localMakeMetricRow(statusGrid, 6, 'SOC');
[dcdcValue, dcdcUnit] = localMakeMetricRow(statusGrid, 7, 'DCDC State');
[chgValue, chgUnit] = localMakeMetricRow(statusGrid, 8, 'Charge State');
[errorValue, errorUnit] = localMakeMetricRow(statusGrid, 9, 'Error Flags');
statusDetail = uilabel(statusGrid, 'Text', '等待有效数据…', 'FontName', fontName, ...
    'FontSize', 10, 'FontColor', colors.muted, 'HorizontalAlignment', 'left', ...
    'VerticalAlignment', 'top', 'WordWrap', 'on');
statusDetail.Layout.Row = 10;

[batteryAxes, batteryTitle] = localMakeChartPanel(content, '电池电压变化', ...
    '记录时间 / s', '电池电压 / V', fontName, colors, 1, 2);
[powerAxes, powerTitle] = localMakeChartPanel(content, '太阳能功率变化', ...
    '记录时间 / s', '太阳能功率 / W', fontName, colors, 1, 3);
[energyAxes, energyTitle] = localMakeChartPanel(content, '太阳能累计输出能量', ...
    '记录时间 / s', '累计太阳能输出能量 / Wh', fontName, colors, 2, [2 3]);

footer = uilabel(rootGrid, 'Text', ...
    '历史文件  ·  实时串口只读  ·  原始串口行保存到 realtime_logs  ·  关闭窗口会释放串口', ...
    'FontName', fontName, 'FontSize', 10, 'FontColor', colors.muted, ...
    'HorizontalAlignment', 'left');
footer.Layout.Row = 3;

lineHandles = struct('battery', [], 'power', [], 'energy', []);
localRefreshPorts();
localUpdateControlVisibility();

% 启动时沿用 V1 的便利行为：若父目录有样例历史文件则展示它。
sampleDir = fileparts(projectRoot);
sampleFiles = dir(fullfile(sampleDir, '*.txt'));
if isempty(sampleFiles)
    sampleFiles = dir(fullfile(sampleDir, '*.log'));
end
if ~isempty(sampleFiles)
    samplePath = fullfile(sampleDir, sampleFiles(1).name);
    if isfile(samplePath)
        localLoadHistory(samplePath);
    end
end

if nargout > 0
    app = fig;
end

    function onModeChanged(~, ~)
        newMode = modeDrop.Value;
        if strcmp(newMode, state.mode)
            return;
        end
        localStopReplay();
        localDisconnect();
        state.mode = newMode;
        state.buffer = mppt.realtimeBuffer('create', 500);
        state.validCount = 0;
        state.invalidCount = 0;
        state.totalCount = 0;
        state.lastValidDateTime = NaT;
        modeLabel.Text = [newMode, '模式'];
        localUpdateControlVisibility();
        if strcmp(newMode, '历史文件')
            if isfile(state.lastFile)
                localLoadHistory(state.lastFile);
            else
                localClearAxes();
                localUpdateStatusFromData([]);
            end
        else
            localClearAxes();
            localUpdateStatusFromData([]);
            reportLabel.Text = '等待实时数据';
        end
    end

    function openFile(~, ~)
        startDir = sampleDir;
        if isfile(state.lastFile)
            startDir = fileparts(state.lastFile);
        end
        [fileName, filePath] = uigetfile( ...
            {'*.txt;*.log', '历史日志 (*.txt, *.log)'; '*.*', '所有文件 (*.*)'}, ...
            '打开历史文件', startDir);
        if isequal(fileName, 0)
            return;
        end
        localLoadHistory(fullfile(filePath, fileName));
    end

    function reloadFile(~, ~)
        if isfile(state.lastFile)
            localLoadHistory(state.lastFile);
        else
            openFile(openButton, []);
        end
    end

    function localLoadHistory(filePath)
        try
            [data, report] = mppt.loadHistoryFile(filePath);
            state.lastFile = char(filePath);
            state.data = data;
            state.report = report;
            if ~strcmp(modeDrop.Value, '历史文件')
                modeDrop.Value = '历史文件';
                state.mode = '历史文件';
                modeLabel.Text = '历史文件模式';
                localStopReplay();
                localDisconnect();
                localUpdateControlVisibility();
            end
            [~, shortName, ext] = fileparts(filePath);
            fileLabel.Text = ['文件：', shortName, ext];
            fileLabel.Tooltip = filePath;
            reportLabel.Text = sprintf('有效 %d 行  ·  共 %d 行  ·  跳过 %d 行', ...
                report.parsedCount, report.totalLines, report.skippedCount);
            localRenderHistory(data);
            localUpdateStatusFromData(data);
        catch ME
            if isvalid(fig)
                uialert(fig, sprintf('无法载入历史文件。\n\n%s', ME.message), ...
                    '历史文件读取失败', 'Icon', 'error');
            end
        end
    end

    function refreshPorts(~, ~)
        localRefreshPorts();
    end

    function localRefreshPorts()
        try
            ports = serialportlist('available');
        catch
            try
                ports = serialportlist;
            catch
                ports = string.empty(1, 0);
            end
        end
        if ischar(ports)
            ports = string(cellstr(ports));
        end
        ports = string(ports(:).');
        if isempty(ports)
            portDrop.Items = {'(无可用串口)'};
            portDrop.Value = '(无可用串口)';
        else
            portDrop.Items = cellstr(ports);
            if ~any(strcmp(portDrop.Items, portDrop.Value))
                portDrop.Value = portDrop.Items{1};
            end
        end
    end

    function connectSerial(~, ~)
        if ~strcmp(state.mode, '实时串口')
            modeDrop.Value = '实时串口';
            onModeChanged(modeDrop, []);
        end
        portName = char(portDrop.Value);
        if isempty(portName) || startsWith(portName, '(')
            localShowError('没有可用 COM 口', '请点击“刷新”确认 MPPT USB 串口是否已经出现。');
            return;
        end
        baud = str2double(baudDrop.Value);
        localDisconnect();
        localResetRealtime();
        try
            candidate = serialport(portName, baud, 'Timeout', 1);
            configureTerminator(candidate, 'LF');
            flush(candidate);
            state.serial = candidate;
            state.serialPort = portName;
            state.serialBaud = baud;
            logDir = fullfile(projectRoot, 'realtime_logs');
            if ~isfolder(logDir)
                mkdir(logDir);
            end
            logName = ['MPPT_', datestr(now, 'yyyymmdd_HHMMSS'), '.log'];
            state.logPath = fullfile(logDir, logName);
            state.logFID = fopen(state.logPath, 'a', 'n', 'UTF-8');
            if state.logFID < 0
                error('MPPT:LogOpen', '无法创建实时日志：%s', state.logPath);
            end
            configureCallback(candidate, 'terminator', @onSerialLine);
            connectionLabel.Text = sprintf('已连接 %s @ %d', portName, baud);
            connectionLabel.FontColor = colors.green;
            statusDetail.Text = ['正在接收；日志：', state.logPath];
            reportLabel.Text = '等待串口数据…';
        catch ME
            if ~isempty(state.serial)
                localDisconnect();
            elseif exist('candidate', 'var')
                try
                    configureCallback(candidate, 'off');
                catch
                end
            end
            extra = '';
            lowerMessage = lower(ME.message);
            if contains(lowerMessage, 'busy') || contains(lowerMessage, 'access') || ...
                    contains(lowerMessage, 'in use')
                extra = sprintf('\n\n串口可能正在被串口助手或其他程序占用，请关闭其他串口软件后重试。');
            end
            localShowError('串口连接失败', [ME.message, extra]);
        end
    end

    function disconnectSerial(~, ~)
        localDisconnect();
    end

    function localDisconnect()
        if ~isempty(state.serial)
            try
                configureCallback(state.serial, 'off');
            catch
            end
            try
                flush(state.serial);
            catch
            end
            state.serial = [];
        end
        if isnumeric(state.logFID) && state.logFID >= 0
            try
                fclose(state.logFID);
            catch
            end
            state.logFID = -1;
        end
        if strcmp(state.mode, '实时串口') && ~state.closing
            connectionLabel.Text = '未连接';
            connectionLabel.FontColor = colors.muted;
            if state.validCount > 0
                reportLabel.Text = sprintf('串口已断开  ·  有效 %d  ·  坏数据 %d', ...
                    state.validCount, state.invalidCount);
            end
        end
    end

    function onSerialLine(src, ~)
        if state.closing || isempty(state.serial)
            return;
        end
        try
            rawLine = readline(src);
            localConsumeLine(char(rawLine), true);
        catch ME
            if ~state.closing
                connectionLabel.Text = '串口读取中断';
                connectionLabel.FontColor = colors.red;
                localShowError('串口读取中断', ME.message);
                localDisconnect();
            end
        end
    end

    function localConsumeLine(rawLine, isSerialLine)
        state.totalCount = state.totalCount + 1;
        if isSerialLine && isnumeric(state.logFID) && state.logFID >= 0
            fprintf(state.logFID, '%s\n', rawLine);
            fflush(state.logFID);
        end
        [record, isValid, info] = mppt.parseTelemetryLine(rawLine);
        if ~isValid
            state.invalidCount = state.invalidCount + 1;
            if strcmp(state.mode, '实时串口')
                reportLabel.Text = sprintf('已接收 %d 行  ·  有效 %d  ·  坏数据 %d（%s）', ...
                    state.totalCount, state.validCount, state.invalidCount, info.reason);
            else
                reportLabel.Text = sprintf('Replay 读取 %d 行  ·  有效 %d  ·  跳过 %d', ...
                    state.totalCount, state.validCount, state.invalidCount);
            end
            return;
        end
        [state.buffer, data] = mppt.realtimeBuffer('append', state.buffer, record);
        state.validCount = state.validCount + 1;
        state.lastValidDateTime = datetime('now');
        localRenderRealtime(data);
        localUpdateStatusFromData(data);
        if strcmp(state.mode, '实时串口')
            connectionLabel.Text = sprintf('正在接收 %s @ %d', state.serialPort, state.serialBaud);
            connectionLabel.FontColor = colors.green;
            reportLabel.Text = sprintf('实时有效 %d  ·  坏数据 %d  ·  最近 %s', ...
                state.validCount, state.invalidCount, datestr(state.lastValidDateTime, 'HH:MM:SS'));
        else
            reportLabel.Text = sprintf('Replay 有效 %d  ·  跳过 %d  ·  最近 %s', ...
                state.validCount, state.invalidCount, datestr(state.lastValidDateTime, 'HH:MM:SS'));
        end
        drawnow limitrate;
    end

    function clearRealtime(~, ~)
        localResetRealtime();
    end

    function localResetRealtime()
        state.buffer = mppt.realtimeBuffer('create', 500);
        state.validCount = 0;
        state.invalidCount = 0;
        state.totalCount = 0;
        state.lastValidDateTime = NaT;
        localClearAxes();
        localUpdateStatusFromData([]);
        reportLabel.Text = '实时曲线已清空';
    end

    function selectReplayFile(~, ~)
        startDir = sampleDir;
        if isfile(state.replayFile)
            startDir = fileparts(state.replayFile);
        end
        [fileName, filePath] = uigetfile( ...
            {'*.txt;*.log', 'MPPT 日志 (*.txt, *.log)'; '*.*', '所有文件 (*.*)'}, ...
            '选择 Replay 日志', startDir);
        if isequal(fileName, 0)
            return;
        end
        state.replayFile = fullfile(filePath, fileName);
        fileLabel.Text = ['Replay：', fileName];
        fileLabel.Tooltip = state.replayFile;
    end

    function onReplaySpeedChanged(~, ~)
        state.replayFactor = str2double(erase(speedDrop.Value, 'x'));
        if isempty(state.replayTimer) || ~isvalid(state.replayTimer)
            return;
        end
        stop(state.replayTimer);
        state.replayTimer.Period = max(0.03, 1 / state.replayFactor);
        start(state.replayTimer);
    end

    function startReplay(~, ~)
        if ~strcmp(state.mode, '模拟实时')
            modeDrop.Value = '模拟实时';
            onModeChanged(modeDrop, []);
        end
        if ~isfile(state.replayFile)
            selectReplayFile(replayFileButton, []);
            if ~isfile(state.replayFile)
                return;
            end
        end
        localStopReplay();
        localResetRealtime();
        state.replayFID = fopen(state.replayFile, 'r', 'n', 'UTF-8');
        if state.replayFID < 0
            localShowError('Replay 文件打开失败', state.replayFile);
            return;
        end
        state.replayFactor = str2double(erase(speedDrop.Value, 'x'));
        state.replayTimer = timer('ExecutionMode', 'fixedRate', ...
            'Period', max(0.03, 1 / state.replayFactor), ...
            'BusyMode', 'drop', 'TimerFcn', @onReplayTick, ...
            'ErrorFcn', @onReplayTimerError);
        start(state.replayTimer);
        connectionLabel.Text = sprintf('Replay 运行中 · %s', speedDrop.Value);
        connectionLabel.FontColor = colors.primary;
        fileLabel.Text = ['Replay：', getFileName(state.replayFile)];
        fileLabel.Tooltip = state.replayFile;
    end

    function stopReplay(~, ~)
        localStopReplay();
    end

    function localStopReplay()
        if ~isempty(state.replayTimer)
            try
                stop(state.replayTimer);
            catch
            end
            try
                delete(state.replayTimer);
            catch
            end
            state.replayTimer = [];
        end
        if isnumeric(state.replayFID) && state.replayFID >= 0
            try
                fclose(state.replayFID);
            catch
            end
            state.replayFID = -1;
        end
        if strcmp(state.mode, '模拟实时') && ~state.closing
            connectionLabel.Text = 'Replay 已停止';
            connectionLabel.FontColor = colors.muted;
        end
    end

    function onReplayTick(~, ~)
        if state.replayFID < 0 || state.closing
            return;
        end
        rawLine = fgetl(state.replayFID);
        if ~ischar(rawLine)
            localStopReplay();
            connectionLabel.Text = 'Replay 已完成';
            connectionLabel.FontColor = colors.green;
            return;
        end
        localConsumeLine(rawLine, false);
    end

    function onReplayTimerError(~, evt)
        if state.closing
            return;
        end
        localStopReplay();
        localShowError('Replay 停止', evt.Data.Message);
    end

    function localRenderHistory(data)
        localClearAxes();
        valid = isfinite(data.Time_s) & isfinite(data.Bat_V);
        if any(valid)
            localPlotAndFit(batteryAxes, data.Time_s(valid), data.Bat_V(valid), colors.blue);
        else
            localEmptyAxes(batteryAxes, '此文件无 Bat_V 数据');
        end
        valid = isfinite(data.Time_s) & isfinite(data.SolarPower_W);
        if any(valid)
            localPlotAndFit(powerAxes, data.Time_s(valid), data.SolarPower_W(valid), colors.orange);
            if isfinite(data.metrics.indexAtPmax)
                idx = data.metrics.indexAtPmax;
                hold(powerAxes, 'on');
                plot(powerAxes, data.Time_s(idx), data.SolarPower_W(idx), 'o', ...
                    'MarkerSize', 8, 'LineWidth', 1.4, 'MarkerEdgeColor', colors.orange, ...
                    'MarkerFaceColor', colors.surface);
                hold(powerAxes, 'off');
            end
        else
            localEmptyAxes(powerAxes, '此文件无有效 Solar_V / Solar_A 数据');
        end
        valid = isfinite(data.Time_s) & isfinite(data.Energy_Wh);
        if any(valid)
            localPlotAndFit(energyAxes, data.Time_s(valid), data.Energy_Wh(valid), colors.green);
        else
            localEmptyAxes(energyAxes, '此文件无可用能量数据');
        end
        if data.energyIsComputed
            energyTitle.Text = '太阳能累计输出能量 · 计算值';
        else
            energyTitle.Text = '太阳能累计输出能量 · 原始字段';
        end
        batteryTitle.Text = '电池电压变化';
        powerTitle.Text = '太阳能功率变化';
    end

    function localRenderRealtime(data)
        localEnsureRealtimeLines();
        localSetLine(lineHandles.battery, data.Time_s, data.Bat_V);
        localSetLine(lineHandles.power, data.Time_s, data.SolarPower_W);
        localSetLine(lineHandles.energy, data.Time_s, data.Energy_Wh);
        localRealtimeLimits(batteryAxes, data.Time_s, data.Bat_V);
        localRealtimeLimits(powerAxes, data.Time_s, data.SolarPower_W);
        localRealtimeLimits(energyAxes, data.Time_s, data.Energy_Wh);
        energyTitle.Text = '太阳能累计输出能量 · 实时';
        batteryTitle.Text = '电池电压变化 · 最近 500 点';
        powerTitle.Text = '太阳能功率变化 · 最近 500 点';
    end

    function localEnsureRealtimeLines()
        if isempty(lineHandles.battery) || ~isvalid(lineHandles.battery)
            lineHandles.battery = plot(batteryAxes, NaN, NaN, '-', ...
                'Color', colors.blue, 'LineWidth', 1.8);
        end
        if isempty(lineHandles.power) || ~isvalid(lineHandles.power)
            lineHandles.power = plot(powerAxes, NaN, NaN, '-', ...
                'Color', colors.orange, 'LineWidth', 1.8);
        end
        if isempty(lineHandles.energy) || ~isvalid(lineHandles.energy)
            lineHandles.energy = plot(energyAxes, NaN, NaN, '-', ...
                'Color', colors.green, 'LineWidth', 1.9);
        end
    end

    function localSetLine(lineHandle, x, y)
        valid = isfinite(x) & isfinite(y);
        if any(valid)
            lineHandle.XData = x(valid);
            lineHandle.YData = y(valid);
        else
            lineHandle.XData = NaN;
            lineHandle.YData = NaN;
        end
    end

    function localRealtimeLimits(ax, x, y)
        valid = isfinite(x) & isfinite(y);
        if ~any(valid)
            return;
        end
        x = x(valid);
        y = y(valid);
        if min(x) == max(x)
            dx = max(1, abs(x(1)) * 0.05);
        else
            dx = max(1, 0.025 * (max(x) - min(x)));
        end
        ax.XLim = [min(x)-dx, max(x)+dx];
        ymin = min(y);
        ymax = max(y);
        if ymin == ymax
            dy = max(0.1, abs(ymin) * 0.05);
        else
            dy = max(0.1, 0.08 * (ymax-ymin));
        end
        ax.YLim = [ymin-dy, ymax+dy];
    end

    function localClearAxes()
        cla(batteryAxes, 'reset');
        cla(powerAxes, 'reset');
        cla(energyAxes, 'reset');
        localStyleAxes(batteryAxes, '记录时间 / s', '电池电压 / V');
        localStyleAxes(powerAxes, '记录时间 / s', '太阳能功率 / W');
        localStyleAxes(energyAxes, '记录时间 / s', '累计太阳能输出能量 / Wh');
        lineHandles = struct('battery', [], 'power', [], 'energy', []);
        batteryTitle.Text = '电池电压变化';
        powerTitle.Text = '太阳能功率变化';
        energyTitle.Text = '太阳能累计输出能量';
    end

    function localUpdateStatusFromData(data)
        if isempty(data) || ~isstruct(data) || ~isfield(data, 'metrics') || isempty(data.metrics)
            batteryValue.Text = '—'; batteryUnit.Text = 'V';
            solarVoltageValue.Text = '—'; solarVoltageUnit.Text = 'V';
            solarCurrentValue.Text = '—'; solarCurrentUnit.Text = 'A';
            solarPowerValue.Text = '—'; solarPowerUnit.Text = 'W';
            socValue.Text = '—'; socUnit.Text = '%';
            dcdcValue.Text = '—'; dcdcUnit.Text = '';
            chgValue.Text = '—'; chgUnit.Text = '';
            errorValue.Text = '—'; errorUnit.Text = '';
            statusDetail.Text = '等待有效数据…';
            statusPanel.BackgroundColor = colors.surface;
            return;
        end
        idx = data.metrics.lastIndex;
        batteryValue.Text = localNumber(localAt(data.Bat_V, idx), '%.2f'); batteryUnit.Text = 'V';
        solarVoltageValue.Text = localNumber(localAt(data.Solar_V, idx), '%.2f'); solarVoltageUnit.Text = 'V';
        solarCurrentValue.Text = localNumber(localAt(data.Solar_A_generation, idx), '%.2f'); solarCurrentUnit.Text = 'A';
        solarPowerValue.Text = localNumber(localAt(data.SolarPower_W, idx), '%.2f'); solarPowerUnit.Text = 'W';
        socValue.Text = localNumber(localAt(data.SOC_pct, idx), '%.1f'); socUnit.Text = '%';
        lastChg = localAt(data.ChgState, idx);
        lastDcdc = localAt(data.DCDCState, idx);
        lastError = localAt(data.ErrorFlags, idx);
        stateText = mppt.formatMPPTState(lastChg, lastDcdc, lastError);
        dcdcValue.Text = stateText.dcdcText; dcdcUnit.Text = '';
        chgValue.Text = stateText.chgText; chgUnit.Text = '';
        errorValue.Text = stateText.errorText; errorUnit.Text = '';
        if stateText.hasError
            statusPanel.BackgroundColor = [1.000 0.945 0.940];
            errorValue.FontColor = colors.red;
        else
            statusPanel.BackgroundColor = colors.surface;
            errorValue.FontColor = colors.ink;
        end
        detailParts = {['Pmax ', localNumber(data.metrics.Pmax_W, '%.2f'), ' W'], ...
            ['能量：', data.energySource], data.solarSignRule};
        if state.validCount > 0 && ~isnat(state.lastValidDateTime)
            detailParts{end+1} = ['最近有效：', datestr(state.lastValidDateTime, 'yyyy-mm-dd HH:MM:SS')];
        end
        statusDetail.Text = strjoin(detailParts, newline);
    end

    function localUpdateControlVisibility()
        currentMode = modeDrop.Value;
        historyPanel.Visible = strcmp(currentMode, '历史文件');
        serialPanel.Visible = strcmp(currentMode, '实时串口');
        replayPanel.Visible = strcmp(currentMode, '模拟实时');
        if strcmp(currentMode, '实时串口')
            modeLabel.Text = '实时串口模式';
        elseif strcmp(currentMode, '模拟实时')
            modeLabel.Text = 'Replay 模式';
        else
            modeLabel.Text = '历史文件模式';
        end
    end

    function localShowError(titleText, messageText)
        if isvalid(fig) && ~state.closing
            uialert(fig, messageText, titleText, 'Icon', 'error');
        end
    end

    function onClose(~, ~)
        state.closing = true;
        localStopReplay();
        localDisconnect();
        if isvalid(fig)
            delete(fig);
        end
    end
end

function [valueLabel, unitLabel] = localMakeMetricRow(parent, row, titleText)
grid = uigridlayout(parent, [1 2]);
grid.Layout.Row = row;
grid.ColumnWidth = {'1.2x', '1.4x'};
grid.Padding = [0 0 0 0];
grid.ColumnSpacing = 4;
grid.BackgroundColor = parent.BackgroundColor;
uilabel(grid, 'Text', titleText, 'FontName', 'Segoe UI', 'FontSize', 10, ...
    'FontColor', [0.360 0.425 0.515], 'HorizontalAlignment', 'left', ...
    'VerticalAlignment', 'center');
valueGrid = uigridlayout(grid, [1 2]);
valueGrid.Layout.Column = 2;
valueGrid.ColumnWidth = {'1x', 20};
valueGrid.Padding = [0 0 0 0];
valueGrid.ColumnSpacing = 2;
valueGrid.BackgroundColor = parent.BackgroundColor;
valueLabel = uilabel(valueGrid, 'Text', '—', 'FontName', 'Segoe UI', ...
    'FontSize', 14, 'FontWeight', 'bold', 'FontColor', [0.105 0.145 0.205], ...
    'HorizontalAlignment', 'right');
unitLabel = uilabel(valueGrid, 'Text', '', 'FontName', 'Segoe UI', 'FontSize', 10, ...
    'FontColor', [0.090 0.345 0.690], 'HorizontalAlignment', 'left');
end

function [ax, heading] = localMakeChartPanel(parent, titleText, xLabelText, yLabelText, fontName, colors, row, column)
panel = uipanel(parent, 'BorderType', 'line', 'BorderColor', colors.border, ...
    'BackgroundColor', colors.surface);
panel.Layout.Row = row;
panel.Layout.Column = column;
grid = uigridlayout(panel, [2 1]);
grid.RowHeight = {30, '1x'};
grid.Padding = [14 10 14 12];
grid.RowSpacing = 2;
grid.BackgroundColor = colors.surface;
heading = uilabel(grid, 'Text', titleText, 'FontName', fontName, ...
    'FontSize', 14, 'FontWeight', 'bold', 'FontColor', colors.ink, ...
    'HorizontalAlignment', 'left');
heading.Layout.Row = 1;
ax = uiaxes(grid);
ax.Layout.Row = 2;
localStyleAxes(ax, xLabelText, yLabelText);
end

function localStyleAxes(ax, xLabelText, yLabelText)
ax.FontName = 'Segoe UI';
ax.FontSize = 11;
ax.XColor = [0.265 0.315 0.390];
ax.YColor = [0.265 0.315 0.390];
ax.GridColor = [0.790 0.835 0.900];
ax.MinorGridColor = [0.790 0.835 0.900];
ax.GridAlpha = 0.38;
ax.MinorGridAlpha = 0.18;
ax.LineWidth = 0.8;
ax.Box = 'off';
ax.Color = [1 1 1];
xlabel(ax, xLabelText, 'FontName', 'Segoe UI', 'Color', ax.XColor);
ylabel(ax, yLabelText, 'FontName', 'Segoe UI', 'Color', ax.YColor);
ax.XGrid = 'on';
ax.YGrid = 'on';
end

function localPlotAndFit(ax, x, y, color)
plot(ax, x, y, '-', 'Color', color, 'LineWidth', 1.8);
if min(x) == max(x)
    dx = max(1, abs(x(1)) * 0.05);
else
    dx = max(1, 0.025 * (max(x) - min(x)));
end
ax.XLim = [min(x)-dx, max(x)+dx];
if min(y) == max(y)
    dy = max(0.1, abs(y(1)) * 0.05);
else
    dy = max(0.1, 0.08 * (max(y)-min(y)));
end
ax.YLim = [min(y)-dy, max(y)+dy];
end

function localEmptyAxes(ax, message)
ax.XLim = [0 1];
ax.YLim = [0 1];
ax.XTick = [];
ax.YTick = [];
text(ax, 0.5, 0.5, message, 'Units', 'normalized', 'FontName', 'Segoe UI', ...
    'FontSize', 12, 'Color', [0.360 0.425 0.515], 'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'middle');
end

function value = localAt(values, index)
value = NaN;
if isempty(index) || ~isfinite(index) || index < 1 || index > numel(values)
    return;
end
value = values(index);
if ~isfinite(value)
    valid = find(isfinite(values(1:index)), 1, 'last');
    if ~isempty(valid)
        value = values(valid);
    end
end
end

function textValue = localNumber(value, pattern)
if isfinite(value)
    textValue = sprintf(pattern, value);
else
    textValue = '—';
end
end

function name = getFileName(pathValue)
[~, name, ext] = fileparts(pathValue);
name = [name, ext];
end

function fontName = localPickFont()
fontName = 'Segoe UI';
try
    installed = listfonts;
    candidates = {'Microsoft YaHei UI', 'Microsoft YaHei', '微软雅黑', 'Segoe UI'};
    for k = 1:numel(candidates)
        if any(strcmpi(installed, candidates{k}))
            fontName = candidates{k};
            return;
        end
    end
catch
end
end

function colors = localColors()
colors = struct();
colors.background = [0.953 0.965 0.980];
colors.surface = [1.000 1.000 1.000];
colors.surfaceAlt = [0.985 0.991 0.998];
colors.border = [0.855 0.885 0.925];
colors.grid = [0.790 0.835 0.900];
colors.axis = [0.265 0.315 0.390];
colors.ink = [0.105 0.145 0.205];
colors.muted = [0.360 0.425 0.515];
colors.primary = [0.090 0.345 0.690];
colors.primarySoft = [0.895 0.935 0.985];
colors.blue = [0.105 0.390 0.820];
colors.orange = [0.905 0.430 0.105];
colors.green = [0.100 0.550 0.360];
colors.red = [0.780 0.155 0.135];
end
