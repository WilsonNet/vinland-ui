#!/usr/bin/env python3
"""End-to-end tests for vui-hot (hot reload).

Every app here runs sandboxed (VUI_HIDDEN=1: SDL offscreen driver + Mesa llvmpipe), so the
suite never maps a window or touches the GPU; each test asserts `sandboxed` before it acts.

    ./build.sh && python3 tests/hot/test_hot.py            # all tests
    python3 tests/hot/test_hot.py -k crash                 # tests whose name contains "crash"

Each test copies a fixture package (tests/hot/fixture, tests/hot/plain) to a temporary
directory, starts ./build/vui-hot on the copy and edits it the way an editor would.
"""
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
VUI_HOT = os.path.join(ROOT, "build", "vui-hot")
FIXTURES = os.path.join(ROOT, "tests", "hot")


def is_isolated(info):
    """Linux: llvmpipe on the offscreen driver (sandboxed). macOS has no Mesa offscreen GL, so
    a hidden window with SDL_MAC_BACKGROUND_APP is the isolation vui-test accepts there too."""
    return info.get("sandboxed") is True or (sys.platform == "darwin" and info.get("hidden") is True)


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def ctl(port, cmd, timeout=10, **args):
    msg = dict(cmd=cmd, **args)
    with socket.create_connection(("127.0.0.1", port), timeout=timeout) as s:
        s.sendall((json.dumps(msg) + "\n").encode())
        buf = b""
        while not buf.endswith(b"\n"):
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
    if not buf:
        raise ConnectionError(f"{cmd}: connection closed without a reply")
    return json.loads(buf)


def write_atomic(path, text):
    """Editors usually save by writing a temp file and renaming it over the original."""
    tmp = path + ".tmp~"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)


class Session:
    """One vui-hot supervisor running a copy of a fixture package."""

    def __init__(self, fixture="fixture", extra_args=(), app_args=(), env=None, copy_framework=False, start=True, mutate=None):
        self.dir = tempfile.mkdtemp(prefix="vui-hot-test-")
        self.pkg = os.path.join(self.dir, fixture)
        shutil.copytree(os.path.join(FIXTURES, fixture), self.pkg)
        self.root = ROOT
        if copy_framework:
            # a private copy of vui/ so a test may edit the framework itself
            self.root = os.path.join(self.dir, "vinland")
            os.makedirs(self.root)
            shutil.copytree(os.path.join(ROOT, "vui"), os.path.join(self.root, "vui"))
            shutil.copytree(os.path.join(ROOT, "assets"), os.path.join(self.root, "assets"))
        if mutate:
            mutate(self)
        self.port = free_port()
        self.log_path = os.path.join(self.dir, "vui-hot.log")
        self.out = os.path.join(self.dir, "build")
        self.extra_args = list(extra_args)
        self.app_args = list(app_args)
        self.env = dict(os.environ)
        self.env.update({"VUI_HIDDEN": "1", "VUI_PORT": str(self.port)})
        self.env.pop("VUI_HIDDEN_GPU", None)  # never hardware in tests (GPU safety)
        if env:
            self.env.update(env)
        self.proc = None
        if start:
            self.start()

    def start(self):
        cmd = [VUI_HOT, self.pkg, "--out", self.out, f"-collection:vinland={self.root}", "--poll", "50", *self.extra_args]
        if self.app_args:
            cmd += ["--", *self.app_args]
        self.log = open(self.log_path, "w")
        self.proc = subprocess.Popen(cmd, stdout=self.log, stderr=subprocess.STDOUT, env=self.env, start_new_session=True)

    def path(self, name="main.odin"):
        return os.path.join(self.pkg, name)

    def read(self, name="main.odin"):
        with open(self.path(name)) as f:
            return f.read()

    def edit(self, old, new, name="main.odin"):
        text = self.read(name)
        assert old in text, f"{old!r} not in {name}"
        write_atomic(self.path(name), text.replace(old, new, 1))

    def logs(self):
        self.log.flush()
        with open(self.log_path) as f:
            return f.read()

    def ctl(self, cmd, **args):
        return ctl(self.port, cmd, **args)

    def info(self):
        return self.ctl("info")

    def hot(self):
        return self.info()["hot"]

    def state(self):
        return self.ctl("state")

    def wait(self, pred, timeout=30, what="condition"):
        deadline = time.time() + timeout
        last = None
        while time.time() < deadline:
            if self.proc.poll() is not None and what != "exit":
                raise AssertionError(f"vui-hot exited ({self.proc.returncode}) waiting for {what}\n{self.logs()}")
            try:
                last = pred()
                if last:
                    return last
            except (OSError, ValueError, KeyError):
                pass
            time.sleep(0.05)
        raise AssertionError(f"timed out waiting for {what} (last={last!r})\n{self.logs()}")

    def wait_ready(self, timeout=60):
        info = self.wait(lambda: self.info(), timeout, "app ready")
        assert is_isolated(info), "refusing to test an app that is not sandboxed"
        assert info["hot"] is not None
        return info

    def wait_gen(self, gen, timeout=40):
        return self.wait(lambda: (h := self.hot())["generation"] >= gen and h["status"] != "Building" and h, timeout, f"generation {gen}")

    def wait_status(self, status, timeout=40):
        return self.wait(lambda: (h := self.hot())["status"] == status and h, timeout, f"status {status}")

    def stop(self):
        if self.proc and self.proc.poll() is None:
            try:
                os.killpg(self.proc.pid, signal.SIGINT)
                self.proc.wait(10)
            except (subprocess.TimeoutExpired, ProcessLookupError):
                try:
                    os.killpg(self.proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                self.proc.wait(5)
        if self.proc:
            self.log.close()

    def cleanup(self):
        self.stop()
        shutil.rmtree(self.dir, ignore_errors=True)


HAS_PROC = os.path.isdir("/proc/self")


def pid_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    if not HAS_PROC:
        r = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)], capture_output=True, text=True)
        return r.returncode == 0 and not r.stdout.strip().startswith("Z")
    # a zombie still answers kill(0)
    try:
        with open(f"/proc/{pid}/stat") as f:
            return f.read().split(")")[-1].split()[0] != "Z"
    except FileNotFoundError:
        return False


