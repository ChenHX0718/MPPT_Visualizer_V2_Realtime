function app = MPPT_Visualizer()
%MPPT_VISUALIZER MPPT 历史 / 实时串口 / UDP / Replay 共用可视化仪表盘。
%   运行 MPPT_Visualizer 后，可在顶部选择四种模式：
%   历史文件、实时串口、模拟实时。实时串口只读取，不向设备发送命令。

projectRoot = fileparts(mfilename('fullpath'));
addpath(genpath(projectRoot));
fontName = localPickFont();
colors = localColors();

fig = uifigure( ...
    'Name', 'MPPT 数据监控 / 历史与实时', ...
    'Color', colors.background, ...
    'Position', [80 60 1400 800], ...
    'AutoResizeChildren', 'on', ...
    'CloseRequestFcn', @onClose);

state = struct();
state.mode = '历史文件';
state.lastFile = '';
state.serial = [];
state.udp = [];
state.receiveTimer = [];
state.pollBusy = false;
state.receiver = mppt.TelemetryReceiver();
state.connectionText = "";
state.serialPort = '';
state.serialBaud = 115200;
state.logFID = -1;
state.logPath = '';
state.replayFID = -1;
state.replayFile = '';
state.replayTimer = [];
state.replayFactor = 1;
state.buffer = mppt.realtimeBuffer('create');
state.validCount = 0;
state.invalidCount = 0;
state.totalCount = 0;
state.lastValidDateTime = NaT;
state.data = [];
state.report = [];
state.closing = false;
state.displayDuration_s = 500;
state.customDuration_s = 500;
state.receiveClock = [];
state.receiveFirst_s = NaN;
state.receiveLast_s = NaN;
state.receiveCount = 0;

rootGrid = uigridlayout(fig, [3 1]);
rootGrid.RowHeight = {132, '1x', 26};
rootGrid.ColumnWidth = {'1x'};
rootGrid.Padding = [22 16 22 10];
rootGrid.RowSpacing = 12;
rootGrid.BackgroundColor = colors.background;

header = uipanel(rootGrid, 'BorderType', 'none', 'BackgroundColor', colors.background);
header.Layout.Row = 1;
headerGrid = uigridlayout(header, [3 1]);
headerGrid.RowHeight = {46, 50, 24};
headerGrid.Padding = [0 0 0 0];
headerGrid.RowSpacing = 5;
headerGrid.BackgroundColor = colors.background;

topGrid = uigridlayout(headerGrid, [1 4]);
topGrid.Layout.Row = 1;
topGrid.ColumnWidth = {'1x', 350, 125, 130};
topGrid.Padding = [0 0 0 0];
topGrid.ColumnSpacing = 12;
topGrid.BackgroundColor = colors.background;

titleLabel = uilabel(topGrid, 'Text', 'MPPT 数据监控 / 历史与实时', ...
    'FontName', fontName, 'FontSize', 22, 'FontWeight', 'bold', ...
    'FontColor', colors.ink, 'HorizontalAlignment', 'left');
titleLabel.Layout.Column = 1;

rangeGrid = uigridlayout(topGrid, [1 4]);
rangeGrid.Layout.Column = 2;
rangeGrid.ColumnWidth = {90, 140, 72, 18};
rangeGrid.Padding = [0 9 0 9];
rangeGrid.ColumnSpacing = 6;
rangeGrid.BackgroundColor = colors.background;
uilabel(rangeGrid, 'Text', '显示时间范围', 'FontName', fontName, 'FontSize', 12);
rangeDrop = uidropdown(rangeGrid, ...
    'Items', {'最近60 s', '最近300 s', '最近500 s', '最近1800 s', ...
    '最近3600 s', '全部（本次记录）', '自定义'}, 'Value', '最近500 s', ...
    'FontName', fontName, 'FontSize', 12, 'ValueChangedFcn', @onRangeChanged);
% 文本输入允许统一检查空值、NaN、Inf及非法字符，错误时恢复上次设置。
customRange = uieditfield(rangeGrid, 'text', 'Value', '500', ...
    'FontName', fontName, 'FontSize', 12, 'Enable', 'off', ...
    'Tooltip', '有限正数，单位 s', 'ValueChangedFcn', @onCustomRangeChanged);
uilabel(rangeGrid, 'Text', 's', 'FontName', fontName, 'FontSize', 12);

modeDrop = uidropdown(topGrid, 'Items', {'历史文件', '实时串口', '实时UDP', '模拟实时'}, ...
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
    'FontSize', 11, 'ForegroundColor', colors.muted, 'BorderColor', colors.border, ...
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
    'FontSize', 11, 'ForegroundColor', colors.muted, 'BorderColor', colors.border, ...
    'BackgroundColor', colors.surface);
