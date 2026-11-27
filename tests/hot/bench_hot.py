#!/usr/bin/env python3
"""Benchmarks for vui-hot (results recorded in tools/vui-hot/BENCHMARKS.md).

    ./build.sh && python3 tests/hot/bench_hot.py [--runs 10] [--app showroom|counter]

Everything runs sandboxed (VUI_HIDDEN=1, llvmpipe): no window, no GPU memory.

Measures
  1. hot reload: save -> new code answering on the control port (median / p90), with the
     compile time and the in-process swap time reported by the runner
  2. traditional cycle: stop the app, `odin build`, start it, wait until it answers
  3. supervisor idle cost: CPU time while watching with no edits (per poll interval)
  4. runner memory across many reloads (every old build stays mapped)
"""
import argparse
import json
import os
import shutil
import signal
import socket
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HOT = os.path.join(ROOT, "build", "vui-hot")
TICK = os.sysconf("SC_CLK_TCK")
# on disk, like a real project's ./build/hot (on tmpfs, mapped old builds could never be dropped)
BENCH_DIR = os.path.join(ROOT, "build", "bench")
os.makedirs(BENCH_DIR, exist_ok=True)


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def ctl(port, cmd, **a):
    with socket.create_connection(("127.0.0.1", port), timeout=30) as s:
        s.sendall((json.dumps(dict(cmd=cmd, **a)) + "\n").encode())
        b = b""
        while not b.endswith(b"\n"):
            c = s.recv(1 << 20)
            if not c:
                raise ConnectionError(cmd)
            b += c
    return json.loads(b)


def wait_port(port, timeout=120):
    t = time.time()
    while time.time() - t < timeout:
        try:
            return ctl(port, "info")
        except (OSError, ValueError):
            time.sleep(0.01)
    raise TimeoutError("app did not answer")


def cpu_s(pid):
    with open(f"/proc/{pid}/stat") as f:
        parts = f.read().rsplit(")", 1)[1].split()
    return (int(parts[11]) + int(parts[12])) / TICK


def rss_mb(pid, field="VmRSS"):
    with open(f"/proc/{pid}/status") as f:
        for line in f:
            if line.startswith(field + ":"):
                return int(line.split()[1]) / 1024
    return 0.0


def rss_split(pid):
    return {k: rss_mb(pid, k) for k in ("VmRSS", "RssAnon", "RssFile", "RssShmem")}


def save(path, old, new):
    with open(path) as f:
        text = f.read()
    assert old in text, (path, old)
    tmp = path + ".tmp~"
    with open(tmp, "w") as f:
        f.write(text.replace(old, new, 1))
    os.replace(tmp, path)


def sandbox_env(port):
    env = dict(os.environ, VUI_HIDDEN="1", VUI_PORT=str(port), VUI_QUIET="1")
    env.pop("VUI_HIDDEN_GPU", None)
    return env


def setup_app(work, app):
    """Copies the app (and vui, so relative imports resolve inside the copy)."""
    for d in ("vui", "assets"):
        shutil.copytree(os.path.join(ROOT, d), os.path.join(work, d))
    if app == "showroom":
        shutil.copytree(os.path.join(ROOT, "showroom"), os.path.join(work, "showroom"))
        return os.path.join(work, "showroom"), os.path.join(work, "showroom", "pages_intro.odin"), "Skeuomorphic HUDs for games"
    os.makedirs(os.path.join(work, "examples"))
    shutil.copytree(os.path.join(ROOT, "examples", "counter"), os.path.join(work, "examples", "counter"))
    return os.path.join(work, "examples", "counter"), os.path.join(work, "examples", "counter", "main.odin"), '"Counter"'


