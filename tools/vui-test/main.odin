// vui-test: Playwright-style end-to-end runner for vinland-ui apps.
//
//   vui-test [--update] [--out DIR] [--headed-gpu] suite.vt ...
//
// Each suite launches the app headless and SANDBOXED (SDL offscreen driver + Mesa llvmpipe:
// no compositor connection, no GPU memory), drives it over the control port, asserts on the
// element tree, takes screenshots, compares them with baselines, and writes an HTML + JSON
// report. Every test starts a fresh app process (isolation, like a new browser context).
//
// Suite format (one directive per line, `#` comments, "quoted args"):
//   app ../bin/my-app --data {test}/data     command; {out} = output dir, {dir} = suite dir,
//                                             {test} = fresh empty scratch dir for each test
//   cwd ..                                    working directory (relative to the suite)
//   env KEY=VALUE                             extra environment
//   size 1180x760   scale 1.5                 logical window size and UI scale
//   baselines baselines                       baseline screenshot dir (relative to the suite)
//   threshold 0.001                           allowed fraction of differing pixels
//   test "name"                               starts a test; steps follow (indentation optional)
// Steps:
//   click TEXT [nth]   dblclick TEXT   click-at X Y   move X Y   drag X1 Y1 X2 Y2 [steps]
//   drag-text TEXT DX DY   type TEXT   key NAME [mods]   scroll DY [X Y]   wait FRAMES
//   settle   resize W H   dark on|off   raw JSON
//   expect-text TEXT [count] (substring)   expect-exact TEXT [count] (whole text)   expect-no-text TEXT
// Locators (click, dblclick, drag-text) prefer an exact whole-text match, then a substring.
//   expect-class TEXT TOKEN    expect-no-class TEXT TOKEN   (element or its 3 nearest ancestors)
//   expect-frame-ms MAX        (performance budget, from `info`)
//   screenshot NAME            (compared with baselines/NAME.png; --update rewrites it)
package vui_test

import "core:encoding/json"
import "core:fmt"
import "core:net"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:time"
import stbi "vendor:stb/image"

Suite :: struct {
	path, dir:   string,
	app:         []string,
	cwd:         string,
	env:         [dynamic]string,
	size:        string,
	scale:       string,
	baselines:   string,
	threshold:   f64,
	tests:       [dynamic]Test,
}

Step :: struct {
	line: int,
	args: []string,
}

Test :: struct {
	name:  string,
	steps: [dynamic]Step,
}

Step_Result :: struct {
	text:   string,
	ok:     bool,
	msg:    string,
	ms:     f64,
	shot:   string, // screenshot file (relative to out)
	base:   string,
	diff:   string,
}

Test_Result :: struct {
	name:  string,
	ok:    bool,
	ms:    f64,
	steps: [dynamic]Step_Result,
	fail_shot: string,
}

g_port := 7461
g_update := false
g_out := "vui-test-results"
g_gpu := false

