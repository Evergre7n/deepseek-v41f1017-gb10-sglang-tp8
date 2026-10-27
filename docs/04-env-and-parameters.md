# 04 · 环境底版与启动开关

## 环境底版（head 上一个 env 文件，示例 `env/clean-best3.env.example`）

| 键 | 值 | 说明 |
|---|---|---|
| `CONTEXT_LENGTH` | `1000000` | 引擎总窗 |
| `DSV41_MAX_NEW_TOKENS` | `100000` | 单请求输出帽 |
| `MAX_RUNNING_REQUESTS` | `8` | 并发；与 KV 池对齐（8M ÷ 1M = 8 个满窗会话） |
| `MAX_TOTAL_TOKENS` | `8000256` | KV 池钉值 |
| `MEM_FRACTION_STATIC` | `0.80` | 起服时再按实际内存封顶 |
| `GLOO_SOCKET_IFNAME` | `<roce-if>` | 集合通信钉 RoCE 口 |
| `EXTRA_SGLANG_ARGS` | `--image-processor-backend pil --prefill-decode-interval 1 …` | 必带启动项追加 |

## 起服开关（`tp8-prod.conf` 的 `CHAIN_ARGS`，X: 前缀 = 容器环境变量）

| 开关 | 作用 |
|---|---|
| `DSV41_WO_A_TP8=1` | TP8 形态下的权重装载路径 |
| `DSV41_VERIFY_CAP_BS=3-16:0.2` | CUDA graph decode bs 档校验（3–16，步进 0.2 档宽） |
| `DSV41_SHARED_PAD_K_SRC=288` | 共享专家 K padding 源宽（5120,288→(5120,384) 形状对齐） |
| `DSV41_PREFILL_WOB_A2A=1` | prefill 权重外 bundling，免跨机 A2A |
| `DSV41_PREFILL_QKV_LOCAL=1` | QKV 投影本地化 |
| `DSV41_PREFILL_SKIP_NONFINAL=1` | 非末块跳过晚层（末块隐状态逐位一致，prefill +7%） |
| `DSV41_PREFILL_EMBED_LOCAL=1` | 词嵌入整表本地查（逐位一致） |
| `DSV41_PREFILL_SHARED_SHARD=1` | 共享专家整块算在分片上再回散（+3–5%，down 段 fp32 误差减半） |
| `DSV41_PREFILL_SP_ALIGN=1` | 末块对齐到 SP（131k 档 +3.7%） |
| `DSV41_PREFILL_FAIR=1` | 公平分块：有解码在跑时 prefill 每块 ≤3072 行、块间 ≥6 解码步（深前缀后 ≥2048 行）——多路长冷 prefill 不堵其他路解码的关键 |
| `DSV41_CHAT_ENCODE_OFFLOAD=1` | chat 套模板与分词挪出 HTTP 事件循环（防长请求进门卡住所有流） |
| `SGLANG_ENABLE_HEALTH_ENDPOINT_GENERATION=0` | /health 不再跑一次生成（1s → 1ms） |
| `DSV41_HICACHE_WALK_DEDUPE=1` | HiCache 回写去重（上游已修的平方级重复入队，回移） |
| `DSV41_RADIX_OFFSET_INSERT=1` | radix 偏移量插入（配合去重） |
| `DSV41_HICACHE_LOCAL_REPLICA=1` | HiCache 节点本地副本（每台写自己的 NVMe） |

## 调优方法论（为什么是这 15 个）

1. **逐项验收，不留「据说有用」**：每个开关进现役前都有同 boot A/B 读数；逐位一致性开关（SKIP_NONFINAL/EMBED_LOCAL）必须证明输出逐位相同。
2. **试过不要的也记账**：NCCL 512K×4（−4~9%）、MoE 两半流水（无差）、EP8 分发（净收益估 0–3% 不值得）、DGX 解锁（0–1%）、套接字忙轮询（略负）——回退候选时不用重试。
3. **公平分块是护栏型改动**：它把「长 prefill 堵死所有解码流」（262k prefill 期间其他路掉到 4 tok/s、>1s 停顿 30 次）变成「prefill 稍慢、解码 12–14 tok/s 无 >1s 停顿」。任何自带分块假设的适配器叠加都可能破坏「本步预算用尽」不变式，需配分块护栏（`prefill_chunk_guard`）。
4. 解码两条硬线（散文 C1 120 / C4 300）：每步几乎全是 GPU 时间、MoE 贴带宽、C4 受 100G 收端丢包限制——软件侧已无可捡，不要再耗。
