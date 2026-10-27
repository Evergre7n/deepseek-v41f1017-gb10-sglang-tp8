# 02 · 宿主准备（三件运行时状态 + 一件开机自启）

宿主重启会丢三件运行时状态；固定起服链（[05-boot-pipeline.md](05-boot-pipeline.md)）每轮起服前自动补，但首次部署要手动做一遍并理解每件的作用。

## 1. 内存哨兵（绝对下限 1024 MB）

GB10 是 CPU/GPU 一致性内存，推理引擎把宿主可用内存吃穿时会 wedge 整机（只能硬复位）。哨兵两个进程：

- `sentinel_keeper.sh`：保证 watcher 常驻；
- `v41-mg-load.sh __watch dsv41-tp8`：盯容器内存水位，低于绝对下限先杀容器保宿主（**丢会话好过丢机器**）。

安装/恢复：head 的工具目录里有 `fix_sentinel_host.sh`（内部封装 [scripts/memguard/](../scripts/memguard/) 的 keeper/watcher），每台跑一次；验证标准：

```
keeper=$(pgrep -f "[s]entinel_keeper.sh" | wc -l)   # 必须 =1
watcher=$(pgrep -f "[v]41-mg-load.sh __watch dsv41-tp8" | wc -l)  # 必须 =1
```

**任何一台挂不上哨兵就不允许起服**（起服链会硬性拦截）。宿主重启后 keeper/watcher 归零，必须重挂。

## 2. CPU 深睡眠态关闭

C-state 深睡眠（state2/state3）进出延迟会拖累集合通信与调度抖动，八台全部关闭（需要 root）：

```bash
for f in /sys/devices/system/cpu/cpu*/cpuidle/state2/disable \
         /sys/devices/system/cpu/cpu*/cpuidle/state3/disable; do echo 1 > $f; done
```

验证：`cat /sys/devices/system/cpu/cpu0/cpuidle/state3/disable` 必须 `1`。运行时状态，**宿主重启后复原**。

## 3. GPU 锁频 2200 MHz（`gb10-clock-cap.service`）

八台装一个开机自启的小服务，把 SM 时钟钉在 2200 MHz。收益是**稳定性与延迟方差**（高波动的瞬时提频会让 TP 集合通信互相等）；代价约 2–3% prefill 吞吐。是否锁频可自选，但**八台必须一致**——部分锁频会让快的那几台在 all-reduce 上空等。

- 超聚变机器：systemd 服务 `gb10-clock-cap`，`systemctl enable --now`；
- DGX Spark：同样以服务方式落锁（开机自启），重启后自动恢复。

验证：`systemctl is-active gb10-clock-cap` 八台全部 `active`；`nvidia-smi --query-gpu=clocks.sm --format=csv,noheader` 满载时稳定在 2184–2190 MHz。

## 4. Docker 与镜像

每台本地各自构建/导入镜像（**不要**起一个共享 registry——起服时八台并发拉取会被 registry 限速卡死）。验证：`docker images -q <image> | wc -l` = 1。

## 5. 首次部署核对清单

- [ ] 八台 SSH 互信（head→各台 RoCE IP，`BatchMode=yes` 可达）
- [ ] 各台 `/proc/uptime` 正常、时间同步
- [ ] 哨兵 keeper/watcher 各 1（八台）
- [ ] 深睡眠态 state3.disable 全 1（八台）
- [ ] `gb10-clock-cap` 八台 active
- [ ] 镜像八台各自在位
