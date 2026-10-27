#!/bin/bash
# 变体链 v2：时钟闸门 → 拷底版（BASE_ENV，默认 clean-best）→ 追加 EXTRA_SGLANG_ARGS → chain_boot（KEY=VAL / X:KEY=VAL）→ 依次跑若干 sparkDash 档（逗号分隔，如 quick,pr）
# 用法: BASE_ENV=... chain_variant2.sh <标签> <档,档> "<追加 sglang 参数，可空>" [KEY=VAL ...]
TAG=$1; TIERS=$2; APPEND=$3; shift 3
BASE=${BASE_ENV:-/home/deploy/knapcio-v24/.env.tp4.clean-best}
E=/home/deploy/knapcio-v24/.env.tp4
bash /home/deploy/v24-tools/clk_gate.sh $TAG || { echo "CLK_GATE_FAIL $(date +%T)" > /home/deploy/logs/v24-rb-$TAG.log; echo BOOT_FAILED >> /home/deploy/logs/v24-rb-$TAG.log; exit 1; }
cp -f "$BASE" $E
if [ -n "$APPEND" ]; then
python3 - "$E" "$APPEND" <<'PY'
import sys
p, app = sys.argv[1], sys.argv[2]
t = open(p, encoding="utf-8").read().split("\n")
n = 0
for i, l in enumerate(t):
    if l.startswith('EXTRA_SGLANG_ARGS="') and l.endswith('"'):
        t[i] = l[:-1] + " " + app + '"'; n += 1
if n != 1:
    sys.exit("EXTRA_SGLANG_ARGS line not found exactly once")
open(p, "w", encoding="utf-8", newline="\n").write("\n".join(t))
PY
fi
echo "VARIANT $TAG base=$BASE tiers=$TIERS append=[$APPEND] kv=[$*]" > /home/deploy/logs/v24-variant-$TAG.log
bash /home/deploy/v24-tools/chain_boot.sh $TAG 0 DSPARK_BLOCK_SIZE=5 "$@" > /home/deploy/logs/v24-chain-$TAG.log 2>&1
setsid -f bash -c "docker logs -f dsv41-tp8 > /home/deploy/logs/ctn-$TAG.log 2>&1" < /dev/null > /dev/null 2>&1
grep -q "^BOOT_READY" /home/deploy/logs/v24-rb-$TAG.log || { echo "AUTO_SD_DONE $(date +%T) rc=boot_not_ready" > /home/deploy/logs/sd-$TAG-auto.log; exit 1; }
: > /home/deploy/logs/sd-$TAG-auto.log
for T in ${TIERS//,/ }; do
  echo "AUTO_SD_START $T $(date +%T)" >> /home/deploy/logs/sd-$TAG-auto.log
  TIER=$T TAG=$TAG-$T OUT=/home/deploy/logs/sd-$TAG-$T.json python3 -u /home/deploy/v24-tools/sd_tp8_run.py >> /home/deploy/logs/sd-$TAG-auto.log 2>&1
  echo "TIER_DONE $T $(date +%T) rc=$?" >> /home/deploy/logs/sd-$TAG-auto.log
done
echo "AUTO_SD_DONE $(date +%T) rc=0" >> /home/deploy/logs/sd-$TAG-auto.log