serialPanel.Layout.Column = 2;
serialGrid = uigridlayout(serialPanel, [1 11]);
serialGrid.ColumnWidth = {42, '1.15x', 58, 78, 58, 58, 70, 40, 52, 48, 52};
serialGrid.Padding = [6 2 6 4];
serialGrid.ColumnSpacing = 5;
serialGrid.BackgroundColor = colors.surface;
uilabel(serialGrid, 'Text', 'COM', 'FontName', fontName, 'FontSize', 11, ...
    'FontColor', colors.muted, 'HorizontalAlignment', 'center');
portDrop = uidropdown(serialGrid, 'Items', {'正在检测…'}, 'FontName', fontName, ...
    'FontSize', 11, 'Value', '正在检测…');
refreshButton = uibutton(serialGrid, 'push', 'Text', '刷新', 'FontName', fontName, ...
    'FontSize', 11, 'ButtonPushedFcn', @refreshPorts);
baudDrop = uidropdown(serialGrid, 'Items', {'9600', '19200', '38400', '57600', '115200', '230400'}, ...
    'Value', '115200', 'FontName', fontName, 'FontSize', 11);
connectButton = uibutton(serialGrid, 'push', 'Text', '连接', 'FontName', fontName, ...
    'FontSize', 11, 'FontWeight', 'bold', 'FontColor', [1 1 1], ...
    'BackgroundColor', colors.green, 'ButtonPushedFcn', @connectSerial, 'Tooltip', '连接并开始新记录，清空本次曲线与累计值');
disconnectButton = uibutton(serialGrid, 'push', 'Text', '断开', 'FontName', fontName, ...
    'FontSize', 11, 'BackgroundColor', colors.surfaceAlt, 'ButtonPushedFcn', @disconnectSerial);
clearButton = uibutton(serialGrid, 'push', 'Text', '清空曲线', 'FontName', fontName, ...
    'FontSize', 11, 'BackgroundColor', colors.surfaceAlt, 'ButtonPushedFcn', @clearRealtime, ...
    'Tooltip', '清空本次曲线和累计值，下一条有效Uptime_s开始新记录；原始日志继续保存');

uilabel(serialGrid, 'Text', 'Sys', 'FontName', fontName, 'FontSize', 11);
sysField = uieditfield(serialGrid, 'numeric', 'Value', 0, 'Limits', [0 255], ...
    'RoundFractionalValues', 'on', 'Tooltip', 'MAVLink源System ID，0=自动');
uilabel(serialGrid, 'Text', 'Comp', 'FontName', fontName, 'FontSize', 11);
compField = uieditfield(serialGrid, 'numeric', 'Value', 0, 'Limits', [0 255], ...
    'RoundFractionalValues', 'on', 'Tooltip', 'MAVLink源Component ID，0=自动');

udpPanel = uipanel(controlGrid, 'Title', 'R30 UDP（只读，协议自动识别）', ...
    'FontName', fontName, 'FontSize', 11, 'BorderColor', colors.border, ...
    'BackgroundColor', colors.surface);
udpGrid = uigridlayout(udpPanel, [1 10]);
udpGrid.ColumnWidth = {100, 100, 80, 80, 90, 45, 65, 50, 65, '1x'};
udpGrid.Padding = [6 2 6 4]; udpGrid.ColumnSpacing = 5;
udpGrid.BackgroundColor = colors.surface;
uilabel(udpGrid, 'Text', '本机监听端口', 'FontName', fontName);
udpPortField = uieditfield(udpGrid, 'numeric', 'Value', 14552, 'ValueDisplayFormat', '%.0f', ...
    'Limits', [1 65535], 'RoundFractionalValues', 'on', ...
    'Tooltip', '绑定0.0.0.0；需与R30发往本机的目标端口匹配');
uibutton(udpGrid, 'Text', '监听', 'FontName', fontName, 'ButtonPushedFcn', @connectUDP);
uibutton(udpGrid, 'Text', '断开', 'FontName', fontName, 'ButtonPushedFcn', @disconnectSerial);
uibutton(udpGrid, 'Text', '清空曲线', 'FontName', fontName, 'ButtonPushedFcn', @clearRealtime);
uilabel(udpGrid, 'Text', 'Sys', 'FontName', fontName);
udpSysField = uieditfield(udpGrid, 'numeric', 'Value', 0, 'Limits', [0 255], ...
    'RoundFractionalValues', 'on', 'Tooltip', '0=自动识别来源');
uilabel(udpGrid, 'Text', 'Comp', 'FontName', fontName);
udpCompField = uieditfield(udpGrid, 'numeric', 'Value', 0, 'Limits', [0 255], ...
    'RoundFractionalValues', 'on', 'Tooltip', '0=自动识别来源');

replayPanel = uipanel(controlGrid, 'Title', '模拟实时 / Replay', 'FontName', fontName, ...
    'FontSize', 11, 'ForegroundColor', colors.muted, 'BorderColor', colors.border, ...
    'BackgroundColor', colors.surface);