main :: proc() {
	files: [dynamic]string
	args := os.args[1:]
	for i := 0; i < len(args); i += 1 {
		a := args[i]
		switch {
		case a == "--update":
			g_update = true
		case a == "--headed-gpu":
			g_gpu = true
		case a == "--out" && i + 1 < len(args):
			i += 1
			g_out = args[i]
		case a == "--port" && i + 1 < len(args):
			i += 1
			g_port, _ = strconv.parse_int(args[i])
		case a == "-h" || a == "--help":
			fmt.println("usage: vui-test [--update] [--out DIR] [--port N] suite.vt ...")
			return
		case:
			append(&files, a)
		}
	}
	if len(files) == 0 {
		fmt.eprintln("vui-test: no suite files")
		os.exit(2)
	}
	_ = os.make_directory_all(g_out)
	abs_out, _ := filepath.abs(g_out, context.allocator)
	g_out = abs_out

	all: [dynamic]Test_Result
	failed := 0
	t0 := time.now()
	for f in files {
		s, ok := parse_suite(f)
		if !ok {
			os.exit(2)
		}
		fmt.printfln("\n%s", f)
		for &t in s.tests {
			r := run_test(&s, &t)
			append(&all, r)
			mark := "\x1b[32m✓\x1b[0m" if r.ok else "\x1b[31m✗\x1b[0m"
			fmt.printfln("  %s %s (%.0f ms)", mark, r.name, r.ms)
			if !r.ok {
				failed += 1
				for st in r.steps {
					if !st.ok {
						fmt.printfln("      %s\n      → %s", st.text, st.msg)
					}
				}
			}
		}
	}
	write_report(all[:], time.duration_milliseconds(time.since(t0)))
	fmt.printfln("\n%d passed, %d failed  ·  report: %s/report.html", len(all) - failed, failed, g_out)
	os.exit(failed > 0 ? 1 : 0)
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

tokenize :: proc(line: string) -> []string {
	out: [dynamic]string
	i := 0
	for i < len(line) {
		for i < len(line) && (line[i] == ' ' || line[i] == '\t') {
			i += 1
		}
		if i >= len(line) {
			break
		}
		if line[i] == '#' {
			break
		}
		if line[i] == '"' {
			j := i + 1
			sb := strings.builder_make()
			for j < len(line) && line[j] != '"' {
				if line[j] == '\\' && j + 1 < len(line) {
					j += 1
				}
				strings.write_byte(&sb, line[j])
				j += 1
			}
			append(&out, strings.to_string(sb))
			i = j + 1
		} else if line[i] == '\'' {
			j := i + 1
			for j < len(line) && line[j] != '\'' {
				j += 1
			}
			append(&out, line[i + 1:j])
			i = j + 1
		} else {
			j := i
			for j < len(line) && line[j] != ' ' && line[j] != '\t' {
				j += 1
			}
			append(&out, line[i:j])
			i = j
		}
	}
	return out[:]
}

parse_suite :: proc(path: string) -> (s: Suite, ok: bool) {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fmt.eprintfln("vui-test: cannot read %s: %v", path, err)
		return
	}
	abs, _ := filepath.abs(path, context.allocator)
	s.path = abs
	s.dir = filepath.dir(abs)
	s.threshold = 0.001
	s.size = "1180x760"
	s.scale = "1"
	cur: ^Test
	text := string(data)
	ln := 0
	for line in strings.split_lines_iterator(&text) {
		ln += 1
		tk := tokenize(line)
		if len(tk) == 0 {
			continue
		}
		switch tk[0] {
		case "app":
			s.app = tk[1:]
		case "cwd":
			s.cwd = pj(s.dir, tk[1])
		case "env":
			append(&s.env, tk[1])
		case "size":
			s.size = tk[1]
		case "scale":
			s.scale = tk[1]
		case "baselines":
			s.baselines = pj(s.dir, tk[1])
		case "threshold":
			s.threshold, _ = strconv.parse_f64(tk[1])
		case "test":
			append(&s.tests, Test{name = len(tk) > 1 ? tk[1] : fmt.aprintf("test %d", len(s.tests) + 1)})
			cur = &s.tests[len(s.tests) - 1]
		case:
			if cur == nil {
				fmt.eprintfln("%s:%d: step outside a test: %s", path, ln, line)
				return
			}
			append(&cur.steps, Step{line = ln, args = tk})
		}
	}
	if len(s.app) == 0 {
		fmt.eprintfln("%s: missing `app` directive", path)
		return
	}
	if s.cwd == "" {
		s.cwd = s.dir
	}
	return s, true
}

// ---------------------------------------------------------------------------
// Control connection
// ---------------------------------------------------------------------------

ctl :: proc(msg: string, timeout_ms := 15000) -> (json.Object, string, bool) {
	sock, err := net.dial_tcp(net.Endpoint{address = net.IP4_Loopback, port = g_port})
	if err != nil {
		return nil, "", false
	}
	defer net.close(sock)
	line := strings.concatenate({msg, "\n"}, context.temp_allocator)
	if _, serr := net.send_tcp(sock, transmute([]u8)line); serr != nil {
		return nil, "", false
	}
	buf: [1 << 16]u8
	acc := strings.builder_make(context.temp_allocator)
	for {
		n, rerr := net.recv_tcp(sock, buf[:])
		if rerr != nil || n <= 0 {
			break
		}
		strings.write_bytes(&acc, buf[:n])
		if buf[n - 1] == '\n' {
			break
		}
	}
	out := strings.trim_space(strings.to_string(acc))
	v, perr := json.parse_string(out, allocator = context.temp_allocator)
	if perr != nil {
		return nil, out, false
	}
	obj, _ := v.(json.Object)
	ok, _ := obj["ok"].(json.Boolean)
	return obj, out, bool(ok)
}