def rss_anon_kb(pid):
    with open(f"/proc/{pid}/status") as f:
        for line in f:
            if line.startswith("RssAnon:"):
                return int(line.split()[1])
    return 0


class HotTestCase(unittest.TestCase):
    def session(self, *a, **kw):
        s = Session(*a, **kw)
        self.addCleanup(s.cleanup)
        return s


# ---------------------------------------------------------------------------
# Positive paths
# ---------------------------------------------------------------------------


class Reload(HotTestCase):
    def test_starts_sandboxed_with_hot_status(self):
        s = self.session()
        info = s.wait_ready()
        h = info["hot"]
        self.assertEqual(h["generation"], 1)
        self.assertEqual(h["reloads"], 0)
        self.assertEqual(h["cold_starts"], 1)
        self.assertEqual(h["status"], "Idle")
        self.assertEqual(h["kept"], 1)
        self.assertEqual(s.state()["marker"], "marker-1")

    def test_edit_swaps_code_and_keeps_state_in_same_process(self):
        s = self.session()
        h1 = s.wait_ready()["hot"]
        for _ in range(3):
            s.ctl("click_text", text="increment")
        s.ctl("click_text", text="add item")
        self.assertEqual(s.state()["count"], 3)
        s.edit('"marker-1"', '"marker-2"')
        h2 = s.wait_gen(2)
        st = s.state()
        self.assertEqual(st["marker"], "marker-2")
        self.assertEqual(st["count"], 3)
        self.assertEqual(st["items"], 1)
        self.assertEqual(st["label"], "alpha", "string literal from the first build must stay readable")
        self.assertEqual(h2["pid"], h1["pid"], "hot reload must not restart the process")
        self.assertEqual(h2["cold_starts"], 1, "hot reload must not reopen the window")
        self.assertEqual(h2["reloads"], 1)
        self.assertGreater(h2["build_ms"], 0)
        found = s.ctl("find", text="marker-2", exact=True)
        self.assertTrue(found["found"])

    def test_unkept_globals_reset_and_kept_survive_many_reloads(self):
        s = self.session()
        pid = s.wait_ready()["hot"]["pid"]
        s.ctl("click_text", text="increment")
        for i in range(2, 8):
            s.edit(f'"marker-{i-1}"', f'"marker-{i}"')
            s.wait_gen(i)
            self.assertEqual(s.state()["marker"], f"marker-{i}")
        st = s.state()
        self.assertEqual(st["count"], 1)
        h = s.hot()
        self.assertEqual(h["reloads"], 6)
        self.assertEqual(h["pid"], pid)
        self.assertLess(st["frames"], 200, "the unkept frame counter restarts with each build")

    def test_scroll_position_survives_reload(self):
        s = self.session()
        s.wait_ready()
        before = s.ctl("find", text="row 0", exact=True)
        s.ctl("scroll", x=before["x"] + 20, y=before["y"] + 20, dy=200)
        s.ctl("settle")
        scrolled = s.ctl("find", text="row 0", exact=True)
        self.assertLess(scrolled["y"], before["y"] - 50, "scroll should move the rows up")
        s.edit('"marker-1"', '"marker-2"')
        s.wait_gen(2)
        s.ctl("settle")
        after = s.ctl("find", text="row 0", exact=True)
        self.assertAlmostEqual(after["y"], scrolled["y"], delta=1.0)

    def test_added_field_migrates(self):
        s = self.session()
        s.wait_ready()
        s.ctl("click_text", text="increment")
        s.ctl("click_text", text="increment")
        s.edit("// EDIT:fields", "extra: int,\n\tratio: f32,")
        h = s.wait_gen(2)
        self.assertEqual(s.state()["count"], 2)
        self.assertTrue(any("added" in n and "extra" in n and "ratio" in n for n in h["notes"]), h["notes"])

    def test_field_type_change_resets_only_that_field(self):
        s = self.session()
        s.wait_ready()
        s.ctl("click_text", text="increment")
        s.ctl("click_text", text="add item")
        s.edit("spare: [2]int,", "spare: string,")
        h = s.wait_gen(2)
        st = s.state()
        self.assertEqual(st["count"], 1)
        self.assertEqual(st["items"], 1)
        self.assertEqual(st["label"], "alpha")
        self.assertTrue(any("reset: spare" in n for n in h["notes"]), h["notes"])

    def test_integer_resize_keeps_value(self):
        s = self.session()
        s.wait_ready()
        for _ in range(5):
            s.ctl("click_text", text="increment")
        s.edit("count: int,", "count: i16,")
        s.edit("s.count += 1", "s.count += 1 // i16")
        s.wait_gen(2)
        self.assertEqual(s.state()["count"], 5)

    def test_removed_field_is_dropped(self):
        s = self.session()
        s.wait_ready()
        s.ctl("click_text", text="increment")
        s.edit("\titems: [dynamic]int,\n", "")
        s.edit("append(&s.items, len(s.items))", "s.count += 10")
        s.edit("len(s.items)", "0")
        h = s.wait_gen(2)
        self.assertEqual(s.state()["count"], 1)
        self.assertTrue(any("removed: items" in n for n in h["notes"]), h["notes"])

    def test_new_file_in_package(self):
        s = self.session()
        s.wait_ready()
        with open(s.path("extra.odin"), "w") as f:
            f.write('package fixture\n\nEXTRA_TEXT :: "from a new file"\n')
        s.edit("// EDIT:frame", 'ui.text(EXTRA_TEXT, "text-sm")')
        s.wait_gen(2)
        self.assertTrue(s.ctl("find", text="from a new file")["found"])

    def test_new_local_package_import_is_watched(self):
        s = self.session()
        s.wait_ready()
        sub = os.path.join(s.pkg, "widgets")
        os.makedirs(sub)
        with open(os.path.join(sub, "widgets.odin"), "w") as f:
            f.write('package widgets\n\nlabel :: proc() -> string { return "widget-1" }\n')
        s.edit('import "core:fmt"', 'import "core:fmt"\nimport "widgets"')
        s.edit("// EDIT:frame", 'ui.text(widgets.label(), "text-sm")')
        s.wait_gen(2)
        self.assertTrue(s.ctl("find", text="widget-1")["found"])
        # editing only the imported package must rebuild too
        write_atomic(os.path.join(sub, "widgets.odin"), 'package widgets\n\nlabel :: proc() -> string { return "widget-2" }\n')
        s.wait_gen(3)
        self.assertTrue(s.ctl("find", text="widget-2")["found"])

    def test_touch_without_change_does_not_rebuild(self):
        s = self.session()
        s.wait_ready()
        os.utime(s.path(), None)
        write_atomic(s.path(), s.read())  # a "save" with identical bytes
        time.sleep(1.5)
        h = s.hot()
        self.assertEqual(h["generation"], 1)
        self.assertNotIn("#2", s.logs())

    def test_burst_of_saves_builds_latest(self):
        s = self.session()
        s.wait_ready()
        for i in range(2, 7):
            s.edit(f'"marker-{i-1}"', f'"marker-{i}"')
            time.sleep(0.005)
        s.wait(lambda: s.state()["marker"] == "marker-6", 40, "latest marker")
        self.assertLessEqual(s.hot()["generation"], 3, "a burst of saves should coalesce into one or two builds")

    def test_edit_during_build_cancels_stale_build(self):
        s = self.session()
        s.wait_ready()
        s.edit('"marker-1"', '"marker-2"')
        s.wait(lambda: s.hot()["status"] == "Building", 10, "build start")
        time.sleep(0.2)
        s.edit('"marker-2"', '"marker-3"')
        s.wait(lambda: s.state()["marker"] == "marker-3", 40, "latest marker")
        self.assertIn("cancelled", s.logs())
        self.assertNotEqual(s.state()["marker"], "marker-2")

    def test_toast_after_reload_and_overlay_can_be_hidden(self):
        s = self.session()
        s.wait_ready()
        s.edit('"marker-1"', '"marker-2"')
        s.wait_gen(2)
        self.assertTrue(s.ctl("find", text="Reloaded #2")["found"])
        q = self.session(env={"VUI_HOT_OVERLAY": "0"})
        q.wait_ready()
        q.edit('"marker-1"', '"marker-2"')
        q.wait_gen(2)
        self.assertFalse(q.ctl("find", text="Reloaded #2")["found"])

    def test_app_args_pass_through(self):
        s = self.session(app_args=["--flag", "value"])
        s.wait_ready()
        self.assertEqual(s.state()["args"], ["fixture", "--flag", "value"])

    def test_plain_loop_app_reloads_with_new_window(self):
        s = self.session(fixture="plain")
        h1 = s.wait_ready()["hot"]
        s.ctl("click_text", text="clicks 0")
        s.edit('"plain-1"', '"plain-2"')
        h2 = s.wait_gen(2)
        self.assertTrue(s.ctl("find", text="plain-2")["found"])
        self.assertTrue(s.ctl("find", text="clicks 1")["found"], "app.keep works in a classic loop too")
        self.assertEqual(h2["pid"], h1["pid"])
        self.assertEqual(h2["cold_starts"], 2, "a classic loop reopens its window")

    def test_framework_layout_change_restarts_window_and_keeps_state(self):
        def patch(sess):
            pass

        s = self.session(copy_framework=True, mutate=patch)
        h1 = s.wait_ready()["hot"]
        s.ctl("click_text", text="increment")
        app_odin = os.path.join(s.root, "vui", "app", "app.odin")
        with open(app_odin) as f:
            text = f.read()
        write_atomic(app_odin, text.replace("wait_requests: [dynamic]Wait_Request,", "wait_requests: [dynamic]Wait_Request,\n\thot_test_field: int,", 1))
        h2 = s.wait_gen(2, timeout=60)
        self.assertEqual(h2["pid"], h1["pid"])
        self.assertEqual(h2["cold_starts"], 2, "an App layout change must reopen the window")
        self.assertEqual(s.state()["count"], 1, "kept globals survive a cold start in the same process")

    def test_init_runs_once_per_window(self):
        s = self.session()
        s.wait_ready()
        for i in range(2, 4):
            s.edit(f'"marker-{i-1}"', f'"marker-{i}"')
            s.wait_gen(i)
        self.assertEqual(s.state()["inits"], 1)

    def test_loaded_asset_change_rebuilds(self):
        s = self.session()
        s.wait_ready()
        self.assertEqual(s.state()["data"], "data-1")
        write_atomic(s.path("data.txt"), "data-2\n")
        s.wait_gen(2)
        self.assertEqual(s.state()["data"], "data-2")

    def test_odin_flags_pass_through(self):
        s = self.session(extra_args=["-define:FIXTURE_FLAG=true"])
        s.wait_ready()
        self.assertTrue(s.state()["flag"])

    def test_swap_is_fast_and_memory_bounded(self):
        if not HAS_PROC:
            self.skipTest("needs /proc for RssAnon")
        s = self.session()
        h = s.wait_ready()["hot"]
        pid = h["pid"]
        s.edit('"marker-1"', '"marker-2"')
        s.wait_gen(2)
        base = rss_anon_kb(pid)
        for i in range(3, 11):
            s.edit(f'"marker-{i-1}"', f'"marker-{i}"')
            h = s.wait_gen(i)
            self.assertLess(h["swap_ms"], 100, "dlopen + resume should take milliseconds")
        grown = (rss_anon_kb(pid) - base) / 1024
        # each build's thread-local arenas are released on hand-off (before: +4.2 MB per reload)
        self.assertLess(grown / 8, 1.5, f"anonymous memory grew {grown:.1f} MB over 8 reloads")

    def test_traditional_build_is_unaffected(self):
        d = tempfile.mkdtemp(prefix="vui-trad-")
        self.addCleanup(shutil.rmtree, d, True)
        exe = os.path.join(d, "fixture")
        r = subprocess.run(["odin", "build", os.path.join(FIXTURES, "fixture"), f"-collection:vinland={ROOT}", f"-out:{exe}"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        port = free_port()
        env = dict(os.environ, VUI_HIDDEN="1", VUI_PORT=str(port))
        env.pop("VUI_HIDDEN_GPU", None)
        p = subprocess.Popen([exe], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.time() + 30
            info = None
            while time.time() < deadline:
                try:
                    info = ctl(port, "info")
                    break
                except OSError:
                    time.sleep(0.05)
            self.assertIsNotNone(info)
            self.assertTrue(is_isolated(info))
            self.assertIsNone(info["hot"], "a normal build must not run any hot reload code")
            ctl(port, "click_text", text="increment")
            self.assertEqual(ctl(port, "state")["count"], 1)
            ctl(port, "quit")
            self.assertEqual(p.wait(10), 0)
        finally:
            if p.poll() is None:
                p.kill()


# ---------------------------------------------------------------------------
# Negative paths
# ---------------------------------------------------------------------------


class Failures(HotTestCase):
    def test_syntax_error_keeps_old_build_running(self):
        s = self.session()
        s.wait_ready()
        s.ctl("click_text", text="increment")
        s.edit("// EDIT:frame", "if ui.div( {")
        h = s.wait_status("Error")
        self.assertEqual(h["generation"], 1)
        self.assertEqual(h["error_gen"], 2)
        self.assertIn("main.odin", h["error"])
        self.assertEqual(s.state()["marker"], "marker-1", "the previous build keeps running")
        self.assertTrue(s.ctl("find", text="Build #2 failed")["found"], "the error overlay is drawn")
        # fix it: the next build swaps in and clears the error
        s.edit("if ui.div( {", "// EDIT:frame")
        s.edit('"marker-1"', '"marker-3"')
        h = s.wait_gen(3)
        self.assertEqual(h["status"], "Idle")
        self.assertEqual(h["error"], "")
        self.assertEqual(s.state()["count"], 1)
        self.assertFalse(s.ctl("find", text="Build #2 failed")["found"])

    def test_type_error_reports_location(self):
        s = self.session()
        s.wait_ready()
        s.edit("frames += 1", 'frames += "one"')
        h = s.wait_status("Error")
        self.assertRegex(h["error"], r"main\.odin\(\d+:\d+\)")
        self.assertRegex(s.logs(), r"✗ #2 failed .*main\.odin:\d+:\d+")

    def test_initial_build_failure_waits_for_fix(self):
        def broken(sess):
            p = sess.path()
            with open(p) as f:
                t = f.read()
            with open(p, "w") as f:
                f.write(t.replace("frames += 1", "frames += 1 +"))

        s = self.session(mutate=broken)
        s.wait(lambda: "✗ #1 failed" in s.logs(), 40, "first build to fail", )
        self.assertIsNone(s.proc.poll(), "vui-hot keeps watching after a failed first build")
        s.edit("frames += 1 +", "frames += 1")
        info = s.wait_ready()
        self.assertEqual(info["hot"]["generation"], 2)

    def test_crash_right_after_reload_rolls_back(self):
        s = self.session()
        s.wait_ready()
        s.edit('"marker-1"', '"marker-2"')
        s.wait_gen(2)
        s.edit("frames += 1", "frames += 1\n\tif frames > 2 { p: ^int; p^ = 1 }")
        s.wait(lambda: "right after loading #3" in s.logs(), 40, "rollback")
        h = s.wait_status("Error")
        self.assertEqual(s.state()["marker"], "marker-2", "restarted on the last good build")
        self.assertIn("crashed right after it was loaded", h["error"])
        s.edit("\n\tif frames > 2 { p: ^int; p^ = 1 }", "")
        s.edit('"marker-2"', '"marker-4"')
        s.wait(lambda: s.state()["marker"] == "marker-4", 40, "fixed build")
        self.assertEqual(s.hot()["status"], "Idle")

    def test_runtime_crash_restarts_then_stops_on_crash_loop(self):
        s = self.session()
        pid1 = s.wait_ready()["hot"]["pid"]
        with self.assertRaises(OSError):
            s.ctl("crash")
        h = s.wait(lambda: (h := s.hot())["pid"] != pid1 and h, 30, "restart")
        self.assertEqual(h["generation"], 1)
        self.assertIn("restarting #1", s.logs())
        # two more crashes inside 10 s: vui-hot stops respawning until the next change
        for _ in range(2):
            pid = s.wait(lambda: s.hot()["pid"], 30, "running")
            try:
                s.ctl("crash")
            except OSError:
                pass
            s.wait(lambda: not pid_alive(pid), 10, "crash")
        s.wait(lambda: "waiting for the next change" in s.logs(), 20, "crash loop stop")
        s.edit('"marker-1"', '"marker-2"')
        s.wait(lambda: s.state()["marker"] == "marker-2", 40, "respawn after change")

    def test_window_close_ends_supervisor(self):
        s = self.session()
        s.wait_ready()
        s.ctl("quit")
        self.assertEqual(s.proc.wait(15), 0)
        self.assertIn("app exited", s.logs())

    def test_sigint_cleans_up_builds_and_runner(self):
        s = self.session()
        pid = s.wait_ready()["hot"]["pid"]
        os.kill(s.proc.pid, signal.SIGINT)  # supervisor only (an IDE stop button)
        self.assertEqual(s.proc.wait(15), 130)
        s.wait(lambda: not pid_alive(pid), 10, "exit")
        libs = [f for f in os.listdir(s.out) if f.startswith("fixture_")]
        self.assertEqual(libs, [], "builds are removed on exit")

    def test_killed_supervisor_never_leaves_orphan_window(self):
        s = self.session()
        pid = s.wait_ready()["hot"]["pid"]
        os.kill(s.proc.pid, signal.SIGKILL)
        s.proc.wait(5)
        s.wait(lambda: not pid_alive(pid), 10, "exit")

    def test_hot_abi_mismatch_keeps_running(self):
        s = self.session(copy_framework=True)
        s.wait_ready()
        hot_odin = os.path.join(s.root, "vui", "hot", "hot.odin")
        with open(hot_odin) as f:
            text = f.read()
        write_atomic(hot_odin, text.replace("HOST_ABI :: ", "HOST_ABI :: 1000 + ", 1))
        h = s.wait_status("Error", timeout=60)
        self.assertIn("different vui/hot", h["error"])
        self.assertEqual(s.state()["marker"], "marker-1")

    def test_deleted_file_fails_then_restores(self):
        s = self.session()
        s.wait_ready()
        with open(s.path("extra.odin"), "w") as f:
            f.write('package fixture\n\nEXTRA_TEXT :: "extra"\n')
        s.edit("// EDIT:frame", 'ui.text(EXTRA_TEXT, "text-sm")')
        s.wait_gen(2)
        os.remove(s.path("extra.odin"))
        h = s.wait_status("Error")
        self.assertIn("EXTRA_TEXT", h["error"])
        self.assertTrue(s.ctl("find", text="extra")["found"], "the last good build keeps running")
        with open(s.path("extra.odin"), "w") as f:
            f.write('package fixture\n\nEXTRA_TEXT :: "extra back"\n')
        s.wait(lambda: s.ctl("find", text="extra back")["found"], 40, "restored file")
        self.assertEqual(s.hot()["status"], "Idle")

    def test_mismatched_vui_checkout_is_refused(self):
        def relative_vui(sess):
            # the app imports a private vui copy relatively while the collection points elsewhere
            shutil.copytree(os.path.join(ROOT, "vui"), os.path.join(sess.dir, "vui"))
            shutil.copytree(os.path.join(ROOT, "assets"), os.path.join(sess.dir, "assets"))
            p = sess.path()
            with open(p) as f:
                t = f.read()
            with open(p, "w") as f:
                f.write(t.replace('"vinland:vui"', '"../vui"').replace('"vinland:vui/app"', '"../vui/app"').replace('"vinland:vui/fonts"', '"../vui/fonts"'))

        s = self.session(mutate=relative_vui)
        self.assertEqual(s.proc.wait(30), 2)
        self.assertIn("so both use the same vui", s.logs())

    def test_tmpfs_build_dir_is_noted(self):
        s = self.session()
        s.wait_ready()
        if HAS_PROC and subprocess.run(["stat", "-f", "-c", "%T", s.out], capture_output=True, text=True).stdout.strip() == "tmpfs":
            self.assertIn("is on tmpfs", s.logs())

    def test_quiet_prints_only_errors(self):
        s = self.session(extra_args=["--quiet"])
        s.wait_ready()
        s.edit('"marker-1"', '"marker-2"')
        s.wait_gen(2)
        self.assertNotIn("built in", s.logs())
        s.edit("frames += 1", "frames += 1 +")
        s.wait_status("Error")
        self.assertIn("failed", s.logs())

    def test_bad_arguments(self):
        cases = [
            ([VUI_HOT, "/nonexistent/pkg"], "not a directory"),
            ([VUI_HOT, tempfile.gettempdir(), "--poll", "1"], "--poll"),
            ([VUI_HOT, os.path.join(FIXTURES, "fixture"), "-out:x"], "set by vui-hot"),
            ([VUI_HOT, os.path.join(FIXTURES, "fixture"), "--bogus"], "unknown option"),
            ([VUI_HOT, os.path.join(FIXTURES, "fixture"), os.path.join(FIXTURES, "plain")], "one package only"),
            ([VUI_HOT, "--child"], "internal"),
        ]
        empty = tempfile.mkdtemp(prefix="vui-empty-")
        self.addCleanup(shutil.rmtree, empty, True)
        cases.append(([VUI_HOT, empty], "no .odin files"))
        for cmd, needle in cases:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            self.assertNotEqual(r.returncode, 0, cmd)
            self.assertIn(needle, r.stderr + r.stdout, cmd)

    def test_help(self):
        r = subprocess.run([VUI_HOT, "--help"], capture_output=True, text=True, timeout=10)
        self.assertEqual(r.returncode, 0)
        self.assertIn("usage: vui-hot", r.stdout)


if __name__ == "__main__":
    if not os.path.exists(VUI_HOT):
        sys.exit("build/vui-hot missing: run ./build.sh first")
    unittest.main(verbosity=2)
