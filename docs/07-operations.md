# 07 · 运维：日志、回退、事故预案

## 日志（全在 head `/home/<user>/logs/`，按标签 `TAG` 组织）

| 文件 | 内容 |
|---|---|
| `v24-launch-<TAG>.log` | 起服发射回执 |
| `v24-chain-<TAG>.log` | chain_boot 全过程（check8 / 八台发射 / BOOT 里程碑） |
| `v24-rb-<TAG>.log` | BOOT_READY / BOOT_FAILED / BOOT_TIMEOUT / CLK_GATE_FAIL 终态行 |
| `v24-serve-<TAG>.log` | 服务进程侧 |
| `ctn-<TAG>.log` | 容器 stdout（ARMED 行、调度器异常都在这里 grep） |
| `sd-<TAG>-formal.log` | tp8_after.sh 起服后检查与暖机 |

## 计划内换配置 / 换镜像

1. 改 `tp8-prod.conf`（`IMAGE=` 或 `CHAIN_ARGS`）并在本文档末尾变更记录表记一行；
2. 新镜像先八台各自构建好（不覆盖旧 tag）；
3. `FORCE=1 bash scripts/tp8/tp8_up.sh <标签>`——会断开所有在途会话，挑空窗执行；
4. 全量验证（[06](06-verification.md)）通过才算切完；不过就回退 conf 重起。

## 回退

- **换回旧镜像**：conf 的 `IMAGE=` 改回上一记录（`canary-roce-y` → `-z` → `-z2` 现役），`FORCE=1` 重起；
- **去掉某开关**：从 `CHAIN_ARGS` 删除对应行重起；去掉 `HICACHE_LOCAL_REPLICA` 前先想清楚（回到 rank0 独写模式需要共享存储假设）；
- **KV 缓存**：清 `/state/hicache` = 放弃全部前缀缓存（冷读回回退到全量重算），非必要不清。

## 事故预案

### 单台掉线 → 全集群倒

TP 集合通信下，任何一台宿主重启/断网，其余七台秒级报 `Connection closed by peer`、容器全部退出。**这是设计行为**。恢复 = 修好那台后直接走 `tp8_up.sh` 全量起服（不要试图单台拉起）。

排查顺序：各台 `uptime` / `last -x` / `journalctl -b -1`，确认是人为重启、掉电还是 panic，再起服。

### 宿主内存耗尽 wedge

现象：SSH 卡死、docker 无响应。预防已在哨兵（绝对下限 1024MB 先杀容器）；真 wedge 了只能硬复位该台，复位后该台回到「三件运行时状态丢失」态，由 `tp8_up.sh` 第 3/4/5 步补回。

### 起服失败三分支

- `CLK_GATE_FAIL`：锁频没就位——查 `gb10-clock-cap`；
- `BOOT_FAILED`：容器起不起来——看 `ctn-<TAG>.log` 尾部（多为参数/权重路径/镜像不一致）；
- `BOOT_TIMEOUT`：八台里有台慢——比对其容器进度，多数是镜像/缓存 IO 慢，等或修 IO。

### 实录一（单台 grub + 重启带倒八台）

有人在单台上改 grub（`lockdown=none module.sig_enforce=0`）并 `reboot`：该台干净重启，其余七台 gloo 全断，八台容器全退，集群掉线 28 分钟。教训：**TP 集群里没有「只动一台」这种操作**；grub/内核参数必须八台一致且经变更评审。

### 实录二（长会话步间停顿）

长会话（73 万 token）每步收尾停 1.6–2.2s、首 token 涨到 5s。py-spy 定位为 HiCache 回写缓冲模式的平方级重复入队（上游已修），回移修复后：收尾 2.339s → **0.068s**，首 token 5.36 → **3.04s**。方法论：`py-spy record --nonblocking` 在负载下会卡死，改用一次性快照循环采样再离线分析。

### 实录三（噪音排障）

机柜出现「发动机式」持续轰鸣，随负载/温度出现。单台逐台满载压测（临时容器跑 matmul，每台 30–120s）八台全部清白 → 定案为**密闭房间环境温度爬升导致八台风扇长时间全速**的机柜级现象，开空调自愈。教训：多台同构风扇的叠加噪音是机柜级声学现象，单台压测全清白不代表有问题；先查环境温度与负载形态（脉冲 vs 数小时稳态）。

## 变更记录（示例格式）

| 日期 | 变更 |
|---|---|
| 2026-10-25 | 起服路径固化为 `tp8_up.sh` 体系；现役 = z2 镜像 + 15 开关；BOOT_READY 12 分钟，暖机过线，健康 200 |
| 2026-10-24 | HiCache 本地副本（z2）：冷读回 19.3 万 token 33.6s → 1.07s |
| 2026-10-23 | 八台锁 2200 MHz（接受 prefill −2–3%）；1M 窗 / 输出 100k / 并发 8 / KV 8M |