jstr :: proc(s: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	strings.write_byte(&sb, '"')
	for c in s {
		switch c {
		case '"':
			strings.write_string(&sb, `\"`)
		case '\\':
			strings.write_string(&sb, `\\`)
		case '\n':
			strings.write_string(&sb, `\n`)
		case:
			strings.write_rune(&sb, c)
		}
	}
	strings.write_byte(&sb, '"')
	return strings.to_string(sb)
}

num :: proc(v: json.Value) -> f64 {
	#partial switch x in v {
	case json.Float:
		return f64(x)
	case json.Integer:
		return f64(x)
	}
	return 0
}

// ---------------------------------------------------------------------------
// Running
// ---------------------------------------------------------------------------

slug :: proc(s: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	for c in strings.to_lower(s, context.temp_allocator) {
		if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
			strings.write_rune(&sb, c)
		} else if strings.builder_len(sb) > 0 {
			strings.write_byte(&sb, '-')
		}
	}
	return strings.trim_right(strings.to_string(sb), "-")
}

launch :: proc(s: ^Suite, test_dir: string) -> (os.Process, bool) {
	cmd := make([]string, len(s.app))
	for a, i in s.app {
		x, _ := strings.replace_all(a, "{out}", g_out)
		x, _ = strings.replace_all(x, "{dir}", s.dir)
		x, _ = strings.replace_all(x, "{test}", test_dir)
		cmd[i] = x
	}
	if strings.contains(cmd[0], "/") && !filepath.is_abs(cmd[0]) {
		cmd[0] = pj(s.cwd, cmd[0]) // executable path is relative to the suite's cwd
	}
	env, _ := os.environ(context.allocator)
	envs: [dynamic]string
	for e in env {
		if strings.has_prefix(e, "VUI_") {
			continue // the runner owns the VUI_* environment
		}
		append(&envs, e)
	}
	append(&envs, "VUI_HIDDEN=1", "VUI_QUIET=1", fmt.aprintf("VUI_PORT=%d", g_port), fmt.aprintf("VUI_SIZE=%s", s.size), fmt.aprintf("VUI_SCALE=%s", s.scale))
	if g_gpu {
		append(&envs, "VUI_HIDDEN_GPU=1")
	}
	for e in s.env {
		x, _ := strings.replace_all(e, "{out}", g_out)
		x, _ = strings.replace_all(x, "{test}", test_dir)
		append(&envs, x)
	}
	log_path := pj(g_out, "app.log")
	logf, _ := os.open(log_path, {.Write, .Create, .Append})
	p, err := os.process_start({working_dir = s.cwd, command = cmd, env = envs[:], stdout = logf, stderr = logf})
	if err != nil {
		fmt.eprintfln("vui-test: cannot start %v: %v", cmd, err)
		return {}, false
	}
	deadline := time.now()
	for time.since(deadline) < 15 * time.Second {
		if _, _, ok := ctl(`{"cmd":"ping"}`); ok {
			// safety: never drive a headless app that is not sandboxed unless asked
			info, _, _ := ctl(`{"cmd":"info"}`)
			sb, _ := info["sandboxed"].(json.Boolean)
			if !bool(sb) && !g_gpu {
				fmt.eprintln("vui-test: app is not sandboxed (old vinland-ui?) — refusing to run on the real GPU")
				_ = os.process_kill(p)
				return {}, false
			}
			return p, true
		}
		time.sleep(100 * time.Millisecond)
	}
	fmt.eprintln("vui-test: app did not open its control port; see", log_path)
	_ = os.process_kill(p)
	return {}, false
}

stop :: proc(p: os.Process) {
	ctl(`{"cmd":"quit"}`)
	if _, err := os.process_wait(p, 3 * time.Second); err != nil {
		_ = os.process_kill(p)
		_, _ = os.process_wait(p, 2 * time.Second)
	}
}

