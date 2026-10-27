# 01 · 硬件与网络拓扑

## 机器清单

| 角色 | 数量 | 机型 | 说明 |
|---|---|---|---|
| head（编排 + 服务入口） | 1 | DGX Spark（GB10） | 另持一个固定的管理副地址，见下 |
| worker（DGX） | 3 | DGX Spark（GB10） | 与 head 同构 |
| worker（超聚变） | 4 | 超聚变 GB10 整机 | 与 DGX 混编进同一个 TP8 |

每台 GB10：GPU 与 Grace CPU 之间一致性互联，128 GB 统一内存。TP8 下每卡是一个 TP rank，**八台必须同进退**。

## 网络面（两网分离）

| 网络面 | 用途 | 规划 |
|---|---|---|
| RoCE 数据网 | TP 集合通信（gloo/NCCL）、HiCache 节点本地读写、节点间 SSH | 独立交换机，`/24` 一段，按节点编号静态分配（模板见下） |
| 管理网 | 日常 SSH、对外服务口、DHCP | 家/机房主网；head 建议做 DHCP 保留或加固定副地址 |

> 集合通信流量只走 RoCE 口：容器内以 `GLOO_SOCKET_IFNAME=<roce-if>` 钉死接口，防止 gloo 误走管理网。

## 地址规划模板

```
RoCE 网段：<roce-cidr，例 10.0.0.0/24>
  node1(head) -> <n1-roce>    node2 -> <n2-roce>    node3 -> <n3-roce>    node4 -> <n4-roce>
  node5       -> <n5-roce>    node6 -> <n6-roce>    node7 -> <n7-roce>    node8 -> <n8-roce>
管理网：
  head        -> <head-mgmt>（固定副地址或 DHCP 保留；服务对外口）
  其余节点     -> DHCP 即可
```

要点：

1. **head 的管理地址必须固定**（服务入口与编排 SSH 都指向它）。直接改静态会和 DHCP 抢同网段路由；推荐做法 = 保留 DHCP 主地址 + 在 NetworkManager 连接上加**固定副地址 `/32`（noprefixroute）**，`/24` 副地址会与 DHCP 地址抢同一条网段路由导致配不上。
2. RoCE 口静态地址 + 独立交换机；交换机口与线缆要**核对插紧**——实践中一根上行线没插紧曾造成 prefill 吞吐掉 10–20%、FEC 纠错计数暴涨，插紧后恢复（排障时先看交换机 FEC/丢包计数）。
3. 交换机不配 PFC/DSCP 时，跨机 100G 收端丢包主要由线缆质量决定；判断地址是否存活一律用 TCP 探测（某些 TUN 代理会对任意地址伪造 ICMP 应答）。

## 节点 SSH 互信

八台之间（含 head→各台）配好 SSH 公钥免密（`BatchMode=yes` 可达），起服链依赖这一点做并行操作。本机到 head 用一份 ssh config（示例 `scripts/spark8.ssh_config.example`），head 上再到各 RoCE IP。
