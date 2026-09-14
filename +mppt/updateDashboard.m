function updateDashboard(handles, data, report, filePath)
%UPDATEDASHBOARD 用统一的数据结构刷新卡片和三张图。

c = handles.colors;
fontName = handles.fontName;
fileName = char(string(filePath));
[~, shortName, ext] = fileparts(fileName);
handles.fileLabel.Text = ['文件：', shortName, ext];
handles.fileLabel.Tooltip = fileName;
handles.reportLabel.Text = sprintf('有效 %d 行  ·  共 %d 行  ·  跳过 %d 行', ...
    report.parsedCount, report.totalLines, report.skippedCount);

metrics = data.metrics;
if isfinite(metrics.V_at_Pmax_V)
    handles.vmpValue.Text = sprintf('%.2f', metrics.V_at_Pmax_V);
    handles.vmpUnit.Text = 'V';
    handles.vmpDetail.Text = sprintf('%s  ·  Pmax %.2f W', metrics.vmpSource, metrics.Pmax_W);
else
    handles.vmpValue.Text = '—';
    handles.vmpUnit.Text = 'V';
    handles.vmpDetail.Text = '没有足够的 Solar_V / Solar_A 数据';
end

lastIndex = metrics.lastIndex;
lastBat = localAt(data.Bat_V, lastIndex);
if isfinite(lastBat)
    handles.batteryValue.Text = sprintf('%.2f', lastBat);
    handles.batteryUnit.Text = 'V';
else
    handles.batteryValue.Text = '—';
    handles.batteryUnit.Text = 'V';
end
handles.batteryDetail.Text = '最后一个有效采样点';

lastChg = localAt(data.ChgState, lastIndex);
lastDcdc = localAt(data.DCDCState, lastIndex);
lastError = localAt(data.ErrorFlags, lastIndex);
state = mppt.formatMPPTState(lastChg, lastDcdc, lastError);
handles.stateValue.Text = state.mainText;
handles.stateUnit.Text = '状态';
handles.stateDetail.Text = sprintf('DCDC：%s  ·  ChgState：%s  ·  ErrorFlags：%s', ...
    state.dcdcText, state.chgText, state.errorText);
if state.hasError
    handles.stateCard.BackgroundColor = [1.000 0.945 0.940];
    handles.stateValue.FontColor = c.red;
    handles.stateUnit.FontColor = c.red;
    handles.stateDetail.FontColor = c.red;
else
    handles.stateCard.BackgroundColor = c.surfaceAlt;
    handles.stateValue.FontColor = c.ink;
    handles.stateUnit.FontColor = c.primary;
    handles.stateDetail.FontColor = c.muted;
end

localPlotBattery(handles.batteryAxes, data, fontName, c);
localPlotPower(handles.powerAxes, data, fontName, c, metrics);
localPlotEnergy(handles.energyAxes, data, fontName, c);
if data.energyIsComputed
    handles.energyTitle.Text = '太阳能累计输出能量 · 计算值';
else
    handles.energyTitle.Text = '太阳能累计输出能量 · 原始字段';
end
drawnow;
end

function localPlotBattery(ax, data, fontName, c)
cla(ax, 'reset');
localStyleAxes(ax, fontName, c, '记录时间 / s', '电池电压 / V');
valid = isfinite(data.Time_s) & isfinite(data.Bat_V);
if ~any(valid)
    localEmptyAxes(ax, '此文件无 Bat_V 数据', fontName, c);
    return;
end
x = data.Time_s(valid);
y = data.Bat_V(valid);
lineHandle = plot(ax, x, y, '-', 'Color', c.blue, 'LineWidth', 1.8);
localFitLimits(ax, x, y);
lineHandle.DataTipTemplate.DataTipRows = [ ...
    dataTipTextRow('记录时间 / s', x), dataTipTextRow('电池电压 / V', y)];
localStyleAxes(ax, fontName, c, '记录时间 / s', '电池电压 / V');
end

function localPlotPower(ax, data, fontName, c, metrics)
cla(ax, 'reset');
localStyleAxes(ax, fontName, c, '记录时间 / s', '太阳能功率 / W');
valid = isfinite(data.Time_s) & isfinite(data.SolarPower_W);
if ~any(valid)
    localEmptyAxes(ax, '此文件无有效 Solar_V / Solar_A 数据', fontName, c);
    return;