replayPanel.Layout.Column = 3;
replayGrid = uigridlayout(replayPanel, [1 5]);
replayGrid.ColumnWidth = {42, '1.35x', 62, 58, 58};
replayGrid.Padding = [6 2 6 4];
replayGrid.ColumnSpacing = 5;
replayGrid.BackgroundColor = colors.surface;
uilabel(replayGrid, 'Text', '文件', 'FontName', fontName, 'FontSize', 11, ...
    'FontColor', colors.muted, 'HorizontalAlignment', 'center');
replayFileButton = uibutton(replayGrid, 'push', 'Text', '选择日志', ...
    'FontName', fontName, 'FontSize', 11, 'ButtonPushedFcn', @selectReplayFile);
speedDrop = uidropdown(replayGrid, 'Items', {'1x', '5x', '10x'}, 'Value', '1x', ...
    'FontName', fontName, 'FontSize', 11, 'ValueChangedFcn', @onReplaySpeedChanged);
replayStartButton = uibutton(replayGrid, 'push', 'Text', '开始', 'FontName', fontName, ...
    'FontSize', 11, 'FontWeight', 'bold', 'FontColor', [1 1 1], ...
    'BackgroundColor', colors.primary, 'ButtonPushedFcn', @startReplay);
replayStopButton = uibutton(replayGrid, 'push', 'Text', '停止', 'FontName', fontName, ...
    'FontSize', 11, 'BackgroundColor', colors.surfaceAlt, 'ButtonPushedFcn', @stopReplay);

headerStatusGrid = uigridlayout(headerGrid, [1 3]);
headerStatusGrid.Layout.Row = 3;
headerStatusGrid.ColumnWidth = {'1.3x', '1.4x', '1x'};
headerStatusGrid.Padding = [0 0 0 0];
headerStatusGrid.ColumnSpacing = 12;
headerStatusGrid.BackgroundColor = colors.background;
connectionLabel = uilabel(headerStatusGrid, 'Text', '未连接', 'FontName', fontName, ...
    'FontSize', 12, 'FontColor', colors.muted, 'HorizontalAlignment', 'left');
fileLabel = uilabel(headerStatusGrid, 'Text', '文件：尚未载入', 'FontName', fontName, ...
    'FontSize', 12, 'FontColor', colors.muted, 'HorizontalAlignment', 'left');
reportLabel = uilabel(headerStatusGrid, 'Text', '等待数据', 'FontName', fontName, ...
    'FontSize', 12, 'FontColor', colors.muted, 'HorizontalAlignment', 'right');

content = uigridlayout(rootGrid, [2 3]);
content.Layout.Row = 2;
content.ColumnWidth = {330, '1x', '1x'};
content.RowHeight = {'1x', '1.03x'};
content.Padding = [0 0 0 0];
content.RowSpacing = 14;
content.ColumnSpacing = 14;
content.BackgroundColor = colors.background;

statusPanel = uipanel(content, 'BorderType', 'line', 'BorderColor', colors.border, ...
    'BackgroundColor', colors.surface);
statusPanel.Layout.Row = [1 2];
statusPanel.Layout.Column = 1;
statusGrid = uigridlayout(statusPanel, [8 1]);
statusGrid.RowHeight = {38, 38, 38, 38, 38, 38, 38, '1x'};
statusGrid.Padding = [14 14 14 14];
statusGrid.RowSpacing = 8;
statusGrid.BackgroundColor = colors.surface;
statusHeading = uilabel(statusGrid, 'Text', '实时状态 / 最后有效采样', ...
    'FontName', fontName, 'FontSize', 16, 'FontWeight', 'bold', ...
    'FontColor', colors.ink, 'HorizontalAlignment', 'left');
statusHeading.Layout.Row = 1;
[solarVoltageValue, solarVoltageUnit] = localMakeMetricRow(statusGrid, 2, '太阳能板电压');
[solarCurrentValue, solarCurrentUnit] = localMakeMetricRow(statusGrid, 3, '太阳能电流');
[solarPowerValue, solarPowerUnit] = localMakeMetricRow(statusGrid, 4, '实时功率');
[energyValue, energyUnit] = localMakeMetricRow(statusGrid, 5, '累计输出能量');
[capacityValue, capacityUnit] = localMakeMetricRow(statusGrid, 6, '累计输出容量');
[errorValue, errorUnit] = localMakeMetricRow(statusGrid, 7, 'Error Flag');
statusDetail = uilabel(statusGrid, 'Text', '等待有效数据…', 'FontName', fontName, ...
    'FontSize', 11, 'FontColor', colors.muted, 'HorizontalAlignment', 'left', ...
    'VerticalAlignment', 'top', 'WordWrap', 'on');
statusDetail.Layout.Row = 8;

