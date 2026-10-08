# MPPT 可视化软件 V2：历史 / 实时串口 / UDP / Replay

本版本在 V1 历史日志仪表盘基础上增加实时 MPPT 串口读取和模拟 Replay。历史文件、串口和 Replay 共用 `+mppt/parseTelemetryLine.m` 与 `+mppt/processMPPTData.m`，不会修改 MPPT 固件，也不会向设备发送命令。

## 打开软件

在 MATLAB 中将当前文件夹切换到本目录，运行：

```matlab
MPPT_Visualizer
```

程序启动时会尝试显示上一级目录中的样例 `.txt` / `.log` 文件；也可以用顶部按钮选择其他日志。

## 四种模式

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

程序使用 MATLAB 原生 `serialport`，默认115200、8N1、无流控。唯一接收 timer 每0.1秒按当前可用字节数读取，再明确转换为 `uint8`；没有换行回调或阻塞等待完整记录。旧 ThingSet 文本和新 MAVLink 2 MPPT 均自动识别，无需切换协议。Sys / Comp 设置为0表示自动识别，也可指定源ID（当前固件1 / 158）。

串口原始行会保存到：

```text
realtime_logs\MPPT_YYYYMMDD_HHMMSS.log
```

旧文本的完整原始行继续记录；MAVLink只记录通过完整性验证、去重和时序检查后的原始 ThingSet 行，保留UTF-8和LF/CRLF字节，不保存MAVLink二进制。已识别MAVLink后，不能识别的尾部噪声不作为旧文本写入日志。关闭或断开会释放串口/UDP、接收timer、重组缓存和日志；Replay timer也会在关闭窗口时释放。

### R30 UDP

1. 选择“实时UDP”。
2. “本机监听端口”默认 **14552**，可在同一连接区修改；绑定 `0.0.0.0`，监听所有本地IPv4网卡。
3. R30应把UDP数据发往本机可达IPv4地址及该端口；本程序不修改R30配置，也不发送任何网络请求或设备命令。
4. 点击“监听”，收到完整有效MPPT记录后自动显示协议和来源；用“断开”结束。

本机MATLAB R2024b的 `udpport('datagram',...)` 已通过实际本机回环测试。其他安装缺少udpport能力时，只影响UDP模式；原生串口模式不依赖Python或新增工具箱。一个数据报可包含多帧，一帧可跨数据报；缓冲按发送IP和端口隔离。第一份有效MPPT记录固定当前来源，同一会话不混合多块板子；重新连接重新选择来源。Sys / Comp的0表示自动，指定值可筛选所需板子。

状态区显示“等待识别 / ThingSet 文本 / MAVLink 2 MPPT”、连接与源sys/comp、最近有效记录距今多久、坏帧和重组超时。单独的HEARTBEAT只显示收到MAVLink并等待MPPT；超过3秒没有有效遥测显示超时。电流0或ChgState=IDLE不影响在线状态。

### 自动解码和时序

`+mppt/TelemetryReceiver.m`是串口和UDP共用的唯一字节分帧入口。MAVLink1/2按帧整体消费，TUNNEL(385)先验证实际传输字节的CRC_EXTRA=147，再补齐尾部零。私有类型32768、MPPT标记、24字节版本1分片头、104字节几何约束、1～2048字节记录长度及CRC32/ISO-HDLC全部通过后，才调用原有ThingSet解析器。实时有效记录须至少含有效Bat_V或Solar_V；历史和Replay继续沿用原有缺字段兼容判定。

重组按输入端点、sysid、compid、record_seq、boot_ms隔离，支持乱序及相同重复片；冲突、缺片和CRC错不更新采样或积分。接收timer在静默期间也清理超时。缓存容量、3秒超时和去重期限集中配置于接收器构造函数。未知消息CRC_EXTRA不猜测，按帧跳过；签名帧跳过。帧CRC错误中的JSON不会作为旧文本接收。协议由有效MPPT记录确定，允许同会话切换。

MAVLink的seq / boot回绕使用double的模2^32运算。晚完成的旧记录不会提交实时缓存。启动时间和序号同时倒退时，先暂存候选，收到连续的新启动记录后建立新的时钟段；旧文本则用连续倒退后递增的Uptime候选恢复。单条时间倒退不能证明重启，会被暂存/丢弃。新段保留原始Uptime_s及既有累计值，不跨重启间隔积分。boot_ms仅用于排序和重组，不是Unix时间。仅凭无启动代号的协议，连续旧记录与重启仍可能歧义；必要时“断开/连接”或“清空曲线”明确开始新会话。

### CSV

窗口右下“导出CSV”保存本次完整缓存或当前历史文件。导出包含所有接收字段（包括未来新增字段和完整ErrorFlags / LoadErrFlags），以及Time_s、SolarPower_W、Energy_Wh、Capacity_mAh。缺失字段留空；复杂字段以JSON保存。若原始字段与派生列同名，派生列加Computed_前缀，不覆盖原始字段。设备SolarInDay_Wh与本次Energy_Wh保持独立。

## 数据协议

