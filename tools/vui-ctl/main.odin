// vui-ctl: drive a running vinland-ui app over its control port.
//
//   vui-ctl [--port N] <command> [args...]
//
//   ping | info | tree [depth]
//   screenshot <path.png> [x y w h]       (crop in logical px)
//   click <x> <y> [right|double]          (logical px)
//   click-text <text> [nth]
//   move <x> <y>
//   scroll <dy> [x y] [dx]
//   type <text> | key <name> [shift,ctrl,alt]
//   resize <w> <h> | dark [on|off] | gamma <value>
//   wait [frames] | settle | quit
//   raw '<json>'                          (send any JSON command)
//   <app-command> [key=value ...]         (forwarded to the app, e.g. nav page=padding)
package vui_ctl

import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"

usage :: proc() {
	fmt.eprintln(`usage: vui-ctl [--port N] <command> [args...]
commands:
  ping | info | tree [depth]
  screenshot <path.png> [x y w h]
  click <x> <y> [right|double] | click-text <text> [nth] | move <x> <y>
  scroll <dy> [x y] [dx] | type <text> | key <name> [mods]
  resize <w> <h> | dark [on|off] | gamma <value>
  wait [frames] | settle | quit | raw '<json>'
  <app-command> [key=value ...]`)
}

q :: proc(sb: ^strings.Builder, s: string) {
	strings.write_byte(sb, '"')
	for r in s {
		switch r {
		case '"':
			strings.write_string(sb, `\"`)
		case '\\':
			strings.write_string(sb, `\\`)
		case '\n':
			strings.write_string(sb, `\n`)
		case:
			strings.write_rune(sb, r)
		}
	}
	strings.write_byte(sb, '"')
}

is_number :: proc(s: string) -> bool {
	_, ok := strconv.parse_f64(s)
	return ok
}

main :: proc() {
	args := os.args[1:]
	port := 7420
	if env := os.get_env("VUI_PORT", context.temp_allocator); env != "" {
		port, _ = strconv.parse_int(env)
	}
	for len(args) >= 2 && args[0] == "--port" {
		port, _ = strconv.parse_int(args[1])
		args = args[2:]
	}
	if len(args) == 0 {
		usage()
		os.exit(2)
	}
	cmd := args[0]
	rest := args[1:]
	sb := strings.builder_make()
	arg := proc(rest: []string, i: int, def := "") -> string {
		return i < len(rest) ? rest[i] : def
	}
	switch cmd {
	case "raw":
		strings.write_string(&sb, arg(rest, 0, "{}"))
	case "screenshot":
		strings.write_string(&sb, `{"cmd":"screenshot","path":`)
		path := arg(rest, 0, "screenshot.png")
		if !strings.has_prefix(path, "/") {
			cwd, _ := os.get_working_directory(context.temp_allocator)
			path = strings.concatenate({cwd, "/", path})
		}
		q(&sb, path)
		if len(rest) >= 5 {
			fmt.sbprintf(&sb, `,"x":%s,"y":%s,"w":%s,"h":%s`, rest[1], rest[2], rest[3], rest[4])
		}
		strings.write_string(&sb, "}")
	case "click":
		fmt.sbprintf(&sb, `{{"cmd":"click","x":%s,"y":%s`, arg(rest, 0, "0"), arg(rest, 1, "0"))
		switch arg(rest, 2) {
		case "right":
			strings.write_string(&sb, `,"button":"right"`)
		case "double":
			strings.write_string(&sb, `,"clicks":2`)
		}
		strings.write_string(&sb, "}")
	case "click-text":
		strings.write_string(&sb, `{"cmd":"click_text","text":`)
		q(&sb, arg(rest, 0))
		fmt.sbprintf(&sb, `,"nth":%s}}`, arg(rest, 1, "0"))
	case "move":
		fmt.sbprintf(&sb, `{{"cmd":"move","x":%s,"y":%s}}`, arg(rest, 0, "0"), arg(rest, 1, "0"))
	case "scroll":
		fmt.sbprintf(&sb, `{{"cmd":"scroll","dy":%s`, arg(rest, 0, "100"))
		if len(rest) >= 3 {
			fmt.sbprintf(&sb, `,"x":%s,"y":%s`, rest[1], rest[2])
		}
		if len(rest) >= 4 {
			fmt.sbprintf(&sb, `,"dx":%s`, rest[3])
		}
		strings.write_string(&sb, "}")
	case "type":
		strings.write_string(&sb, `{"cmd":"type","text":`)
		q(&sb, strings.join(rest, " "))
		strings.write_string(&sb, "}")
	case "key":
		strings.write_string(&sb, `{"cmd":"key","key":`)
		q(&sb, arg(rest, 0, "tab"))
		strings.write_string(&sb, `,"mods":`)
		q(&sb, arg(rest, 1))
		strings.write_string(&sb, "}")
	case "resize":
		fmt.sbprintf(&sb, `{{"cmd":"resize","w":%s,"h":%s}}`, arg(rest, 0, "1280"), arg(rest, 1, "800"))
	case "dark":
		v := arg(rest, 0, "toggle")
		if v == "toggle" {
			strings.write_string(&sb, `{"cmd":"dark"}`)
		} else {
			fmt.sbprintf(&sb, `{{"cmd":"dark","on":%v}}`, v == "on" || v == "true" || v == "1")
		}
	case "gamma":
		fmt.sbprintf(&sb, `{{"cmd":"gamma","value":%s}}`, arg(rest, 0, "1"))
	case "tree":
		fmt.sbprintf(&sb, `{{"cmd":"tree","depth":%s}}`, arg(rest, 0, "64"))
	case "wait":
		fmt.sbprintf(&sb, `{{"cmd":"wait","frames":%s}}`, arg(rest, 0, "2"))
	case "-h", "--help", "help":
		usage()
		return
	case:
		strings.write_string(&sb, `{"cmd":`)
		q(&sb, cmd)
		for a in rest {
			eq := strings.index_byte(a, '=')
			if eq < 0 {
				continue
			}
			strings.write_string(&sb, ",")
			q(&sb, a[:eq])
			strings.write_string(&sb, ":")
			v := a[eq + 1:]
			if is_number(v) || v == "true" || v == "false" {
				strings.write_string(&sb, v)
			} else {
				q(&sb, v)
			}
		}
		strings.write_string(&sb, "}")
	}
	strings.write_byte(&sb, '\n')

	sock, err := net.dial_tcp(net.Endpoint{address = net.IP4_Loopback, port = port})
	if err != nil {
		fmt.eprintfln("vui-ctl: cannot connect to 127.0.0.1:%d (%v). Is the app running with a control port?", port, err)
		os.exit(1)
	}
	defer net.close(sock)
	msg := strings.to_string(sb)
	if _, serr := net.send_tcp(sock, transmute([]u8)msg); serr != nil {
		fmt.eprintln("vui-ctl: send failed:", serr)
		os.exit(1)
	}
	buf: [1 << 16]u8
	acc := strings.builder_make()
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
	fmt.println(out)
	if strings.contains(out, `"ok":false`) {
		os.exit(1)
	}
}
