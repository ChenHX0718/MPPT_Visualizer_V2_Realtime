# MPPT 可视化软件 V2 实时验证报告

> 下方旧章节保留为历史记录；最新行为与实测结果以文末“2026-10-06 时间轴、时间范围与布局验收”为准。

## 代码检查结论

- 保留 V1 的历史文件读取、功率和 Pmax 计算路径；累计 Wh 改为从当前数据序列重新起算。
- `SolarPower_W = Solar_V × Solar_A_generation`；Wh 与 mAh 均使用 `Uptime_s` 的实际时间间隔做梯形积分。
- `Capacity_mAh` 独立由 `Solar_A_generation` 积分得到，不通过 Wh 与电压反算。
- 历史文件和实时串口/Replay 都调用 `mppt.parseTelemetryLine`。
- 实时串口使用 MATLAB 原生 `serialport`，默认波特率 `115200`，按 `LF` terminator 配置 callback。
- GUI 不使用永久阻塞循环；实时接收由 `configureCallback` 驱动，Replay 由可停止的 `timer` 驱动。
- 实时曲线使用预创建的 line 对象更新 `XData` / `YData`，保留最近 500 点。
- 串口原始行保存到 `realtime_logs\MPPT_YYYYMMDD_HHMMSS.log`；断开和关闭窗口都会关闭 callback、串口、日志和 timer。

## 自动测试

已在 MATLAB R2024b 中从最终目录实际运行 `tests/run_mppt_tests.m` 和 `tests/run_realtime_tests.m`，结果为：

- 历史样例：274 条 JSON、1 条坏行；
- Pmax：197.6068 W，Pmax 电压：43.24 V，与 V1 一致；
- Replay 逐行处理：有效 274、跳过 1；
- 滚动缓存上限测试：10 点测试缓存正确截断；实际 GUI 缓存配置为 500 点；
- 数值验证：40 V、2 A 持续 3600 s 得到 80 Wh、2000 mAh；滚动窗口超过上限后累计值保持连续；
- 原始接收行写入临时日志后，历史入口回读：2 条有效、1 条跳过；
- 空行、半行 JSON、坏 JSON、非 JSON 文本、字段类型错误和字段缺失分支均通过；
- GUI 在 MATLAB R2024b 中启动并关闭通过；历史数据和无数据实时状态截图检查通过，六项状态、轴标签和刻度均可见且无裁剪。

## 实体设备状态

本次开发未宣称已经连接实体 MPPT。实体验证需要下一步将 MPPT USB 串口接入电脑，关闭其他串口软件，在 GUI 中刷新并选择 COM 口，确认 `115200` 后点击“连接”，观察有效计数、状态区和实时曲线；完成后点击“断开”并再次连接确认资源释放。


## 2026-10-06 时间轴、时间范围与布局验收

### 实际目录与修改边界

修改目录：`E:\可视化demo\MPPT_Visualizer_V2_Realtime`。测试前由 MATLAB `which('MPPT_Visualizer')` 断言等于该目录入口，实际使用 MATLAB R2024b (24.2.0.2712019)。Git 保持 main 分支；开始时已有 `?? realtime_logs/`，未覆盖已有日志。未创建工程副本/备份、未修改上游/驱动/固件、未切换分支、未暂存、提交或推送。

实际修改：

| 文件 | 主要函数与影响 |
| --- | --- |
| MPPT_Visualizer.m | onRangeChanged/onCustomRangeChanged/localRefreshRange：共用时间范围控件；localConsumeLine：保存完整显示快照和有效接收时刻；localRenderRealtime/localRenderHistory：按时间绘图并保留缺口；localMakeChartPanel/localStyleAxes：下方标题独立居中、边距及两行纵轴标签；localDisconnect：显式释放串口 |
| +mppt/realtimeBuffer.m | create/append/data/clear、localOverlaySessionTotals、localIntegrateSession：取消点数截断，保存会话零点、异常标记、全程累计量 |
| +mppt/processMPPTData.m | processMPPTData/localCumulativeIntegral：历史/实时共用可靠时钟，无效时间不以样本编号替代，积分不跨未知时间或大缺口 |
| +mppt/recordTime.m（新增） | 会话时间验证、固定零点、重复/缺失/倒退/大缺口保护 |
| +mppt/timeWindow.m（新增） | 统一的时间筛选索引、坐标边界和范围标题 |
| +mppt/plotSeries.m（新增） | 仅在显示层插入NaN断线符，原始数据、时间及累计量不变 |
| tests/run_realtime_tests.m | 将截断预期改为完整保留；一小时积分测试用完整1秒序列而非跨3600秒未知缺口 |
| tests/run_time_window_tests.m（新增） | 六组时间轴、取窗、异常与累计定量测试 |
| README_CN.md、本文 | 使用方法、记录规则和验证证据 |