run_test :: proc(s: ^Suite, t: ^Test) -> (r: Test_Result) {
	r.name = t.name
	r.ok = true
	t0 := time.now()
	// fresh scratch dir per test ({test}), like a new browser context
	test_dir := pj(g_out, "tmp", slug(t.name))
	_ = os.remove_all(test_dir)
	_ = os.make_directory_all(test_dir)
	p, ok := launch(s, test_dir)
	if !ok {
		r.ok = false
		append(&r.steps, Step_Result{text = "launch", ok = false, msg = "app failed to start"})
		return
	}
	for st in t.steps {
		s0 := time.now()
		res := run_step(s, t, st)
		res.ms = time.duration_milliseconds(time.since(s0))
		append(&r.steps, res)
		free_all(context.temp_allocator)
		if !res.ok {
			r.ok = false
			name := fmt.aprintf("FAIL-%s.png", slug(t.name))
			ctl(fmt.tprintf(`{{"cmd":"screenshot","path":%s}}`, jstr(pj(g_out, name))))
			r.fail_shot = name
			break
		}
	}
	stop(p)
	r.ms = time.duration_milliseconds(time.since(t0))
	return
}

// Locator: an element whose whole text equals TEXT wins; otherwise substring matches
// (case-insensitive), like Playwright's getByText with exact-first semantics.
locate :: proc(text: string, nth := 0) -> (obj: json.Object, exact: bool, ok: bool) {
	o, _, k := ctl(fmt.tprintf(`{{"cmd":"find","text":%s,"nth":%d,"exact":true}}`, jstr(text), nth))
	if k && bool(o["found"].(json.Boolean) or_else false) {
		return o, true, true
	}
	o, _, k = ctl(fmt.tprintf(`{{"cmd":"find","text":%s,"nth":%d}}`, jstr(text), nth))
	if k && bool(o["found"].(json.Boolean) or_else false) {
		return o, false, true
	}
	return nil, false, false
}

find_node :: proc(text: string, exact := false) -> (count: int) {
	obj, _, ok := ctl(fmt.tprintf(`{{"cmd":"find","text":%s,"exact":%v}}`, jstr(text), exact))
	if !ok {
		return 0
	}
	return int(num(obj["count"]))
}

// element (exact text match preferred) and its ancestors' classes
classes_for :: proc(text: string) -> (classes: [dynamic]string, found: bool) {
	obj, _, ok := ctl(`{"cmd":"tree","depth":64}`)
	if !ok {
		return
	}
	nodes, _ := obj["nodes"].(json.Array)
	idx := -1
	for pass in 0 ..< 2 {
		for n, i in nodes {
			o := n.(json.Object) or_continue
			t, _ := o["t"].(json.String)
			if (pass == 0 && string(t) == text) || (pass == 1 && strings.contains(string(t), text)) {
				idx = i
				break
			}
		}
		if idx >= 0 {
			break
		}
	}
	if idx < 0 {
		return
	}
	found = true
	o := nodes[idx].(json.Object)
	d := int(num(o["d"]))
	c, _ := o["c"].(json.String)
	append(&classes, string(c))
	for i := idx - 1; i >= 0 && len(classes) < 4; i -= 1 {
		po := nodes[i].(json.Object) or_continue
		pd := int(num(po["d"]))
		if pd < d {
			pc, _ := po["c"].(json.String)
			append(&classes, string(pc))
			d = pd
		}
	}
	return
}

has_token :: proc(class, token: string) -> bool {
	c := class
	for part in strings.fields_iterator(&c) {
		if part == token {
			return true
		}
	}
	return false
}

