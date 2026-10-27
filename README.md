# DGX Spark + 超聚变 GB10 ×8 · DeepSeek-V4.1-Flash-1017 · SGLang TP8

在 **8 台 NVIDIA GB10 机器**（4×DGX Spark + 4×超聚变 GB10）上，用 SGLang **TP8 / EP8** 跑 **DeepSeek-V4.1-Flash-1017**：上下文窗口 **1,000,000**、最大输出 **100,000**、并发 **8**、KV 池 **8,000,256** token。

本仓库是 **0 到 1 的部署手册 + 固定起服链 + 内存哨兵**，不是上游启动器的复刻。引擎底座沿用 [knapcio/DeepSeek-V4.1-Flash-4x-DGX-Spark-TP4](https://github.com/knapcio/DeepSeek-V4.1-Flash-4x-DGX-Spark-TP4) 的镜像构建思路（v2.2 起），在 8 机 TP8 形态下自建镜像与起服链。

> **2026-10-27**：本仓库从 **TP4 四机方案整包换为现役 TP8 八机方案**。TP4 时代的 13 篇文档与 TP4 专用脚本已删除（git 历史可查）。内存哨兵 `scripts/memguard/` 仍是现役组件，原样保留。

---

## 现役数字（2026-10-25 起服日志，A 级实测）

| 项 | 值 |
|---|---|
| 服务入口 | `http://<head-mgmt>:8888/v1` |
| 模型名 | `deepseek-v4.1-flash-1017-unc` |
| 引擎 | SGLang（自建镜像 `dsv41-4x-spark:canary-roce-z2`） |
| 上下文 / 输出 / 并发 | `CONTEXT_LENGTH=1000000` / `DSV41_MAX_NEW_TOKENS=100000` / `MAX_RUNNING_REQUESTS=8` |
| KV 池 | `MAX_TOTAL_TOKENS=8000256`（8 个满窗会话） |
| 冷 prefill（实测中位） | 131k：6,542 tok/s · 262k：6,511 · 524k：5,834 |
| 代码补全 C1 | 203 tok/s（512 上下文口径） |
| 长会话解码 | 73 万 token 上下文下 119 tok/s |
| 锁频 | 八台 GPU 全核 2200 MHz（`gb10-clock-cap` 服务） |
| 起服耗时 | 约 9 分钟到 BOOT_READY，15 分钟含暖机 |

## 目录

| 文档 | 内容 |
|---|---|
| [docs/01-hardware-topology.md](docs/01-hardware-topology.md) | 8 台 GB10、RoCE 网络与地址规划模板 |
| [docs/02-host-preparation.md](docs/02-host-preparation.md) | 宿主准备：内存哨兵、CPU 深睡眠态、GPU 锁频 |
| [docs/03-image-and-model.md](docs/03-image-and-model.md) | 镜像构成与模型权重 |
| [docs/04-env-and-parameters.md](docs/04-env-and-parameters.md) | 引擎环境底版与 15 个启动开关详解 |
| [docs/05-boot-pipeline.md](docs/05-boot-pipeline.md) | 固定起服链 `tp8_up.sh` 九步与单编排者协议 |
| [docs/06-verification.md](docs/06-verification.md) | 起服后检查：ARMED、暖机、健康、压测档 |
| [docs/07-operations.md](docs/07-operations.md) | 运维：日志、回退、事故预案（含实录两则） |

脚本：`scripts/`（起服链、后检查、独占/密管工具、内存哨兵）。

## 三条铁律（细节在分册，先立此照）

1. **TP 必须八台同起同停**。任何对单台宿主的重启 / grub 修改都会带倒整个集群（TP 集合通信对端全断）。绝不轮询 wedge 节点、绝不单台起服。
2. **宿主重启后有三件运行时状态不会自己回来**：内存哨兵、CPU 深睡眠态关闭、（DGX 侧的）钟锁——固定起服链的第 3、4、5 步专门补这三件，缺一不起服。
3. **sudo 密码只走 stdin、密钥只进密管**。任何部署脚本不得把凭据放进 argv、环境文件或仓库。

## LICENSE / NOTICE

见 [LICENSE](LICENSE) 与 [NOTICE.md](NOTICE.md)。文档内容按原许可证发布；上游 knapcio 启动器与 SGLang 分别遵循其各自许可证。