[batteryAxes, batteryTitle] = localMakeChartPanel(content, '电池电压变化', ...
    '记录时间 / s', '电池电压 / V', fontName, colors, 1, 2);
[powerAxes, powerTitle] = localMakeChartPanel(content, '太阳能功率变化', ...
    '记录时间 / s', '太阳能功率 / W', fontName, colors, 1, 3);
[energyAxes, energyTitle] = localMakeChartPanel(content, '太阳能累计输出能量', ...
    '记录时间 / s', '累计太阳能输出能量 / Wh', fontName, colors, 2, [2 3]);

footerGrid = uigridlayout(rootGrid, [1 2]);
footerGrid.Layout.Row = 3; footerGrid.ColumnWidth = {'1x',100};
footerGrid.Padding = [0 0 0 0];
exportButton = uibutton(footerGrid, 'Text', '导出 CSV', 'FontName', fontName, ...
    'ButtonPushedFcn', @exportCurrentCSV);
exportButton.Layout.Column = 2;
footer = uilabel(footerGrid, 'Text', ...
    '历史文件 / Replay  ·  串口 / UDP只读，协议自动识别  ·  完整遥测行保存到 realtime_logs', ...
    'FontName', fontName, 'FontSize', 11, 'FontColor', colors.muted, ...
    'HorizontalAlignment', 'left');