run_step :: proc(s: ^Suite, t: ^Test, st: Step) -> (res: Step_Result) {
	a := st.args
	res.text = strings.join(a, " ")
	res.ok = true
	arg :: proc(a: []string, i: int, def := "") -> string {
		return a[i] if i < len(a) else def
	}
	fail :: proc(res: ^Step_Result, msg: string) {
		res.ok = false
		res.msg = strings.clone(msg)
	}
	send :: proc(res: ^Step_Result, msg: string) {
		_, out, ok := ctl(msg)
		if !ok {
			fail(res, out if out != "" else "no response from app")
		}
	}
	switch a[0] {
	case "click", "click-text", "dblclick":
		nth, _ := strconv.parse_int(arg(a, 2, "0"))
		obj, _, ok := locate(arg(a, 1), nth)
		if !ok {
			fail(&res, fmt.tprintf("text %q not found", arg(a, 1)))
			return
		}
		x := num(obj["x"]) + num(obj["w"]) / 2
		y := num(obj["y"]) + num(obj["h"]) / 2
		send(&res, fmt.tprintf(`{{"cmd":"click","x":%.1f,"y":%.1f,"clicks":%d}}`, x, y, a[0] == "dblclick" ? 2 : 1))
	case "click-at":
		send(&res, fmt.tprintf(`{{"cmd":"click","x":%s,"y":%s}}`, arg(a, 1), arg(a, 2)))
	case "move":
		send(&res, fmt.tprintf(`{{"cmd":"move","x":%s,"y":%s}}`, arg(a, 1), arg(a, 2)))
	case "drag", "drag-text":
		x1, y1, x2, y2: f64
		steps := 8
		if a[0] == "drag-text" {
			obj, _, ok := locate(arg(a, 1))
			if !ok {
				fail(&res, fmt.tprintf("text %q not found", arg(a, 1)))
				return
			}
			x1 = num(obj["x"]) + num(obj["w"]) / 2
			y1 = num(obj["y"]) + num(obj["h"]) / 2
			dx, _ := strconv.parse_f64(arg(a, 2, "0"))
			dy, _ := strconv.parse_f64(arg(a, 3, "0"))
			x2, y2 = x1 + dx, y1 + dy
		} else {
			x1, _ = strconv.parse_f64(arg(a, 1))
			y1, _ = strconv.parse_f64(arg(a, 2))
			x2, _ = strconv.parse_f64(arg(a, 3))
			y2, _ = strconv.parse_f64(arg(a, 4))
			if len(a) > 5 {
				steps, _ = strconv.parse_int(a[5])
			}
		}
		send(&res, fmt.tprintf(`{{"cmd":"down","x":%.1f,"y":%.1f}}`, x1, y1))
		for i in 1 ..= steps {
			f := f64(i) / f64(steps)
			send(&res, fmt.tprintf(`{{"cmd":"move","x":%.1f,"y":%.1f}}`, x1 + (x2 - x1) * f, y1 + (y2 - y1) * f))
		}
		send(&res, fmt.tprintf(`{{"cmd":"up","x":%.1f,"y":%.1f}}`, x2, y2))
	case "type":
		send(&res, fmt.tprintf(`{{"cmd":"type","text":%s}}`, jstr(arg(a, 1))))
	case "key":
		send(&res, fmt.tprintf(`{{"cmd":"key","key":%s,"mods":%s}}`, jstr(arg(a, 1)), jstr(arg(a, 2))))
	case "scroll":
		if len(a) > 3 {
			send(&res, fmt.tprintf(`{{"cmd":"scroll","dy":%s,"x":%s,"y":%s}}`, arg(a, 1), arg(a, 2), arg(a, 3)))
		} else {
			send(&res, fmt.tprintf(`{{"cmd":"scroll","dy":%s}}`, arg(a, 1)))
		}
	case "wait":
		send(&res, fmt.tprintf(`{{"cmd":"wait","frames":%s}}`, arg(a, 1, "2")))
	case "settle":
		send(&res, `{"cmd":"settle"}`)
	case "resize":
		send(&res, fmt.tprintf(`{{"cmd":"resize","w":%s,"h":%s}}`, arg(a, 1), arg(a, 2)))
		send(&res, `{"cmd":"wait","frames":3}`)
	case "dark":
		send(&res, fmt.tprintf(`{{"cmd":"dark","on":%v}}`, arg(a, 1) == "on"))
	case "raw":
		send(&res, arg(a, 1))
	case "expect-text", "expect-exact":
		n := find_node(arg(a, 1), a[0] == "expect-exact")
		if len(a) > 2 {
			want, _ := strconv.parse_int(a[2])
			if n != want {
				fail(&res, fmt.tprintf("expected %d matches of %q, found %d", want, a[1], n))
			}
		} else if n == 0 {
			fail(&res, fmt.tprintf("text %q not visible", a[1]))
		}
	case "expect-no-text":
		if n := find_node(arg(a, 1)); n > 0 {
			fail(&res, fmt.tprintf("text %q is visible (%d matches)", a[1], n))
		}
	case "expect-class", "expect-no-class":
		classes, found := classes_for(arg(a, 1))
		if !found {
			fail(&res, fmt.tprintf("text %q not found", a[1]))
			return
		}
		hit := false
		for c in classes {
			if has_token(c, arg(a, 2)) {
				hit = true
			}
		}
		want := a[0] == "expect-class"
		if hit != want {
			fail(&res, fmt.tprintf("%q: class %q %s; classes: %v", a[1], a[2], want ? "missing" : "present", classes[:]))
		}
	case "expect-frame-ms":
		send(&res, `{"cmd":"settle"}`)
		obj, _, _ := ctl(`{"cmd":"info"}`)
		ms := num(obj["frame_ms"])
		lim, _ := strconv.parse_f64(arg(a, 1, "16"))
		if ms > lim {
			fail(&res, fmt.tprintf("frame took %.2f ms, budget %.2f ms (software renderer)", ms, lim))
		} else {
			res.msg = fmt.aprintf("%.2f ms", ms)
		}
	case "screenshot":
		name := fmt.aprintf("%s--%s.png", slug(t.name), slug(arg(a, 1, "shot")))
		path := pj(g_out, name)
		send(&res, fmt.tprintf(`{{"cmd":"screenshot","path":%s}}`, jstr(path)))
		res.shot = name
		if res.ok && s.baselines != "" {
			base := pj(s.baselines, fmt.tprintf("%s.png", slug(arg(a, 1, "shot"))))
			if g_update || !os.exists(base) {
				_ = os.make_directory_all(s.baselines)
				data, _ := os.read_entire_file(path, context.allocator)
				_ = os.write_entire_file(base, data)
				res.msg = "baseline written"
			} else {
				res.base = base
				ratio, msg := compare(path, base, pj(g_out, fmt.tprintf("diff-%s", name)))
				if msg != "" {
					fail(&res, msg)
				} else if ratio > s.threshold {
					res.diff = fmt.aprintf("diff-%s", name)
					fail(&res, fmt.tprintf("screenshot differs from baseline: %.3f%% of pixels (threshold %.3f%%)", ratio * 100, s.threshold * 100))
				} else {
					res.msg = fmt.aprintf("matches baseline (%.4f%% diff)", ratio * 100)
				}
			}
		}
	case:
		fail(&res, fmt.tprintf("unknown step %q (line %d)", a[0], st.line))
	}
	return
}

