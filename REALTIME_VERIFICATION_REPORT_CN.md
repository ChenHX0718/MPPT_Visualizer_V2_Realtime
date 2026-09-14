# MPPT 可视化软件 V2 实时验证报告

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