def bench_hot(work, pkg, file, needle, runs, poll):
    port = free_port()
    log = open(os.path.join(work, f"hot-{poll}.log"), "w")
    p = subprocess.Popen([HOT, pkg, "--out", os.path.join(work, "build"), "--poll", str(poll)], cwd=work, env=sandbox_env(port), stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        info = wait_port(port)
        assert info["sandboxed"], "refusing to benchmark a non-sandboxed app"
        child = info["hot"]["pid"]
        rss0 = rss_mb(child)
        split0 = rss_split(child)
        # idle cost of the watcher
        time.sleep(1.0)
        c0 = cpu_s(p.pid)
        idle_s = 10.0
        time.sleep(idle_s)
        idle_cpu = cpu_s(p.pid) - c0
        lat, build, swap = [], [], []
        cur = needle
        for i in range(runs):
            nxt = needle.replace("HUDs", f"HUDs v{i}") if "HUDs" in needle else f'"Counter v{i}"'
            gen = ctl(port, "info")["hot"]["generation"]
            t0 = time.perf_counter()
            save(file, cur, nxt)
            cur = nxt
            while True:
                h = ctl(port, "info")["hot"]
                if h["generation"] > gen and h["status"] == "Idle":
                    break
                time.sleep(0.002)
            lat.append(time.perf_counter() - t0)
            build.append(h["build_ms"] / 1000)
            swap.append(h["swap_ms"])
            time.sleep(0.3)
        rss1 = rss_mb(child)
        split1 = rss_split(child)
        same_pid = ctl(port, "info")["hot"]["pid"] == child
        return dict(split0=split0, split1=split1, lat=lat, build=build, swap=swap, idle_cpu=idle_cpu, idle_s=idle_s, rss0=rss0, rss1=rss1, same_pid=same_pid, reloads=runs)
    finally:
        os.killpg(p.pid, signal.SIGINT)
        p.wait(20)
        log.close()


def bench_traditional(work, pkg, runs):
    exe = os.path.join(work, "trad-app")
    times, builds = [], []
    for _ in range(runs):
        port = free_port()
        t0 = time.perf_counter()
        r = subprocess.run(["odin", "build", pkg, "-debug", f"-out:{exe}"], capture_output=True)
        assert r.returncode == 0, r.stderr
        tb = time.perf_counter()
        p = subprocess.Popen([exe], env=sandbox_env(port), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        info = wait_port(port)
        assert info["sandboxed"]
        times.append(time.perf_counter() - t0)
        builds.append(tb - t0)
        ctl(port, "quit")
        p.wait(10)
    return dict(total=times, build=builds)


def fmt(xs, unit="s", scale=1.0):
    xs = sorted(x * scale for x in xs)
    p90 = xs[min(len(xs) - 1, int(round(0.9 * (len(xs) - 1))))]
    return f"median {statistics.median(xs):.3f} {unit}, p90 {p90:.3f} {unit}, min {xs[0]:.3f} {unit}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=10)
    ap.add_argument("--app", default="showroom", choices=["showroom", "counter"])
    ap.add_argument("--poll", type=int, nargs="*", default=[100])
    args = ap.parse_args()
    if not os.path.exists(HOT):
        sys.exit("build/vui-hot missing: run ./build.sh")
    print(f"app: {args.app}   runs: {args.runs}   cpus: {os.cpu_count()}")
    for poll in args.poll:
        work = tempfile.mkdtemp(prefix="vui-hot-bench-", dir=BENCH_DIR)
        try:
            pkg, file, needle = setup_app(work, args.app)
            r = bench_hot(work, pkg, file, needle, args.runs, poll)
            print(f"\n[hot reload, --poll {poll}]")
            print("  save -> new code live :", fmt(r["lat"]))
            print("  odin build (dll)      :", fmt(r["build"]))
            print("  swap (dlopen+resume)  :", fmt(r["swap"], "ms"))
            print(f"  watcher idle CPU      : {r['idle_cpu'] * 1000:.1f} ms over {r['idle_s']:.0f} s ({100 * r['idle_cpu'] / r['idle_s']:.3f}% of one core)")
            print(f"  runner RSS            : {r['rss0']:.1f} MB -> {r['rss1']:.1f} MB after {r['reloads']} reloads ({(r['rss1'] - r['rss0']) / r['reloads']:.2f} MB/reload)")
            print("  RSS anon / file / shm : %.1f / %.1f / %.1f MB -> %.1f / %.1f / %.1f MB" % (r["split0"]["RssAnon"], r["split0"]["RssFile"], r["split0"]["RssShmem"], r["split1"]["RssAnon"], r["split1"]["RssFile"], r["split1"]["RssShmem"]))
            print(f"  same process          : {r['same_pid']}")
        finally:
            shutil.rmtree(work, ignore_errors=True)
    work = tempfile.mkdtemp(prefix="vui-hot-bench-", dir=BENCH_DIR)
    try:
        pkg, _, _ = setup_app(work, args.app)
        t = bench_traditional(work, pkg, max(3, args.runs // 2))
        print("\n[traditional: odin build + start + first answer]")
        print("  total                 :", fmt(t["total"]))
        print("  odin build (exe)      :", fmt(t["build"]))
        print("  (state, page, scroll and dark mode are lost and must be re-created by hand)")
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