// Fraction of pixels that differ by more than a small tolerance; writes a diff image.
compare :: proc(a_path, b_path, diff_path: string) -> (ratio: f64, err: string) {
	aw, ah, bw, bh, ch: i32
	ca := strings.clone_to_cstring(a_path, context.temp_allocator)
	cb := strings.clone_to_cstring(b_path, context.temp_allocator)
	pa := stbi.load(ca, &aw, &ah, &ch, 4)
	pb := stbi.load(cb, &bw, &bh, &ch, 4)
	defer if pa != nil {stbi.image_free(pa)}
	defer if pb != nil {stbi.image_free(pb)}
	if pa == nil || pb == nil {
		return 1, "cannot decode screenshot or baseline"
	}
	if aw != bw || ah != bh {
		return 1, fmt.tprintf("size %dx%d differs from baseline %dx%d", aw, ah, bw, bh)
	}
	n := int(aw * ah)
	diff := make([]u8, n * 4, context.temp_allocator)
	bad := 0
	for i in 0 ..< n {
		d := 0
		for k in 0 ..< 3 {
			d = max(d, abs(int(pa[i * 4 + k]) - int(pb[i * 4 + k])))
		}
		g := u8((int(pa[i * 4]) + int(pa[i * 4 + 1]) + int(pa[i * 4 + 2])) / 12)
		if d > 24 {
			bad += 1
			diff[i * 4], diff[i * 4 + 1], diff[i * 4 + 2] = 255, 40, 40
		} else {
			diff[i * 4], diff[i * 4 + 1], diff[i * 4 + 2] = g, g, g
		}
		diff[i * 4 + 3] = 255
	}
	if bad > 0 {
		cd := strings.clone_to_cstring(diff_path, context.temp_allocator)
		stbi.write_png(cd, aw, ah, 4, raw_data(diff), aw * 4)
	}
	return f64(bad) / f64(n), ""
}

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------

