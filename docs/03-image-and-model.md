# 03 · 镜像与模型

## 镜像 `dsv41-4x-spark:canary-roce-z2`

自建镜像 = 上游 SGLang DSV41 开发镜像 + 本地补丁层。八台各自本地构建（同名 tag），起服前置核查会验证八台都在位。

| 层 | 内容 | 作用 |
|---|---|---|
| 基底 | `lmsysorg/sglang` 的 DeepSeek-V4.1 开发镜像（记录 digest 固定） | 引擎本体 |
| +y 系列 | 公平分块 `prefill_fair_chunk`、chat 模板分词卸载 `chat_encode_offload`、健康检查不跑生成 | 长 prefill 不堵解码 |
| +z 系列 | HiCache 回写去重 `hicache_walk_dedupe`、radix 偏移量插入 `radix_offset_insert` | 消除回写平方级重复入队 |
| +z2 | HiCache 节点本地副本 `hicache_local_replica` | MLA 只让 rank0 写盘的上游假定不适用于节点本地盘；本地副本后冷读回 19.3 万 token 33.6s → 1.07s |

镜像历史（回退路径）：`canary-roce-y`（只有公平分块）→ `-z`（+去重 +偏移）→ `-z2`（+本地副本，现役）。构建纪律：**不覆盖旧 tag**，新变体新 tag，回退 = 改 conf 里的 `IMAGE=`。

## 模型权重

- 模型：**DeepSeek-V4.1-Flash-1017**（本部署跑的权重文件名带 `-unc` 后缀，模型 id 亦同）。
- 权重放每台本地盘同一路径，容器内同路径挂载。TP8 下八台各自读本地权重，不要放共享存储再并发挂载（起服 IO 风暴）。
- 授权与分发遵循 DeepSeek 官方模型许可；本仓库不含权重。

## HiCache（节点本地 NVMe KV 缓存）

- 后端：file，落在每台本机 NVMe（`/state/hicache`，head 为 `state-tp4` 目录名），容器挂载点 `/state`。
- 每台上限 `SGLANG_HICACHE_FILE_BACKEND_MAX_SIZE=100G`，水位 0.90 触发淘汰（淘汰器按 LRU 收到目标线）。
- 现实容量感受：8M token 池写满每台约 13.4 GB；长期运行后缓存文件 21–25 万个 / 约 90 GB 属正常，回收器会自己维持余量。
- 缓存目录**跨起服保留**（这是冷读回加速的前提），清空 = 放弃全部前缀缓存。

## 引擎上游代码

SGLang 引擎代码带 DSV41 支持分支（上游 commit 固定记录在起服配置；换上游 commit = 重建镜像 = 新 tag）。升级流程：新 commit 构建 → md5 冒烟 → 同配置起服 → 全量压测档（见 [06-verification.md](06-verification.md)）→ 通过才切现役。