footer.Layout.Row = 1; footer.Layout.Column = 1;
footerGrid.RowHeight = {26};

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
        state.buffer = mppt.realtimeBuffer('create');
        state.validCount = 0;
        state.invalidCount = 0;
        state.totalCount = 0;
        state.lastValidDateTime = NaT;
        state.data = [];
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
            localRefreshRange();
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
            modeDrop.Value = '实时串口'; onModeChanged(modeDrop, []);
        end
        portName = char(portDrop.Value);
        if isempty(portName) || startsWith(portName, '(')
            localShowError('没有可用 COM 口', '请点击“刷新”确认 MPPT USB 串口。'); return;
        end
        localDisconnect(); localResetRealtime();
        try
            state.serial = serialport(portName, str2double(baudDrop.Value), ...
                'DataBits', 8, 'Parity', 'none', 'StopBits', 1, ...
                'FlowControl', 'none', 'Timeout', 1);
            configureCallback(state.serial, 'off');
            state.serialPort = portName; state.serialBaud = str2double(baudDrop.Value);
            state.connectionText = sprintf('%s @ %d', portName, state.serialBaud);
            state.receiver = mppt.TelemetryReceiver(struct('SourceSystem',sysField.Value, ...
                'SourceComponent',compField.Value));
            localStartReception();
        catch ME
            localDisconnect(); localShowError('串口连接失败', ME.message);
        end
    end

    function connectUDP(~, ~)
        if ~strcmp(state.mode, '实时UDP')
            modeDrop.Value = '实时UDP'; onModeChanged(modeDrop, []);
        end
        localDisconnect(); localResetRealtime();
        try
            if isempty(which('udpport'))
                error('MPPT:UDPUnavailable', '当前MATLAB没有udpport能力；串口模式仍可使用。');
            end
            state.udp = udpport('datagram', 'IPV4', 'LocalHost', '0.0.0.0', ...
                'LocalPort', udpPortField.Value, 'Timeout', 1);
            configureCallback(state.udp, 'off');
            state.connectionText = sprintf('UDP 0.0.0.0:%d', udpPortField.Value);
            state.receiver = mppt.TelemetryReceiver(struct('SourceSystem',udpSysField.Value, ...
                'SourceComponent',udpCompField.Value));
            localStartReception();
        catch ME
            localDisconnect(); localShowError('UDP监听失败', ME.message);
        end
    end

    function localStartReception()
        logDir = fullfile(projectRoot, 'realtime_logs');
        if ~isfolder(logDir), mkdir(logDir); end
        base = ['MPPT_',datestr(now,'yyyymmdd_HHMMSS')];
        state.logPath = fullfile(logDir,[base,'.log']);
        suffix = 0;
        while isfile(state.logPath)
            suffix = suffix+1;
            state.logPath = fullfile(logDir,sprintf('%s_%02d.log',base,suffix));
        end
        % Binary fwrite preserves original UTF-8, LF and CRLF without an extra LF.
        state.logFID = fopen(state.logPath, 'wb');
        if state.logFID < 0, error('MPPT:LogOpen','无法创建日志：%s',state.logPath); end
        state.receiveTimer = timer('ExecutionMode','fixedSpacing','Period',0.1, ...
            'BusyMode','drop','Name','MPPT byte reception', ...
            'TimerFcn',@onReceiveTick,'ErrorFcn',@onReceiveError);
        start(state.receiveTimer); localUpdateConnectionStatus();
        fileLabel.Text = ['日志：', getFileName(state.logPath)];
        fileLabel.Tooltip = state.logPath;
    end

    function disconnectSerial(~, ~)
        localDisconnect();
    end

    function localDisconnect()
        if ~isempty(state.receiveTimer)
            try, stop(state.receiveTimer); catch, end
            try, delete(state.receiveTimer); catch, end
            state.receiveTimer = [];
        end
        transports = {state.serial,state.udp};
        state.serial = []; state.udp = [];
        for k = 1:numel(transports)
            if ~isempty(transports{k})
                try, configureCallback(transports{k}, 'off'); catch, end
                try, delete(transports{k}); catch, end
            end
        end
        if state.logFID >= 0
            try, fclose(state.logFID); catch, end
            state.logFID = -1;
        end
        state.receiver.reset();
        if any(strcmp(state.mode, {'实时串口','实时UDP'})) && ~state.closing
            connectionLabel.Text = '未连接 · 协议：等待识别';
            connectionLabel.FontColor = colors.muted;
            reportLabel.Text = sprintf('已断开 · 有效 %d',state.validCount);
        end
    end

    function onReceiveTick(~, ~)
        if state.closing || state.pollBusy, return; end
        state.pollBusy = true;
        try
            now_s = toc(state.receiveClock);
            state.receiver.expire(now_s); % Cleanup also runs with no incoming bytes.
            if ~isempty(state.serial)
                count = min(double(state.serial.NumBytesAvailable),65536);
                if count > 0
                    bytes = uint8(read(state.serial,count,'uint8'));
                    localConsumeBytes(bytes,['serial:',state.serialPort],now_s);
                end
            elseif ~isempty(state.udp)
                count = min(double(state.udp.NumDatagramsAvailable),128);
                if count > 0
                    datagrams = read(state.udp,count,'uint8');
                    for k = 1:numel(datagrams)
                        if state.closing || isempty(state.udp), break; end
                        endpoint = sprintf('udp:%s:%d',char(datagrams(k).SenderAddress), ...
                            double(datagrams(k).SenderPort));
                        localConsumeBytes(uint8(datagrams(k).Data),endpoint,now_s);
                    end
                end
            end
            if ~state.closing, localUpdateConnectionStatus(); end
        catch ME
            state.pollBusy = false;
            rethrow(ME);
        end
        state.pollBusy = false;
    end

    function onReceiveError(~, evt)
        if state.closing, return; end
        localDisconnect(); localShowError('遥测接收中断',evt.Data.Message);
    end

    function localConsumeBytes(bytes,endpoint,now_s)
        events = state.receiver.feed(uint8(bytes),endpoint,now_s);
        for k = 1:numel(events)
            if state.closing || (isempty(state.serial) && isempty(state.udp)), break; end
            e = events{k};
            if state.logFID >= 0, fwrite(state.logFID,e.rawBytes,'uint8'); end
            state.totalCount = state.totalCount+1;
            if e.valid
                localAcceptRecord(e.record,true,e.meta);
            else
                state.invalidCount=state.invalidCount+1;
            end
        end
    end

    function localConsumeLine(rawLine, ~)
        % Replay keeps the existing text/history parser and file semantics.
        state.totalCount=state.totalCount+1;
        [record,valid]=mppt.parseTelemetryLine(rawLine);
        if ~valid
            state.invalidCount=state.invalidCount+1;
            reportLabel.Text=sprintf('Replay有效 %d · 跳过 %d',state.validCount,state.invalidCount);
            return;
        end
        localAcceptRecord(record,false,[]);
    end

    function localAcceptRecord(record,isLive,meta)
        [state.buffer,data]=mppt.realtimeBuffer('append',state.buffer,record,meta);
        state.data=data; state.validCount=state.validCount+1;
        state.lastValidDateTime=datetime('now');
        if isLive
            received_s=toc(state.receiveClock);
            if state.receiveCount==0, state.receiveFirst_s=received_s; end
            state.receiveLast_s=received_s; state.receiveCount=state.receiveCount+1;
        end
        localRenderRealtime(data); localUpdateStatusFromData(data);
        if isLive, localUpdateConnectionStatus();
        else, reportLabel.Text=sprintf('Replay有效 %d · 跳过 %d',state.validCount,state.invalidCount); end
        drawnow limitrate;
    end

    function localUpdateConnectionStatus()
        receiver=state.receiver; stats=receiver.Stats;
        age=toc(state.receiveClock)-receiver.LastValid_s;
        if isfinite(age)
            health=sprintf('最近有效 %.1f s 前',age);
            if age>3, health=[health,' · 遥测超时']; connectionLabel.FontColor=colors.red;
            else, connectionLabel.FontColor=colors.green; end
        elseif receiver.MavlinkSeen
            health='已收到MAVLink，等待完整有效MPPT'; connectionLabel.FontColor=colors.muted;
        else
            health='等待有效MPPT'; connectionLabel.FontColor=colors.muted;
        end
        connectionLabel.Text=sprintf('%s · %s',state.connectionText,health);
        connectionLabel.Tooltip=connectionLabel.Text;
        reportLabel.Text=sprintf('有效 %d · 坏帧 %d · 重组超时 %d', ...
            state.validCount,stats.BadFrames,stats.Timeouts);
        if ~isempty(state.data), localUpdateStatusFromData(state.data); end
        statusDetail.Text=sprintf('%s\n协议：%s\n来源：%s\n%s\n坏记录 %d · 迟到 %d · 其他来源 %d', ...
            statusDetail.Text,receiver.Protocol,receiver.Source,health, ...
            stats.BadRecords,stats.LateRecords,stats.IgnoredSources);
        if isempty(state.data)
            statusDetail.Text=sprintf('协议：%s\n%s\n%s\n坏帧 %d · 重组超时 %d', ...
                receiver.Protocol,state.connectionText,health,stats.BadFrames,stats.Timeouts);
        end
    end

    function exportCurrentCSV(~, ~)
        if isempty(state.data), localShowError('无法导出','请先载入或接收有效遥测。'); return; end
        [name,folder]=uiputfile('*.csv','导出本次完整数据','MPPT.csv');
        if isequal(name,0), return; end
        try, mppt.exportCSV(state.data,fullfile(folder,name));
        catch ME, localShowError('CSV导出失败',ME.message); end
    end

    function onRangeChanged(~, ~)
        choice = rangeDrop.Value;
        customRange.Enable = strcmp(choice, '自定义');
        if strcmp(choice, '全部（本次记录）')
            state.displayDuration_s = Inf;
        elseif strcmp(choice, '自定义')
            state.displayDuration_s = state.customDuration_s;
        else
            state.displayDuration_s = sscanf(choice, '最近%f s');
        end
        localRefreshRange();
    end

    function onCustomRangeChanged(~, ~)
        value = str2double(strtrim(customRange.Value));
        if ~isreal(value) || ~isscalar(value) || ~isfinite(value) || value <= 0
            customRange.Value = sprintf('%g', state.customDuration_s);
            uialert(fig, '请输入有限正数（单位 s）。已保留上一次有效设置，接收继续。', ...
                '显示时间范围无效', 'Icon', 'warning');
            return;
        end
        state.customDuration_s = value;
        state.displayDuration_s = value;
        localRefreshRange();
    end

    function localRefreshRange()
        if strcmp(state.mode, '历史文件')
            return;
        end
        [~, ~, label] = mppt.timeWindow([], state.displayDuration_s);
        batteryTitle.Text = ['电池电压变化 · ', label];
        powerTitle.Text = ['太阳能功率变化 · ', label];
        if ~isempty(state.data)
            localRenderRealtime(state.data);
        end
        drawnow limitrate;
    end

    function clearRealtime(~, ~)
        localResetRealtime();
    end

    function localResetRealtime()
        state.buffer = mppt.realtimeBuffer('create');
        state.validCount = 0;
        state.invalidCount = 0;
        state.totalCount = 0;
        state.lastValidDateTime = NaT;
        state.data = [];
        state.receiver.reset();
        state.receiveClock = tic;
        state.receiveFirst_s = NaN;
        state.receiveLast_s = NaN;
        state.receiveCount = 0;
        localClearAxes();
        localUpdateStatusFromData([]);
        reportLabel.Text = '实时曲线已清空';
        localRefreshRange();
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
            [x, y] = mppt.plotSeries(data.Time_s, data.Bat_V, data.breakBefore);
            localPlotAndFit(batteryAxes, x, y, colors.blue);
        else
            localEmptyAxes(batteryAxes, '此文件无 Bat_V 数据');
        end
        valid = isfinite(data.Time_s) & isfinite(data.SolarPower_W);
        if any(valid)
            [x, y] = mppt.plotSeries(data.Time_s, data.SolarPower_W, data.breakBefore);
            localPlotAndFit(powerAxes, x, y, colors.orange);
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
            [x, y] = mppt.plotSeries(data.Time_s, data.Energy_Wh, data.breakBefore);
            localPlotAndFit(energyAxes, x, y, colors.green);
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
        localStyleAxes(batteryAxes, '记录时间 / s', '电池电压 / V');
        localStyleAxes(powerAxes, '记录时间 / s', '太阳能功率 / W');
        localStyleAxes(energyAxes, '记录时间 / s', '累计太阳能输出能量 / Wh');
    end

    function localRenderRealtime(data)
        localEnsureRealtimeLines();
        [index, limits, label] = mppt.timeWindow(data.Time_s, state.displayDuration_s);
        [x, y] = mppt.plotSeries(data.Time_s, data.Bat_V, data.breakBefore, index);
        localSetLine(lineHandles.battery, x, y);
        localRealtimeLimits(batteryAxes, x, y);
        [x, y] = mppt.plotSeries(data.Time_s, data.SolarPower_W, data.breakBefore, index);
        localSetLine(lineHandles.power, x, y);
        localRealtimeLimits(powerAxes, x, y);
        batteryAxes.XLim = limits;
        powerAxes.XLim = limits;
        [x, y] = mppt.plotSeries(data.Time_s, data.Energy_Wh, data.breakBefore);
        localSetLine(lineHandles.energy, x, y);
        localRealtimeLimits(energyAxes, x, y);
        energyTitle.Text = '太阳能累计输出能量 · 本次记录';
        batteryTitle.Text = ['电池电压变化 · ', label];
        powerTitle.Text = ['太阳能功率变化 · ', label];
        localStyleAxes(batteryAxes, '记录时间 / s', '电池电压 / V');
        localStyleAxes(powerAxes, '记录时间 / s', '太阳能功率 / W');
        localStyleAxes(energyAxes, '记录时间 / s', '累计太阳能输出能量 / Wh');
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
        lineHandle.Marker = 'none';
        if nnz(valid) == 1
            lineHandle.Marker = '.';
            lineHandle.MarkerSize = 12;
        end
        if any(valid)
            lineHandle.XData = x;
            lineHandle.YData = y;
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
            solarVoltageValue.Text = '—'; solarVoltageUnit.Text = 'V';
            solarCurrentValue.Text = '—'; solarCurrentUnit.Text = 'A';
            solarPowerValue.Text = '—'; solarPowerUnit.Text = 'W';
            energyValue.Text = '—'; energyUnit.Text = 'Wh';
            capacityValue.Text = '—'; capacityUnit.Text = 'mAh';
            errorValue.Text = '—'; errorUnit.Text = '';
            statusDetail.Text = '等待有效数据…';
            statusPanel.BackgroundColor = colors.surface;
            return;
        end
        idx = data.metrics.lastIndex;
        solarVoltageValue.Text = localNumber(localAt(data.Solar_V, idx), '%.2f'); solarVoltageUnit.Text = 'V';
        solarCurrentValue.Text = localNumber(localAt(data.Solar_A_generation, idx), '%.2f'); solarCurrentUnit.Text = 'A';
        solarPowerValue.Text = localNumber(localAt(data.SolarPower_W, idx), '%.2f'); solarPowerUnit.Text = 'W';
        lastError = localAt(data.ErrorFlags, idx);
        energyValue.Text = localNumber(localAt(data.Energy_Wh, idx), '%.2f'); energyUnit.Text = 'Wh';
        capacityValue.Text = localNumber(localAt(data.Capacity_mAh, idx), '%.2f'); capacityUnit.Text = 'mAh';
        errorValue.Text = localNumber(lastError, '%.0f'); errorUnit.Text = '';
        if isfinite(lastError) && lastError ~= 0
            statusPanel.BackgroundColor = [1.000 0.945 0.940];
            errorValue.FontColor = colors.red;
        else
            statusPanel.BackgroundColor = colors.surface;
            errorValue.FontColor = colors.ink;
        end
        detailParts = {['Pmax ', localNumber(data.metrics.Pmax_W, '%.2f'), ' W'], ...
            ['Wh：', data.energySource], ['mAh：', data.capacitySource], data.solarSignRule};
        if state.validCount > 0 && ~isnat(state.lastValidDateTime)
            detailParts{end+1} = ['最近有效：', datestr(state.lastValidDateTime, 'yyyy-mm-dd HH:MM:SS')];
        end
        detailParts{end+1} = '时间依据：板端Uptime_s（缺失时间不推算）';
        clock = data.clock;
        if clock.invalidated
            detailParts{end+1} = '时间倒退：复位/乱序未确认。原始行继续保存；请清空曲线开始新记录。';
        end
        if clock.missingCount > 0 || clock.gapCount > 0
            detailParts{end+1} = sprintf('未知时间 %d 条；>10 s 缺口 %d 处。累计值不覆盖未知区间。', ...
                clock.missingCount, clock.gapCount);
        end
        if any(strcmp(state.mode, {'实时串口','实时UDP'})) && state.receiveCount > 1 && ...
                state.receiveLast_s > state.receiveFirst_s
            detailParts{end+1} = sprintf('有效接收约 %.2f Hz（电脑回调接收时刻）', ...
                (state.receiveCount-1)/(state.receiveLast_s-state.receiveFirst_s));
        end
        statusDetail.Text = strjoin(detailParts, newline);
    end

    function localUpdateControlVisibility()
        currentMode = modeDrop.Value;
        historyPanel.Layout.Row = 1;
        serialPanel.Layout.Row = 1;
        udpPanel.Layout.Row = 1;
        replayPanel.Layout.Row = 1;
        controlGrid.RowHeight = {'1x'};
        historyPanel.Layout.Column = [1 3];
        serialPanel.Layout.Column = [1 3];
        udpPanel.Layout.Column = [1 3];
        replayPanel.Layout.Column = [1 3];
        rangeDrop.Enable = ~strcmp(currentMode, '历史文件');
        customRange.Enable = ~strcmp(currentMode, '历史文件') && strcmp(rangeDrop.Value, '自定义');
        historyPanel.Visible = strcmp(currentMode, '历史文件');
        serialPanel.Visible = strcmp(currentMode, '实时串口');
        udpPanel.Visible = strcmp(currentMode, '实时UDP');
        replayPanel.Visible = strcmp(currentMode, '模拟实时');
        if strcmp(currentMode, '实时串口')
            modeLabel.Text = '实时串口模式';
        elseif strcmp(currentMode, '实时UDP')
            modeLabel.Text = '实时UDP模式';
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
grid.ColumnWidth = {'1.55x', '1x'};
grid.Padding = [0 0 0 0];
grid.ColumnSpacing = 6;
grid.BackgroundColor = parent.BackgroundColor;
uilabel(grid, 'Text', titleText, 'FontName', 'Segoe UI', 'FontSize', 18, ...
    'FontColor', [0.360 0.425 0.515], 'HorizontalAlignment', 'left', ...
    'VerticalAlignment', 'center');
