#!/bin/bash
# TP8 + V41 固定起服入口（2026-10-25 起；PC 侧 Git Bash 跑，后台 job）。只换 / 起容器，不重启宿主、不碰交换机、不改锁频。
# 用法：bash scripts/tp8/tp8_up.sh [标签]           标签默认 up<月日_时分>（决定 head 上各日志文件名）
#       FORCE=1 bash scripts/tp8/tp8_up.sh          服务已在跑也强制换新容器（计划内重启用；会断开所有会话）
# 配置真源 = scripts/tp8/tp8-prod.conf；步骤与排错见 docs/ai-industry/compute-economics/tp8-boot-path.md。
# 步骤：0 前置核查 → 1 独占声明 → 2 停八台容器 → 3 挂内存哨兵（每台 keeper=1 watcher=1，缺则停） → 4 关深睡眠态 →
#       5 锁频核查（八台 gb10-clock-cap=active） → 6 chain_variant2 起服 → 7 等 BOOT_READY → 8 tp8_after.sh（适配器 / 暖机 / 健康） → 9 对外口自检
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
. scripts/tp8/tp8-prod.conf
CFG=scripts/spark8.ssh_config
TAG=${1:-up$(date +%m%d_%H%M)}
FORCE=${FORCE:-0}
SSH() { timeout "${T:-40}" ssh -F $CFG -o ConnectTimeout=6 -o BatchMode=yes "$@"; }
say() { echo "$(date +%T) $*"; }
die() { say "ABORT $*"; exit 1; }

say "TP8_UP_START tag=$TAG image=$IMAGE force=$FORCE"

# 0 前置核查：八台 ssh 可达、运行时长、head 上有无编排在跑、服务是否已在跑
bad=0
for i in "${!NODES_SSH[@]}"; do
  n=${NODES_SSH[$i]}
  r=$(T=12 SSH $n 'echo "up=$(cut -d. -f1 /proc/uptime)s ctn=$(docker ps --format "{{.Names}}" | grep -c "^dsv41-tp8$") img=$(docker images -q '"$IMAGE"' | wc -l)"' 2>&1 | tail -1)
  say "PRE $n $r"
  echo "$r" | grep -q "^up=" || bad=$((bad+1))
  echo "$r" | grep -q "img=1" || { say "PRE $n 缺镜像 $IMAGE"; bad=$((bad+1)); }