参考 `LinHan2/MPPT` 的 `v21.0-branch/monitor_realtime.py`：串口为 `/dev/ttyUSB0` 示例，波特率 `115200`，通常约 1 Hz；每条数据是一行可选 `#` 前缀的 ThingSet JSON 对象，例如：

```text
# {"Uptime_s":151,"Bat_V":24.16,"Bat_A":7.54,"SOC_pct":97,"ChgState":0,"DCDCState":1,"Solar_V":42.12,"Solar_A":-4.34,"Load_A":0.03,"LoadBus_V":24.16,"ErrorFlags":0,"SolarInDay_Wh":1.62}
```

重点字段包括 `Uptime_s`、`Bat_V`、`Bat_A`、`Solar_V`、`Solar_A`、`Load_A`、`LoadBus_V`、`SOC_pct`、`ChgState`、`DCDCState`、`ErrorFlags` 和 `SolarInDay_Wh`。`Solar_A_raw` 保留原始符号；根据多个有效样本判断方向后生成 `Solar_A_generation`，再计算 `SolarPower_W = Solar_V × Solar_A_generation`。界面上的 `Energy_Wh` 和 `Capacity_mAh` 均从当前数据序列的有效功率/电流按 `Uptime_s` 进行梯形积分，设备原始 `SolarInDay_Wh` 不会被带入新的实时采集。

## 文件结构

- `MPPT_Visualizer.m`：四模式GUI、只读字节接收timer、UDP设置、Replay与资源释放。
- `+mppt/TelemetryReceiver.m`：统一分帧、协议识别、CRC验证、来源隔离、重组、去重与时序。
- `+mppt/mavlinkCRC.m`、`crc32.m`：外层MAVLink CRC与整条记录CRC32。
- `+mppt/exportCSV.m`：完整字段及本次派生数据CSV导出。
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
run_protocol_tests
run_transport_tests
run_replay_gui_tests
```

没有实体 MPPT 硬件时，使用 Replay 完成软件测试。真实串口测试必须在 MPPT 设备实际连接且 COM 口未被其他程序占用时进行。

## 2026-10-06：时间轴与显示范围

时间零点保存在 `state.buffer.sessionStartUptime_s`，第一条有效板端时间只初始化一次。正常记录的相对秒数为 `double(Uptime_s)-double(sessionStartUptime_s)`，取窗、重新绘图和范围切换不会重置零点。实时缓存保留本次全部记录，无固定点数/时长上限，实际受电脑内存限制；尚未进行超长记录压力测试。

顶部范围共同控制电池电压、太阳能功率。按最新有效记录的时间 `t_end`，用同一个逻辑索引选择 `max(0,t_end-T) <= Time_s <= t_end`；窗口不会重新从0开始。下方累计能量始终显示整次记录，Wh和mAh不随窗口改变。历史文件模式忽略此控件，保留完整历史展示。自定义为空、非数值、非正数、NaN、Inf或复数时，提示并恢复上次有效值。

保留原有功率公式、电流方向规则及梯形积分方法；只修正时间可靠性：重复秒记录保留、dt=0，不重复积分；缺失/无效时间标记NaN，不推算、不跨越积分；超过10秒的缺口显示断线并跳过该间隔积分，累计值不代表缺口内真实产能。这个保守缺口阈值在 `+mppt/recordTime.m` 中集中定义，并非把遥测强制当成1Hz。

一旦时间倒退，无法仅凭这些字段区分复位、乱序或回绕：暂停本次记录的时间定位及积分，保留此前曲线、累计值及全部原始行，状态区提示。用户主动“清空曲线”后，下一条可靠Uptime_s作为新记录零点；原始日志不中断。沿用原操作语义：连接（含重新连接）、Replay开始、切换模式会开始新记录；断开本身保留曲线。重新连接不被当成已证明板子复位。

只有接收到有效串口记录后，界面才按电脑回调接收时刻显示接收频率估计。波特率、GUI刷新、内部测量频率与有效遥测记录频率是不同概念。参考源码、已有日志和本次实板观察的具体证据见 `REALTIME_VERIFICATION_REPORT_CN.md` 最后章节。

## 2026-10-08：协议回归测试

新增三套测试直接调用生产接收器和GUI回调。`run_protocol_tests`覆盖独立C库参考字节、单字节/随机分块、LF/CRLF、UTF-8跨块跨片、104/105/2048边界、零尾裁剪、乱序/重复/冲突/超时、两层CRC、坏LEN恢复、MAVLink1/2其他消息、协议切换、来源隔离、重连、重启/回绕、迟到记录、负电流/完整32位标志、日志/CSV回读及积分一致性。`run_transport_tests`使用真实本机UDP套接字和GUI接收timer，验证跨数据报、端点隔离、三次连接/断开、静默超时、原始日志字节一致性和关闭释放端口。`run_replay_gui_tests`用临时文件选择器替身运行真实Replay回调和timer，验证三轮重播、停止、关闭及积分。测试自动清理自身临时样例和日志，不删除用户已有日志。这些是软件与本机回环验证，不代表实体串口或R30联调通过。