valueGrid = uigridlayout(grid, [1 2]);
valueGrid.Layout.Column = 2;
valueGrid.ColumnWidth = {'1x', 42};
valueGrid.Padding = [0 0 0 0];
valueGrid.ColumnSpacing = 2;
valueGrid.BackgroundColor = parent.BackgroundColor;
valueLabel = uilabel(valueGrid, 'Text', '—', 'FontName', 'Segoe UI', ...
    'FontSize', 20, 'FontWeight', 'bold', 'FontColor', [0.105 0.145 0.205], ...
    'HorizontalAlignment', 'right');
unitLabel = uilabel(valueGrid, 'Text', '', 'FontName', 'Segoe UI', 'FontSize', 17, ...
    'FontColor', [0.090 0.345 0.690], 'HorizontalAlignment', 'left');
end

function [ax, heading] = localMakeChartPanel(parent, titleText, xLabelText, yLabelText, fontName, colors, row, column)
panel = uipanel(parent, 'BorderType', 'line', 'BorderColor', colors.border, ...
    'BackgroundColor', colors.surface);
panel.Layout.Row = row;
panel.Layout.Column = column;
grid = uigridlayout(panel, [2 1]);
grid.RowHeight = {42, '1x'};
grid.Padding = [16 12 16 18];
grid.RowSpacing = 4;
grid.BackgroundColor = colors.surface;
heading = uilabel(grid, 'Text', titleText, 'FontName', fontName, ...
    'FontSize', 19, 'FontWeight', 'bold', 'FontColor', colors.ink, ...
    'HorizontalAlignment', 'left');