done
[ $bad = 0 ] || die "前置核查不过（节点不可达或缺镜像）n=$bad"
h=$(curl -s --noproxy "*" -m 5 -o /dev/null -w "%{http_code}" http://$HEAD_ADDR:$HEAD_PORT/health)
if [ "$h" = "200" ] && [ "$FORCE" != "1" ]; then die "服务已在跑（health 200）；要强制换容器请 FORCE=1"; fi
c=$(SSH node-01 'ls /tmp/AB-CLAIM-v41f1017-unc-tp8.txt 2>/dev/null | wc -l; pgrep -f "[c]hain_variant2|[c]hain_boot|[b]oot_only" | wc -l' | tr '\n' ' ')
say "PRE head claim/chain = $c"
[ "$c" = "0 0 " ] || die "head 上已有独占声明或起服链在跑（$c）；先查清再说"

# 1 独占声明
SSH node-01 "echo \"pid=\$\$ label=v41f1017-unc-tp8 start=\$(date +%FT%T) note=tp8_up $TAG\" > /tmp/AB-CLAIM-v41f1017-unc-tp8.txt" || die "写独占声明失败"
say "CLAIM written"
trap 'SSH node-01 "rm -f /tmp/AB-CLAIM-v41f1017-unc-tp8.txt" 2>/dev/null' EXIT

# 2 停八台容器（并行）
T=60 SSH node-01 'for h in 4 3 1 2 5 6 7 8; do ssh -o BatchMode=yes -o ConnectTimeout=6 deploy@10.99.0.$h "docker rm -f dsv41-tp8 >/dev/null 2>&1; echo \$(hostname) gone=\$(docker ps -a --format {{.Names}} | grep -c \"^dsv41-tp8\$\")" </dev/null & done; wait' | sed 's/^/  /'

# 3 内存哨兵（单台 4 s 起；缺则重试一次）。绝对下限 1024 MB 永久在岗：任何一台挂不上就不起服
bad=0
for n in "${NODES_SSH[@]}"; do
  r=$(SSH $n 'setsid bash /home/deploy/v24-tools/fix_sentinel_host.sh </dev/null >/tmp/fixsent.log 2>&1; tail -n1 /tmp/fixsent.log' 2>&1 | tail -1)
  if ! echo "$r" | grep -q "keeper=1 watcher=1"; then
    sleep 20
    r=$(SSH $n 'echo "$(hostname) keeper=$(pgrep -f "[s]entinel_keeper.sh" | wc -l) watcher=$(pgrep -f "[v]41-mg-load.sh __watch dsv41-tp8" | wc -l)"' 2>&1 | tail -1)
  fi
  say "SENTINEL $n $r"
  echo "$r" | grep -q "keeper=1 watcher=1" || bad=$((bad+1))
done
[ $bad = 0 ] || die "哨兵未全部在岗 n=$bad（已写的独占声明随退出释放）"

# 4 关深睡眠态（运行时状态，宿主重启后复原；幂等）。密码经 SOPS 只走 stdin，不进 argv、不打印
python scripts/tp8/sudo_out.py "$(IFS=,; echo "${NODES_SSH[*]}")" "sh -c 'for f in /sys/devices/system/cpu/cpu*/cpuidle/state2/disable /sys/devices/system/cpu/cpu*/cpuidle/state3/disable; do echo 1 > \$f; done; cat /sys/devices/system/cpu/cpu0/cpuidle/state3/disable'" 2>&1 | tr '\n' ' ' | sed 's/=====/\n  =====/g'; echo
off=$(for n in "${NODES_SSH[@]}"; do SSH $n 'cat /sys/devices/system/cpu/cpu0/cpuidle/state3/disable' 2>/dev/null; done | tr -d '\n')
say "DEEP_IDLE_OFF state3.disable x8 = $off"
[ "$off" = "11111111" ] || die "深睡眠态没有全部关掉（$off）"

# 5 锁频核查（2026-10-23 用户令：八台 2200 MHz 锁频保持；服务 gb10-clock-cap 开机自启）
clk=$(for n in "${NODES_SSH[@]}"; do SSH $n 'systemctl is-active gb10-clock-cap' 2>/dev/null; done | tr '\n' ' ')
say "CLK $clk"
[ "$clk" = "active active active active active active active active " ] || die "锁频服务不是八台 active"

# 6 起服：与历次现役同一条 chain_variant2；只传 tp8_after.sh，其余工具都在 head 的 /home/deploy/v24-tools
timeout 30 scp -F $CFG -q scripts/tp8/tp8_after.sh node-01:/home/deploy/v24-tools/tp8_after.sh || die "传 tp8_after.sh 失败"
ARGSTR="${CHAIN_ARGS[*]}"
say "LAUNCH chain_variant2 $TAG IMAGE=$IMAGE $ARGSTR"
SSH node-01 "cd /home/deploy && BASE_ENV=$BASE_ENV setsid -f bash /home/deploy/v24-tools/chain_variant2.sh $TAG \"\" \"\" IMAGE=$IMAGE $ARGSTR </dev/null >/home/deploy/logs/v24-launch-$TAG.log 2>&1; echo LAUNCHED \$(date +%T)" || die "起服命令发不出去"

# 7 等 BOOT_READY（最多 30 分钟）
ready=0
for t in $(seq 1 60); do
  r=$(T=20 SSH node-01 'grep -hE "^(BOOT_READY|BOOT_FAILED|BOOT_TIMEOUT|CLK_GATE_FAIL)" /home/deploy/logs/v24-rb-'"$TAG"'.log /home/deploy/logs/v24-chain-'"$TAG"'.log 2>/dev/null | tail -n1 | cut -c1-30' 2>/dev/null)
  case "$r" in
    BOOT_READY*) say "$r"; ready=1; break;;
    BOOT_FAILED*|BOOT_TIMEOUT*|CLK_GATE_FAIL*) say "$r TERMINAL"; die "起服失败：$r（日志 v24-chain-$TAG.log / v24-rb-$TAG.log / v24-serve-$TAG.log）";;
  esac
  sleep 30
done
[ $ready = 1 ] || die "30 分钟没等到 BOOT_READY"

# 8 起服后检查与暖机（后台跑在 head 上，这里轮询）
EXP=$(IFS='|'; echo "${EXPECT_ARMED[*]}")
SSH node-01 "setsid -f bash /home/deploy/v24-tools/tp8_after.sh $TAG '$EXP' </dev/null >/dev/null 2>&1; echo AFTER_LAUNCHED \$(date +%T)"
last=""
for t in $(seq 1 120); do
  r=$(T=20 SSH node-01 'L=/home/deploy/logs/sd-'"$TAG"'-formal.log; m=$(grep -hE "^(HEAD_ADDR|EXPECT_ARMED|NODE|WARMUP_START|WARMUP_DONE|HEALTH_VIA_200|TP8_UP_DONE)" $L 2>/dev/null | tail -n1 | cut -c1-40); e=$(grep -ciE "traceback|guard tripped" $L 2>/dev/null); h=$(curl -s -m 4 -o /dev/null -w "%{http_code}" http://127.0.0.1:8888/health); echo "${m:-none}|err=${e:-0}|health=$h"' 2>/dev/null)
  [ "$r" != "$last" ] && { say "AFTER $r"; last="$r"; }
  case "$r" in *TP8_UP_DONE*) break;; esac
  case "$r" in *err=[1-9]*) say "PROBLEM $r"; break;; esac
  sleep 30
done

# 9 汇总与对外口自检
echo "---- sd-$TAG-formal.log ----"
SSH node-01 "grep -vE '^\[' /home/deploy/logs/sd-$TAG-formal.log | cut -c1-260"
say "PC_TCP_$HEAD_ADDR health=$(curl -s --noproxy '*' -m 6 -o /dev/null -w '%{http_code}' http://$HEAD_ADDR:$HEAD_PORT/health) ssh=$(T=15 SSH -o HostName=$HEAD_ADDR node-01 'echo ok' 2>/dev/null)"
say "TP8_UP_END tag=$TAG"
