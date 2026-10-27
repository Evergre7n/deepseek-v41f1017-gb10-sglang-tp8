# Changelog

## 2026-10-27 — 整包换成 TP8 八机方案（现役）

- 集群：**8×GB10**（4 DGX Spark + 4 超聚变），SGLang **TP8/EP8**，八台锁 2200 MHz。
- 模型：**deepseek-v4.1-flash-1017-unc**；窗 **1,000,000** / 输出 **100,000** / 并发 **8** / KV **8,000,256**。
- 固定起服链 `scripts/tp8_up.sh` 九步（哨兵/深睡眠态/锁频核查失败即停）+ 独占声明协议 + `tp8_after.sh` 后检查暖机。
- 镜像 `dsv41-4x-spark:canary-roce-z2`：公平分块 / chat 分词卸载 / HiCache 去重+偏移插入+节点本地副本。
- 读数：冷 prefill 131k 6,542 / 262k 6,511 / 524k 5,834；代码 C1 203；73 万上下文解码 119 tok/s。
- **删除 TP4 四机时代的 13 篇文档与 TP4 专用脚本**（git 历史可查）；`memguard/` 保留并脱敏。
- 全仓库脱敏：内网地址/主机名/用户名一律换文档示例段（10.99.0.x / 192.0.2.x / deploy）。

## 2026-09-29 — 整包换成 knapcio v2.2

- 现役引擎：**SGLang**（knapcio `e9ec61d2`），不再是 vLLM `aidendle94/sparkrun-vllm-dsv41-gb10`。
- 窗：**600000 总长**；客户端示例 500000 / 100000。
- 并发 **4**，KV 钉 **2500000**（0.80 比例封顶，实测池约 2.15M–2.50M）。
- 增加本机修复：PDI=1、切块串行、SSE keepalive。
- 删除默认路径上的 `scripts/v41-tuned-tp4.sh` 与 `patch/`（Tony 七补丁）。需要旧配方请翻本仓 2026-09-14 提交。

## 2026-09-14 — vLLM 第一方配方（已归档）

Tony 七补丁 + joe mp 组法 + vLLM official recipe。窗 720896。见该日提交。