end
x = data.Time_s(valid);
y = data.SolarPower_W(valid);
lineHandle = plot(ax, x, y, '-', 'Color', c.orange, 'LineWidth', 1.8);
localFitLimits(ax, x, y);
lineHandle.DataTipTemplate.DataTipRows = [ ...
    dataTipTextRow('记录时间 / s', x), dataTipTextRow('太阳能功率 / W', y)];

if isfinite(metrics.indexAtPmax) && isfinite(metrics.Pmax_W)
    idx = metrics.indexAtPmax;
    if isfinite(data.Time_s(idx))
        hold(ax, 'on');
        marker = plot(ax, data.Time_s(idx), data.SolarPower_W(idx), 'o', ...
            'MarkerSize', 8, 'LineWidth', 1.4, 'MarkerEdgeColor', c.orange, ...
            'MarkerFaceColor', c.surface);
        marker.DataTipTemplate.DataTipRows = [ ...
            dataTipTextRow('Pmax / W', metrics.Pmax_W), ...
            dataTipTextRow('Solar_V / V', data.Solar_V(idx)), ...
            dataTipTextRow('Solar_A 原始 / A', data.Solar_A_raw(idx)), ...
            dataTipTextRow('Uptime / s', data.Uptime_s(idx))];
        label = sprintf('Pmax = %.2f W\nV = %.2f V', metrics.Pmax_W, metrics.V_at_Pmax_V);
        text(ax, data.Time_s(idx), data.SolarPower_W(idx), ['  ', label], ...
            'FontName', fontName, 'FontSize', 10, 'Color', c.orange, ...
            'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'left', ...
            'Clipping', 'on');
        hold(ax, 'off');
    end
end
localStyleAxes(ax, fontName, c, '记录时间 / s', '太阳能功率 / W');
end

function localPlotEnergy(ax, data, fontName, c)
cla(ax, 'reset');
localStyleAxes(ax, fontName, c, '记录时间 / s', '累计太阳能输出能量 / Wh');
valid = isfinite(data.Time_s) & isfinite(data.Energy_Wh);
if ~any(valid)
    localEmptyAxes(ax, '此文件无 SolarInDay_Wh 数据', fontName, c);
    return;
end
x = data.Time_s(valid);
y = data.Energy_Wh(valid);
lineHandle = plot(ax, x, y, '-', 'Color', c.green, 'LineWidth', 1.9);
localFitLimits(ax, x, y);
lineHandle.DataTipTemplate.DataTipRows = [ ...
    dataTipTextRow('记录时间 / s', x), dataTipTextRow('累计能量 / Wh', y)];
localStyleAxes(ax, fontName, c, '记录时间 / s', '累计太阳能输出能量 / Wh');
end

function localStyleAxes(ax, fontName, c, xLabelText, yLabelText)
ax.FontName = fontName;
ax.FontSize = 11;
ax.XColor = c.axis;
ax.YColor = c.axis;
ax.GridColor = c.grid;
ax.MinorGridColor = c.grid;
ax.GridAlpha = 0.38;
ax.MinorGridAlpha = 0.18;
ax.LineWidth = 0.8;
ax.Box = 'off';
ax.Color = c.surface;
ax.XTickMode = 'auto';
ax.YTickMode = 'auto';
xlabel(ax, xLabelText, 'FontName', fontName, 'Color', c.axis);
ylabel(ax, yLabelText, 'FontName', fontName, 'Color', c.axis);
ax.XGrid = 'on';
ax.YGrid = 'on';
end

function localFitLimits(ax, x, y)
if min(x) == max(x)
    dx = max(1, abs(x(1)) * 0.05);
    ax.XLim = [x(1)-dx, x(1)+dx];
else
    dx = max(1, 0.025 * (max(x)-min(x)));
    ax.XLim = [min(x)-dx, max(x)+dx];
end
if min(y) == max(y)
    dy = max(0.1, abs(y(1)) * 0.05);
else
    dy = max(0.1, 0.08 * (max(y)-min(y)));
end
ax.YLim = [min(y)-dy, max(y)+dy];
end

function localEmptyAxes(ax, message, fontName, c)
ax.XLim = [0 1];
ax.YLim = [0 1];
ax.XTick = [];
ax.YTick = [];
text(ax, 0.5, 0.5, message, 'Units', 'normalized', ...
    'FontName', fontName, 'FontSize', 12, 'Color', c.muted, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
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