已阅读且无需修改的实际调用链包括 `parseTelemetryLine.m`、`parseHistoryLog.m`、`loadHistoryFile.m`、`calculateMetrics.m`。主界面绘图是入口内的嵌套函数，本次未修改未被主界面调用的旧 `updateDashboard.m`。

### 三类时间证据（不得混同）

1. **参考源码**：只读核查 [data_nodes.cpp](https://github.com/LinHan2/MPPT/blob/v21.0-branch/src/data_nodes.cpp) 中Uptime_s绑定uint32 timestamp，注释明确为复位后时间；[setup.cpp](https://github.com/LinHan2/MPPT/blob/v21.0-branch/src/setup.cpp) 的timestamp_inc每1000 ms递增；[ext/serial.cpp](https://github.com/LinHan2/MPPT/blob/v21.0-branch/src/ext/serial.cpp) 按系统运行秒变化调用process_1s，自动发布开启时发送文本，标称约1Hz。内部控制/测量周期、GUI刷新和115200波特率不是有效遥测记录频率。
2. **已有实板日志**：`MPPT_20261006_105530.log`共66行，66行均解析有效，Uptime_s为5746～5811，65个相邻间隔全部1秒，无缺失、重复、倒退或大跳变。另两份非空日志各只有1行，Uptime分别为5006、5331；最早一份为空。各文件没有可靠电脑接收时刻，未用日志行数推算无线链路接收频率。
3. **本次只读实板观察**：COM4可用，115200、LF，打开成功，观察65.0888秒，收到原始行0、有效记录0、无效行0。N/观察时长为0条/秒，只能说明该观察窗口无数据，不能确认当前固件发布周期或连续接收频率，更不能称“实测1Hz”。没有到达记录，无法统计相邻Uptime、成批到达或链路中断分布。未发送任何数据/控制/配置命令。后续GUI串口打开测试也未获得遥测。

### 时间、保留和累计规则

- `state.buffer.clock.sessionStartUptime_s`及同名buffer字段保存首次有效Uptime_s。每条相对时间先转double再相减，范围切换仅读取`state.data`，不创建/清空缓存，不更新零点。
- 默认最近500秒；60/300/500/1800/3600秒、全部及自定义共用一个选择器。取窗条件为 `max(0,t_end-T) <= Time_s <= t_end`，电压和功率用同一逻辑索引；t_end为最后可靠板端记录。0～1200秒记录选500秒得到700～1200秒，共501条。稀疏与不均匀记录保持原位置。
- 保留本次全部records、Time_s及积分序列，不设置固定点数/时长上限。缩小后扩大能恢复较早记录。实际受系统内存/计算能力限制，未做全天或多日压力测试；没有降采样、插值或伪造补点。
- 原正常积分已经使用时间差；本次保留原功率、方向与非负梯形积分方法，删除缺失时间“加1秒”/“样本编号秒数”的回退，并禁止跨无效时间积分。重复秒仍保留，dt=0。超过10秒的大缺口保守跳过该间隔，显示断线和未覆盖提示；10秒为明确缺口规则，并非1Hz强制采样假设。
- 时间倒退无法仅凭Uptime确定复位/乱序/回绕，因而保留已有曲线和累计结果，后续记录Time_s=NaN、原始行继续保存，提示“清空曲线开始新记录”；不自动拼接、不产生负dt。清空后重新选首条可靠时间作为零点。
- 沿用原操作语义：主动连接/重连、Replay开始、模式切换会开始新记录；断开保留当前显示；“清空曲线”重置数据与累计，但保持接收和原始日志。只切范围不触发这些操作。重连并不证明复位。
- 下方图及左侧累计值始终为整次记录，不受显示窗口影响。历史模式禁用窗口控件，仍展示完整历史。
- 原始日志内容、位置、格式不变，`fflush(state.logFID)`继续为注释。接收频率仅在有效串口记录到达后按电脑回调时刻 `(N-1)/(末次-首次)` 估计，不能取代板端时间。

### 布局

保留现有两行图表容器；下方标题仍在独立顶部行，改为居中避开左侧纵轴；顶部行32px、行距10px，左右留白20px。纵轴保持16号字体，将物理量/Wh分两行以缩短旋转后的纵向占用；标题保持19号字。通过缩短标题行抵消新增间距，未明显压缩绘图区高度。活动模式工具条利用同一行空闲宽度，避免COM和连接按钮在缩放时挤压。

实际MATLAB `exportapp`截图检查：1400×800普通窗、1200×720缩放窗、最大化1536×802；下方标题/纵轴/刻度/横轴无重叠裁切。串口模式在1200×720下COM4、115200、连接、断开、清空曲线均可见。

### 测试结果与限制

- `run_mppt_tests`通过：历史274条有效、1条坏行；Pmax=197.6068W，峰值电压43.24V；缺字段与坏文件路径回归通过。
- `run_realtime_tests`通过：274条逐行Replay全部保留；40V×2A连续3600秒=80Wh、2000mAh；原始行临时日志回读2条有效、1条跳过。
- `run_time_window_tests`六组通过：非零起点/uint32、501条闭区间、2秒/不均匀/丢样/批量到达、空/单点/短记录、重复/缺失/倒退/复位/大缺口、缩小扩大和整次累计一致性。40V×2A连续1200秒=26.6666667Wh、666.6666667mAh。
- 实际GUI Replay使用上述66条实板历史日志，10x及5x真实timer运行至完成；1x先运行数个真实tick，再调用同一timer回调推进余下记录以缩短验收。三种速率最终Time_s、Wh、mAh完全相同，未将加速验收称为实板通过。
- GUI范围标题与曲线、恢复全程、自定义12.5秒，以及空值/0/负值/NaN/Inf/文字/复数恢复上次设置通过；零点、records与累计量不被显示操作改写。
- 串口生命周期复测通过：COM4实际打开；无数据时范围切换不变更串口句柄或日志；断开后端口可用；重连和关闭后释放通过。初次测试曾在外部仍持有句柄时发现端口未释放，已从仅清空引用改为显式delete串口，复测通过。
- 带实时数据的GUI串口验收在“至少收到3条有效记录”的断言处失败，原因是未收到数据。因此**未验证当前实板持续接收、带实板数据的在线切换、实板原始日志内容及稳定接收Hz**；不能用Replay代替这些硬件结论。
- MATLAB静态检查没有语法错误；保留已有未使用控件变量、datestr/now建议等非本任务提示。Git差异空白检查通过。

测试输出和实际截图保存在 `C:\Users\dell\Documents\ChatGPT\项目程序可视化`，未加入本工程Git。主要证据文件：`mppt_inspect_result.txt`、`mppt_gui_result.txt`（含实板无数据断言失败）、`mppt_observe_result.txt`、`mppt_replay_gui_result.txt`、`mppt_serial_lifecycle_result.txt`；截图`mppt_replay_300s.png`、`mppt_replay_60s_compact.png`、`mppt_replay_maximized.png`、`mppt_replay_all.png`、`mppt_serial_controls.png`。Replay截图来自实际运行，数据是已有实板日志回放；串口截图为已连接但未收到数据。

### 启动与复核

关闭旧监控窗口后，在MATLAB中运行（不改全局设置）：

```matlab
cd('E:\可视化demo\MPPT_Visualizer_V2_Realtime');
clear MPPT_Visualizer
which MPPT_Visualizer -all
MPPT_Visualizer
```

无硬件自动回归：`addpath(genpath(pwd)); run_mppt_tests; run_realtime_tests; run_time_window_tests`。请自行检查Git差异后提交/上传；本次未自动执行Git写操作。
