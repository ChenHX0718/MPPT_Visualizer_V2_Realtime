# MPPT 可视化软件 V2：历史 / 实时串口 / Replay

本版本在 V1 历史日志仪表盘基础上增加实时 MPPT 串口读取和模拟 Replay。历史文件、串口和 Replay 共用 `+mppt/parseTelemetryLine.m` 与 `+mppt/processMPPTData.m`，不会修改 MPPT 固件，也不会向设备发送命令。

## 打开软件

在 MATLAB 中将当前文件夹切换到本目录，运行：

```matlab
MPPT_Visualizer
```

程序启动时会尝试显示上一级目录中的样例 `.txt` / `.log` 文件；也可以用顶部按钮选择其他日志。

## 三种模式

### 历史文件

选择“历史文件”，点击“打开文件”，选择 `.txt` 或 `.log`。程序逐行解析带 `#` 前缀的 JSON，自动跳过空行、串口提示、非 JSON 行和坏 JSON，并显示太阳能板电压、太阳能电流、实时功率、累计 Wh、累计 mAh 和 Error Flag。

### 模拟实时 / Replay

1. 选择“模拟实时”。
2. 点击“选择日志”，选择已有历史 `.txt` 或 `.log`。
3. 选择 `1x`、`5x` 或 `10x`。
4. 点击“开始”；每次 timer tick 只送入一行，解析、缓存、状态更新和实时曲线与真实串口共用。
5. 点击“停止”可中断，之后可以再次开始。

Replay 与实时串口共用顶部“显示时间范围”：最近60、300、500、1800、3600秒、本次全部记录和自定义正数秒；默认最近500秒。窗口只改变上方两张图，原始历史文件不会被修改。

### 实时串口

1. MPPT 连接 USB 串口。
2. 关闭串口助手等可能占用 COM 的软件。
3. 打开 MATLAB 并运行 `MPPT_Visualizer`。
4. 选择“实时串口”。
5. 点击“刷新”，选择 MPPT 对应的 COM 口。
6. 确认波特率：默认 `115200`。
7. 点击“连接”。
8. 查看实时数据、有效/坏数据计数和实时曲线。
9. 使用完毕点击“断开”。

程序使用 MATLAB 原生 `serialport`、`serialportlist("available")`、`configureTerminator(...,"LF")` 和 `configureCallback(...,"terminator",...)`。收到完整行后会调用共用解析器；坏行只增加坏数据计数，不会使 GUI 退出。

串口原始行会保存到：

```text
realtime_logs\MPPT_YYYYMMDD_HHMMSS.log
```

日志文件包含接收到的原始行，关闭或断开时自动关闭文件。关闭窗口时会停止 callback、释放串口、关闭日志和 Replay timer。

## 数据协议

参考 `LinHan2/MPPT` 的 `v21.0-branch/monitor_realtime.py`：串口为 `/dev/ttyUSB0` 示例，波特率 `115200`，通常约 1 Hz；每条数据是一行可选 `#` 前缀的 ThingSet JSON 对象，例如：

```text
# {"Uptime_s":151,"Bat_V":24.16,"Bat_A":7.54,"SOC_pct":97,"ChgState":0,"DCDCState":1,"Solar_V":42.12,"Solar_A":-4.34,"Load_A":0.03,"LoadBus_V":24.16,"ErrorFlags":0,"SolarInDay_Wh":1.62}
```

重点字段包括 `Uptime_s`、`Bat_V`、`Bat_A`、`Solar_V`、`Solar_A`、`Load_A`、`LoadBus_V`、`SOC_pct`、`ChgState`、`DCDCState`、`ErrorFlags` 和 `SolarInDay_Wh`。`Solar_A_raw` 保留原始符号；根据多个有效样本判断方向后生成 `Solar_A_generation`，再计算 `SolarPower_W = Solar_V × Solar_A_generation`。界面上的 `Energy_Wh` 和 `Capacity_mAh` 均从当前数据序列的有效功率/电流按 `Uptime_s` 进行梯形积分，设备原始 `SolarInDay_Wh` 不会被带入新的实时采集。

## 文件结构

- `MPPT_Visualizer.m`：三模式 GUI、串口 callback、Replay timer、资源释放。
- `+mppt/parseTelemetryLine.m`：历史/实时共用的单行 JSON 解析器。
- `+mppt/parseHistoryLog.m`：逐行历史文件读取，调用共用解析器。
- `+mppt/realtimeBuffer.m`：本次完整记录缓存和多样本 Solar_A 符号锁定；不再按显示点数截断。
- `+mppt/processMPPTData.m`：历史/实时共用数据标准化、功率、Wh 和 mAh 计算。
- `+mppt/loadHistoryFile.m`、`calculateMetrics.m`、`formatMPPTState.m`：历史入口、指标和状态显示。
- `realtime_logs/`：实时串口原始日志输出目录。
- `tests/run_mppt_tests.m`：V1 历史回归测试。
- `tests/run_realtime_tests.m`：Replay、坏数据、滚动缓存、日志回读测试。

## MATLAB 测试

在 MATLAB 中运行：

```matlab
addpath(genpath(pwd));
run_mppt_tests
run_realtime_tests
run_time_window_tests
```

没有实体 MPPT 硬件时，使用 Replay 完成软件测试。真实串口测试必须在 MPPT 设备实际连接且 COM 口未被其他程序占用时进行。

## 2026-10-06：时间轴与显示范围

时间零点保存在 `state.buffer.sessionStartUptime_s`，第一条有效板端时间只初始化一次。正常记录的相对秒数为 `double(Uptime_s)-double(sessionStartUptime_s)`，取窗、重新绘图和范围切换不会重置零点。实时缓存保留本次全部记录，无固定点数/时长上限，实际受电脑内存限制；尚未进行超长记录压力测试。

顶部范围共同控制电池电压、太阳能功率。按最新有效记录的时间 `t_end`，用同一个逻辑索引选择 `max(0,t_end-T) <= Time_s <= t_end`；窗口不会重新从0开始。下方累计能量始终显示整次记录，Wh和mAh不随窗口改变。历史文件模式忽略此控件，保留完整历史展示。自定义为空、非数值、非正数、NaN、Inf或复数时，提示并恢复上次有效值。

保留原有功率公式、电流方向规则及梯形积分方法；只修正时间可靠性：重复秒记录保留、dt=0，不重复积分；缺失/无效时间标记NaN，不推算、不跨越积分；超过10秒的缺口显示断线并跳过该间隔积分，累计值不代表缺口内真实产能。这个保守缺口阈值在 `+mppt/recordTime.m` 中集中定义，并非把遥测强制当成1Hz。

一旦时间倒退，无法仅凭这些字段区分复位、乱序或回绕：暂停本次记录的时间定位及积分，保留此前曲线、累计值及全部原始行，状态区提示。用户主动“清空曲线”后，下一条可靠Uptime_s作为新记录零点；原始日志不中断。沿用原操作语义：连接（含重新连接）、Replay开始、切换模式会开始新记录；断开本身保留曲线。重新连接不被当成已证明板子复位。

只有接收到有效串口记录后，界面才按电脑回调接收时刻显示接收频率估计。波特率、GUI刷新、内部测量频率与有效遥测记录频率是不同概念。参考源码、已有日志和本次实板观察的具体证据见 `REALTIME_VERIFICATION_REPORT_CN.md` 最后章节。