pj :: proc(parts: ..string) -> string {
	r, _ := filepath.join(parts)
	return r
}

html_esc :: proc(s: string) -> string {
	r, _ := strings.replace_all(s, "&", "&amp;", context.temp_allocator)
	r, _ = strings.replace_all(r, "<", "&lt;", context.temp_allocator)
	r, _ = strings.replace_all(r, ">", "&gt;", context.temp_allocator)
	return r
}

write_report :: proc(results: []Test_Result, total_ms: f64) {
	h := strings.builder_make()
	j := strings.builder_make()
	passed := 0
	for r in results {
		if r.ok {
			passed += 1
		}
	}
	fmt.sbprintf(&h, `<!doctype html><meta charset=utf-8><title>vui-test report</title><style>
body{{font:14px/1.5 system-ui,sans-serif;margin:0;background:#0b0d12;color:#e5e7eb}}main{{max-width:1100px;margin:auto;padding:32px}}
h1{{font-size:20px}}.t{{border:1px solid #262a33;border-radius:8px;margin:12px 0;overflow:hidden}}
.t>summary{{padding:10px 14px;cursor:pointer;display:flex;gap:10px}}.ok{{color:#4ade80}}.ko{{color:#f87171}}
.s{{padding:4px 14px;font:12px/1.6 ui-monospace,monospace;border-top:1px solid #1a1d24;display:flex;gap:12px}}
.s span:first-child{{flex:1}}.m{{color:#9ca3af}}img{{max-width:100%%;border:1px solid #262a33;border-radius:6px;margin:6px 14px 10px}}
</style><main><h1>vui-test · %d/%d passed · %.1f s</h1><p class=m>Headless and sandboxed (software rendering, no GPU or compositor access).</p>`, passed, len(results), total_ms / 1000)
	strings.write_string(&j, `{"tests":[`)
	for r, ti in results {
		fmt.sbprintf(&h, `<details class=t %s><summary><b class=%s>%s</b><span>%s</span><span class=m>%.0f ms</span></summary>`, r.ok ? "" : "open", r.ok ? "ok" : "ko", r.ok ? "✓" : "✗", html_esc(r.name), r.ms)
		if ti > 0 {
			strings.write_string(&j, ",")
		}
		fmt.sbprintf(&j, `{{"name":%s,"ok":%v,"ms":%.1f,"steps":[`, jstr(r.name), r.ok, r.ms)
		for st, si in r.steps {
			fmt.sbprintf(&h, `<div class=s><span class=%s>%s %s</span><span class=m>%s</span><span class=m>%.0f ms</span></div>`, st.ok ? "" : "ko", st.ok ? "·" : "✗", html_esc(st.text), html_esc(st.msg), st.ms)
			if st.shot != "" {
				fmt.sbprintf(&h, `<img src="%s" loading=lazy>`, st.shot)
			}
			if st.diff != "" {
				fmt.sbprintf(&h, `<img src="%s" loading=lazy>`, st.diff)
			}
			if si > 0 {
				strings.write_string(&j, ",")
			}
			fmt.sbprintf(&j, `{{"step":%s,"ok":%v,"msg":%s,"ms":%.1f,"screenshot":%s}}`, jstr(st.text), st.ok, jstr(st.msg), st.ms, jstr(st.shot))
		}
		if r.fail_shot != "" {
			fmt.sbprintf(&h, `<img src="%s">`, r.fail_shot)
		}
		strings.write_string(&h, "</details>")
		strings.write_string(&j, "]}")
	}
	strings.write_string(&h, "</main>")
	fmt.sbprintf(&j, `],"passed":%d,"failed":%d}}`, passed, len(results) - passed)
	_ = os.write_entire_file(pj(g_out, "report.html"), strings.to_string(h))
	_ = os.write_entire_file(pj(g_out, "report.json"), strings.to_string(j))
}
