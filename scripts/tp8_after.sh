#!/bin/bash
# 在 head 上跑（由 tp8_up.sh 传到 /home/deploy/v24-tools/tp8_after.sh 并后台启动）。用法：bash tp8_after.sh <TAG> [ARMED 期望行，用 | 分隔]
# ① head 管理口地址；② 引擎参数与适配器 ARMED / 拒装行；③ 八台各自的适配器 / 本机副本 / 淘汰器行与缓存目录文件数；
# ④ 长提示暖机（42 万提示 + 两路 524k 解码交错）；⑤ 经 .200 健康检查。结束后保持开服，写 TP8_UP_DONE。
set -u
TAG=${1:?tag}
EXPECT=${2:-}
L=/home/deploy/logs/sd-$TAG-formal.log
: > $L
echo "pid=$$ label=v41f1017-unc-tp8 start=$(date +%FT%T) note=tp8_up $TAG" > /tmp/AB-CLAIM-v41f1017-unc-tp8.txt
cd /home/deploy/v24-tools
echo "HEAD_ADDR $(ip -4 -br addr show enP7s7 | tr -s ' ')" >> $L
echo "$(bash conf8.sh rm)" >> $L
for f in skipnf_off embloc_off shsh_off spalign_off pffair_off; do echo "ON_$f $(bash toggle8.sh /state/$f off)" >> $L; done
grep -aoE "context_length': [0-9]+|max_running_requests': [0-9]+|max_total_tokens': [0-9]+|cuda_graph_max_bs_decode': [0-9]+" /home/deploy/logs/ctn-$TAG.log | sort -u | tr '\n' ' ' >> $L; echo >> $L
grep -ao "max_total_num_tokens=[0-9]*" /home/deploy/logs/ctn-$TAG.log | head -n 1 >> $L
grep -ahE "ARMED|refusing to arm" /home/deploy/logs/ctn-$TAG.log | cut -c1-100 | sort | uniq -c >> $L
if [ -n "$EXPECT" ]; then
  IFS='|' read -ra EX <<< "$EXPECT"
  for e in "${EX[@]}"; do
    n=$(grep -ac -F "$e" /home/deploy/logs/ctn-$TAG.log)
    echo "EXPECT_ARMED [$e] x$n $([ "$n" -ge 1 ] && echo OK || echo MISSING)" >> $L
  done
fi
for h in 4 3 1 2 5 6 7 8; do
  r=$(ssh -o BatchMode=yes -o ConnectTimeout=6 deploy@10.99.0.$h 'D=$(docker logs dsv41-tp8 2>&1); d=$(docker inspect dsv41-tp8 --format "{{range .Mounts}}{{if eq .Destination \"/state\"}}{{.Source}}{{end}}{{end}}")/hicache; echo "armed=$(echo "$D" | grep -c "ARMED") own=$(echo "$D" | grep -c "writes its own node-local") refuse=$(echo "$D" | grep -c "refusing to arm\|not the MLA storage owner") evict=[$(echo "$D" | grep -o "HiCacheFile eviction enabled.*" | head -n 1 | cut -c1-150)] files=$(( $(ls -f $d | wc -l) - 2 )) avail=$(awk "/MemAvailable/{print int(\$2/1024)}" /proc/meminfo)MB"' </dev/null 2>&1)
  echo "NODE 10.99.0.$h $r" >> $L
done
echo "CLK $(for h in 4 3 1 2 5 6 7 8; do ssh -o BatchMode=yes deploy@10.99.0.$h 'systemctl is-active gb10-clock-cap' 2>/dev/null; done | tr '\n' ' ')" >> $L
echo "WARMUP_START $(date +%T)" >> $L
python3 -u probe_prompt.py 420000 >> $L 2>&1
timeout 1200 python3 -u mix_test.py 2 524288 6 2>&1 | grep -E "^MIX|Traceback|Error" >> $L
echo "WARMUP_DONE $(date +%T)" >> $L
echo "HEALTH_VIA_200 $(curl -s -m 5 -o /dev/null -w "%{http_code}" http://192.0.2.200:8888/health) HEALTH_LOCAL $(curl -s -m 5 -o /dev/null -w "%{http_code}" http://127.0.0.1:8888/health) EXC $(grep -ac "Scheduler hit an exception" /home/deploy/logs/ctn-$TAG.log)" >> $L
echo "TP8_UP_DONE $(date +%T)" >> $L
rm -f /tmp/AB-CLAIM-v41f1017-unc-tp8.txt