heading.Layout.Row = 1;
if row == 2
    heading.HorizontalAlignment = 'center';
    grid.RowHeight = {32, '1x'};
    grid.RowSpacing = 10;
    grid.Padding = [20 12 20 14];
end
ax = uiaxes(grid);
ax.Layout.Row = 2;
localStyleAxes(ax, xLabelText, yLabelText);
end

function localStyleAxes(ax, xLabelText, yLabelText)
ax.FontName = 'Segoe UI';
ax.FontSize = 14;
ax.XColor = [0.265 0.315 0.390];
ax.YColor = [0.265 0.315 0.390];
ax.GridColor = [0.790 0.835 0.900];
ax.MinorGridColor = [0.790 0.835 0.900];
ax.GridAlpha = 0.38;
ax.MinorGridAlpha = 0.18;
ax.LineWidth = 0.8;
ax.Box = 'off';
ax.Color = [1 1 1];
xlabel(ax, xLabelText, 'FontName', 'Segoe UI', 'FontSize', 16, 'Color', ax.XColor);
ylabel(ax, yLabelText, 'FontName', 'Segoe UI', 'FontSize', 16, 'Color', ax.YColor);
ax.XLabel.FontSize = 16;
ax.YLabel.FontSize = 16;
if contains(yLabelText, '累计太阳能')
    % 两行物理量标签仍保留16号字和Wh单位，避免短窗时纵向越过标题行。
    ax.YLabel.String = {'累计太阳能输出', '能量 / Wh'};
end
ax.XGrid = 'on';
ax.YGrid = 'on';
end

function localPlotAndFit(ax, x, y, color)
lineHandle = plot(ax, x, y, '-', 'Color', color, 'LineWidth', 1.8);
valid = isfinite(x) & isfinite(y);
x = x(valid); y = y(valid);
if numel(x) == 1
    lineHandle.Marker = '.';
    lineHandle.MarkerSize = 12;
end
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
    'FontSize', 14, 'Color', [0.360 0.425 0.515], 'HorizontalAlignment', 'center', ...
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
