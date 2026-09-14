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

Replay 使用最近 500 个有效采样点作为滚动曲线缓存；原始历史文件不会被修改。

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
- `+mppt/realtimeBuffer.m`：固定长度滚动缓存和多样本 Solar_A 符号锁定。
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
```

没有实体 MPPT 硬件时，使用 Replay 完成软件测试。真实串口测试必须在 MPPT 设备实际连接且 COM 口未被其他程序占用时进行。
