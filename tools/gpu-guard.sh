#!/usr/bin/env bash
# gpu-guard: run a command under a GPU memory watchdog (AMD/amdgpu sysfs counters).
#
#   tools/gpu-guard.sh [--limit MB] [--warmup S] -- command args...
#
# Samples VRAM+GTT use every 200 ms. If usage grows more than --limit MB above the level
# seen after --warmup seconds, the command's process group is killed before the desktop
# compositor can be starved (on APUs with a small VRAM carveout, a runaway app makes the
# compositor fail to pin its scanout buffers: "prepare_fb bind failed: -ENOSPC").
# Prints a summary: baseline, peak, growth, verdict. Exit code 3 = killed by the guard.
#
# Use it for any GPU benchmark or visible-window test run by an agent. Headless runs
# (VUI_HIDDEN=1) are already sandboxed on software rendering and don't need it.
set -u
limit=150
warmup=2
while [ $# -gt 0 ]; do
  case "$1" in
    --limit) limit=$2; shift 2 ;;
    --warmup) warmup=$2; shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] || { echo "usage: gpu-guard.sh [--limit MB] [--warmup S] -- command..." >&2; exit 2; }

dev=""
for d in /sys/class/drm/card*/device; do
  [ -r "$d/mem_info_vram_used" ] && { dev=$d; break; }
done
if [ -z "$dev" ]; then
  echo "gpu-guard: no amdgpu memory counters found; running without a guard" >&2
  exec "$@"
fi
mem() { echo $(( ($(cat "$dev/mem_info_vram_used") + $(cat "$dev/mem_info_gtt_used")) / 1048576 )); }
vram_total=$(( $(cat "$dev/mem_info_vram_total") / 1048576 ))

start=$(mem)
setsid "$@" &
pid=$!
t0=$(date +%s%N)
base=""
peak=$start
killed=0
while kill -0 "$pid" 2>/dev/null; do
  sleep 0.2
  now=$(mem)
  [ "$now" -gt "$peak" ] && peak=$now
  el=$(( ($(date +%s%N) - t0) / 1000000 ))
  if [ -z "$base" ] && [ "$el" -ge $((warmup * 1000)) ]; then base=$now; fi
  if [ -n "$base" ] && [ $((now - base)) -gt "$limit" ]; then
    echo "gpu-guard: GPU memory grew +$((now - base)) MB after warmup (limit $limit MB): killing" >&2
    kill -TERM -- -"$pid" 2>/dev/null; sleep 0.5; kill -KILL -- -"$pid" 2>/dev/null
    killed=1
    break
  fi
done
wait "$pid" 2>/dev/null
rc=$?
end=$(mem)
echo "gpu-guard: vram carveout ${vram_total} MB | start ${start} MB | after warmup ${base:-n/a} MB | peak ${peak} MB (+$((peak - start))) | end ${end} MB" >&2
if [ $killed = 1 ]; then
  echo "gpu-guard: FAIL (runaway GPU memory)" >&2
  exit 3
fi
echo "gpu-guard: OK" >&2
exit $rc
