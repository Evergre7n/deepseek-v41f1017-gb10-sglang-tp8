# 05 · 固定起服链 `tp8_up.sh` 与单编排者协议

## 用法（PC/管理机侧 Git Bash）

```bash
bash scripts/tp8/tp8_up.sh [标签]        # 服务没在跑时起服；标签默认 up<月日_时分>
FORCE=1 bash scripts/tp8/tp8_up.sh [标签] # 计划内强制换容器（会断开所有会话约 8–10 分钟）
```

配置真源 = `scripts/tp8/tp8-prod.conf`（镜像、八台 SSH 别名、CHAIN_ARGS）。**改 conf = 改现役配置**，须在运维文档记一笔。

## 九步（失败即停，绝不带病起服）

| 步 | 动作 | 失败处置 |
|---|---|---|
| 0 | 前置核查：八台 SSH 可达、各自本地有镜像、head 上无编排在跑、服务未在跑（FORCE 才继续） | ABORT |
| 1 | 写**独占声明** `/tmp/AB-CLAIM-*.txt`（单编排者协议，退出时自动释放） | ABORT |
| 2 | 并行停八台容器 `docker rm -f` | — |
| 3 | 逐台挂**内存哨兵**（`fix_sentinel_host.sh`），必须 keeper=1 watcher=1，缺则重试一次 | 八台不齐 → ABORT |
| 4 | 关 **CPU 深睡眠态**（sudo 经密管只走 stdin，八台 state3.disable 全 1） | 有 0 → ABORT |
| 5 | 核查 **锁频服务** `gb10-clock-cap` 八台 active | 不是全 active → ABORT |
| 6 | scp `tp8_after.sh` 上 head；发射 `chain_variant2.sh <标签>`（时钟闸门 → 拷底版 env → 追加参数 → `chain_boot.sh` 八台同起） | 发射失败 → ABORT |
| 7 | 轮询 `BOOT_READY`（最长 30 分钟，典型 9 分钟）；见 BOOT_FAILED/TIMEOUT/CLK_GATE_FAIL 即终 | 终态 → 排查三份日志 |
| 8 | head 上跑 `tp8_after.sh`（ARMED 核对、八台缓存/内存清点、暖机 42 万 token + 两路 524k 解码交错、健康双口） | err≥1 → PROBLEM |
| 9 | 汇总 + 对外口自检（`http://<head-mgmt>:8888/health` 200 与 SSH） | — |

## 单编排者独占协议

起服/重启前必须：

1. 查 head 上 `/tmp/AB-CLAIM-*.txt` 与 `pgrep -f "chain_variant2|chain_boot|boot_only"`——已有声明或起服进程 = **不开工**，先查清是谁在跑；
2. 自己开工时写 claim（含 pid/标签/时间），结束释放（脚本 trap 保证异常退出也释放）。

多人/多 agent 同时编排一台集群是事故之母。

## head 上的链内脚本（`/home/<user>/v24-tools/`）

| 脚本 | 职责 |
|---|---|
| `clk_gate.sh` | 时钟闸门：八台锁频核查，不过则写 CLK_GATE_FAIL |
| `chain_boot.sh` | `check8` 逐台核查并重挂哨兵 → **八台同起**（一个 docker run 并行发射）→ 等 BOOT_READY |
| `chain_variant2.sh` | 变体链包装：时钟闸门 → 拷底版 env → 追加 EXTRA_SGLANG_ARGS → chain_boot →（可选）依次跑压测档 |
| `tp8_after.sh` | 起服后检查与暖机（见 [06-verification.md](06-verification.md)） |
| `fix_sentinel_host.sh` | 重挂内存哨兵（封装 memguard） |

## sudo 与密钥

- 节点 root 操作（深睡眠态等）经 `sudo_out.py`：sudo 密码从本机密管（如 SOPS+age）解出，**只通过 stdin 递给 sudo `-S`**，不进 argv、不进环境变量、不打印；
- 仓库里永远只有密文与占位；密码文件在部署者本机密管内。
