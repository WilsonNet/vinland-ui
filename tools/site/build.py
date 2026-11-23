#!/usr/bin/env python3
"""Builds the vinland-ui website (static HTML for GitHub Pages) from the running showroom.

Every page's text, tables and code are exported as real HTML (indexable); every live example
is captured by the showroom itself (light and dark, 2x) through the control port.

    python3 tools/site/build.py [out_dir] [--pages slug,slug] [--no-shots]

Requires: build/showroom and build/vui-ctl (./build.sh release), ImageMagick (`magick`).
"""
import html
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORT = 7431
SCALE = 2
WIDTH = 1280
VIEW_H = 1000  # never render tall windows: shared-memory GPUs run out of VRAM
BASE_URL = "https://wilsonnet.github.io/vinland-ui/"
REPO = "https://github.com/WilsonNet/vinland-ui"


def ctl(cmd: dict, timeout=60):
    with socket.create_connection(("127.0.0.1", PORT), timeout=timeout) as s:
        s.sendall((json.dumps(cmd) + "\n").encode())
        buf = b""
        while not buf.endswith(b"\n"):
            chunk = s.recv(1 << 20)
            if not chunk:
                break
            buf += chunk
    res = json.loads(buf)
    if not res.get("ok", True):
        raise RuntimeError(f"{cmd}: {res}")
    return res


# --------------------------------------------------------------------------- Odin highlighting

KEYWORDS = set("if else for in proc return switch case defer when struct enum union import package true false nil do not_in break continue using map dynamic".split())


def highlight(src: str) -> str:
    out = []
    for line in src.split("\n"):
        i = 0
        n = len(line)
        parts = []
        while i < n:
            c = line[i]
            if line.startswith("//", i):
                parts.append(f'<span class="t-c">{html.escape(line[i:])}</span>')
                break
            if c in "\"`":
                j = i + 1
                while j < n and line[j] != c:
                    if line[j] == "\\" and c == '"':
                        j += 1
                    j += 1
                j = min(j + 1, n)
                parts.append(f'<span class="t-s">{html.escape(line[i:j])}</span>')
                i = j
                continue
            if c.isdigit():
                m = re.match(r"[0-9A-Za-z_.]+", line[i:])
                parts.append(f'<span class="t-n">{html.escape(m.group(0))}</span>')
                i += len(m.group(0))
                continue
            if c.isalpha() or c == "_":
                m = re.match(r"[A-Za-z0-9_]+", line[i:])
                w = m.group(0)
                j = i + len(w)
                if w in KEYWORDS:
                    cls = "t-k"
                elif j < n and line[j] == ".":
                    cls = "t-p"
                elif j < n and line[j] == "(":
                    cls = "t-f"
                elif w[0].isupper():
                    cls = "t-t"
                else:
                    cls = "t-i"
                parts.append(f'<span class="{cls}">{html.escape(w)}</span>')
                i = j
                continue
            j = i
            while j < n and not (line[j].isalnum() or line[j] in "_\"`") and not line.startswith("//", j):
                j += 1
            if j == i:
                j = i + 1
            parts.append(f'<span class="t-o">{html.escape(line[i:j])}</span>')
            i = j
        out.append("".join(parts))
    return "\n".join(out)


def rich(text: str) -> str:
    segs = text.split("`")
    out = []
    for k, seg in enumerate(segs):
        out.append(f"<code>{html.escape(seg)}</code>" if k % 2 else html.escape(seg))
    return "".join(out)


def slugify(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


# --------------------------------------------------------------------------- capture

def capture(out_dir: str, only: set, shots: bool):
    env = dict(os.environ, VUI_HIDDEN="1", VUI_SCALE=str(SCALE), VUI_SIZE=f"{WIDTH}x{VIEW_H}", VUI_PORT=str(PORT), VUI_QUIET="1")
    proc = subprocess.Popen([os.path.join(ROOT, "build/showroom")], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(100):
            try:
                ctl({"cmd": "ping"})
                break
            except OSError:
                time.sleep(0.1)
        pages = ctl({"cmd": "pages"})["pages"]
        img_dir = os.path.join(out_dir, "img")
        os.makedirs(img_dir, exist_ok=True)
        data = []
        for p in pages:
            slug = p["slug"]
            if only and slug not in only:
                continue
            ctl({"cmd": "dark", "on": False})
            ctl({"cmd": "nav", "page": slug})
            ctl({"cmd": "settle"})
            doc = ctl({"cmd": "export"})
            if shots:
                examples = [b for b in doc["blocks"] if b["kind"] == "Example"]
                top0 = 56  # content area top (below the top bar)
                for mode in ("light", "dark"):
                    ctl({"cmd": "dark", "on": mode == "dark"})
                    ctl({"cmd": "move", "x": 2, "y": 2})
                    for k, b in enumerate(examples):
                        # position of the example in content coordinates (from the unscrolled export)
                        y_content = b["rect"][1] - top0
                        ctl({"cmd": "scroll_content", "y": max(0, y_content - 40)})
                        ctl({"cmd": "settle"})
                        ctl({"cmd": "wait", "frames": 2})
                        cur = [x for x in ctl({"cmd": "export"})["blocks"] if x["kind"] == "Example"][k]
                        x, y, w, h = cur["rect"]
                        if y < top0 or y + h > VIEW_H or w <= 0 or h <= 0:
                            b["skip"] = True
                            continue
                        png = os.path.join(img_dir, f"{slug}-{k}-{mode}.png")
                        ctl({"cmd": "screenshot", "path": png, "x": x, "y": y, "w": w, "h": h})
                        webp = png[:-4] + ".webp"
                        subprocess.run(["magick", png, "-define", "webp:lossless=true", webp], check=True)
                        os.remove(png)
                        b["size"] = [w, h]
                    ctl({"cmd": "scroll_content", "y": 0})
            data.append(doc)
            print(f"  {slug}: {sum(1 for b in doc['blocks'] if b['kind'] == 'Example')} examples", flush=True)
        return pages, data
    finally:
        try:
            ctl({"cmd": "quit"}, timeout=5)
        except Exception:
            pass
        proc.wait(timeout=10)


# --------------------------------------------------------------------------- html

def page_html(doc, pages, groups, prev_p, next_p):
    slug = doc["slug"]
    title = doc["title"]
    desc = doc["desc"]
    body = []
    toc = []
    k = 0
    last_heading = title
    live = slug == "showcase"
    blocks = doc["blocks"]
    if blocks and blocks[0]["kind"] == "Para" and blocks[0].get("text") == desc:
        blocks = blocks[1:]
    for b in blocks:
        kind = b["kind"]
        if kind == "H2":
            a = slugify(b["text"])
            toc.append((2, b["text"], a))
            last_heading = b["text"]
            body.append(f'<h2 id="{a}">{html.escape(b["text"])}</h2>')
        elif kind == "H3":
            a = slugify(b["text"])
            toc.append((3, b["text"], a))
            last_heading = b["text"]
            body.append(f'<h3 id="{a}">{html.escape(b["text"])}</h3>')
        elif kind == "Para":
            body.append(f'<p>{rich(b["text"])}</p>')
        elif kind == "Note":
            body.append(f'<aside class="note"><svg viewBox="0 0 20 20" aria-hidden="true"><path fill="currentColor" fill-rule="evenodd" d="M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0Zm-7-4a1 1 0 1 1-2 0 1 1 0 0 1 2 0ZM9 9a.75.75 0 0 0 0 1.5h.253a.25.25 0 0 1 .244.304l-.459 2.066A1.75 1.75 0 0 0 10.747 15H11a.75.75 0 0 0 0-1.5h-.253a.25.25 0 0 1-.244-.304l.459-2.066A1.75 1.75 0 0 0 9.253 9H9Z"/></svg><p>{rich(b["text"])}</p></aside>')
        elif kind == "Table":
            rows = b["rows"]
            trs = "".join(f"<tr><td>{html.escape(c)}</td><td>{html.escape(e)}</td></tr>" for c, e in rows)
            more = ' class="ref long"' if len(rows) > 12 else ' class="ref"'
            body.append(f'<div{more}><table><thead><tr><th>Class</th><th>Effect</th></tr></thead><tbody>{trs}</tbody></table>'
                        + ('<button class="show-all" type="button">Show all ' + str(len(rows)) + '</button>' if len(rows) > 12 else '') + '</div>')
        elif kind == "Code":
            body.append(f'<figure class="fig"><pre class="code"><code>{highlight(b["code"])}</code></pre></figure>')
        elif kind == "Example":
            img = ""
            if not b.get("skip") and b.get("size"):
                w, h = b["size"]
                alt = f"{title}: {last_heading} (rendered by vinland-ui)"
                canvas = ""
                if live:
                    canvas = f'<canvas id="vui-{slugify(last_heading)}" tabindex="0" style="height:{h:.0f}px" aria-label="Live demo: {html.escape(last_heading)}"></canvas>'
                img = (f'<div class="preview">{canvas}<img class="only-light" src="img/{slug}-{k}-light.webp" width="{w:.0f}" height="{h:.0f}" alt="{html.escape(alt)}" loading="lazy">'
                       f'<img class="only-dark" src="img/{slug}-{k}-dark.webp" width="{w:.0f}" height="{h:.0f}" alt="{html.escape(alt)}" loading="lazy"></div>')
            body.append(f'<figure class="fig">{img}<pre class="code"><code>{highlight(b.get("code", ""))}</code></pre></figure>')
            k += 1

    nav = []
    for g in groups:
        items = "".join(
            f'<li><a href="{p["slug"]}.html"{" aria-current=\"page\"" if p["slug"] == slug else ""}>{html.escape(p["title"])}</a></li>'
            for p in pages if p["group"] == g)
        nav.append(f'<h5>{html.escape(g)}</h5><ul>{items}</ul>')
    toc_html = "".join(f'<li class="l{lvl}"><a href="#{a}">{html.escape(t)}</a></li>' for lvl, t, a in toc)
    footer = '<nav class="pager">'
    footer += f'<a href="{prev_p["slug"]}.html">← {html.escape(prev_p["title"])}</a>' if prev_p else "<span></span>"
    footer += f'<a href="{next_p["slug"]}.html">{html.escape(next_p["title"])} →</a>' if next_p else ""
    footer += "</nav>"
    is_home = slug == "introduction"
    page_title = "vinland-ui: utility-first UI framework for Odin" if is_home else f"{title} - {doc['group']} - vinland-ui (Odin UI framework)"
    meta_desc = desc if is_home else f"{desc.rstrip('.')}. vinland-ui brings Tailwind-style {title} utilities to native Odin apps, with live examples and copyable code."
    canonical = BASE_URL + ("" if is_home else f"{slug}.html")
    ld = [{
        "@context": "https://schema.org", "@type": "TechArticle", "headline": title,
        "description": meta_desc, "url": canonical, "inLanguage": "en",
        "isPartOf": {"@type": "WebSite", "name": "vinland-ui", "url": BASE_URL},
        "about": {"@type": "SoftwareSourceCode", "name": "vinland-ui", "codeRepository": REPO, "programmingLanguage": "Odin", "license": "https://opensource.org/licenses/MIT"},
    }, {
        "@context": "https://schema.org", "@type": "BreadcrumbList", "itemListElement": [
            {"@type": "ListItem", "position": 1, "name": "Docs", "item": BASE_URL},
            {"@type": "ListItem", "position": 2, "name": doc["group"], "item": canonical},
            {"@type": "ListItem", "position": 3, "name": title, "item": canonical},
        ],
    }]
    ld_json = json.dumps(ld).replace("</", "<\\/")
    live_script = '<script src="odin.js" defer></script><script src="live.js" defer></script>' if live else ""
    return f"""<!doctype html>
<html lang="en" id="vui-root">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(page_title)}</title>
<meta name="description" content="{html.escape(meta_desc)}">
<link rel="canonical" href="{canonical}">
<meta name="robots" content="index, follow">
<meta name="theme-color" content="#ffffff" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#030712" media="(prefers-color-scheme: dark)">
<meta property="og:type" content="{'website' if is_home else 'article'}">
<meta property="og:site_name" content="vinland-ui">
<meta property="og:url" content="{canonical}">
<meta property="og:title" content="{html.escape(page_title)}">
<meta property="og:description" content="{html.escape(meta_desc)}">
<meta property="og:image" content="{BASE_URL}img/og.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="750">
<meta property="og:image:alt" content="vinland-ui showroom: documentation rendered natively by the framework">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{html.escape(page_title)}">
<meta name="twitter:description" content="{html.escape(meta_desc)}">
<meta name="twitter:image" content="{BASE_URL}img/og.png">
<script type="application/ld+json">{ld_json}</script>
<link rel="icon" href="favicon.svg" type="image/svg+xml">
<link rel="preload" href="fonts/Inter-Regular.ttf" as="font" type="font/ttf" crossorigin>
<link rel="stylesheet" href="site.css">
<script>try{{var t=localStorage.getItem('theme');if(t==='dark'||(!t&&matchMedia('(prefers-color-scheme: dark)').matches))document.documentElement.classList.add('dark')}}catch(e){{}}</script>
</head>
<body>
<header class="top">
  <button class="menu" type="button" aria-label="Open navigation"><svg viewBox="0 0 20 20"><path fill="currentColor" fill-rule="evenodd" d="M2 4.75A.75.75 0 0 1 2.75 4h14.5a.75.75 0 0 1 0 1.5H2.75A.75.75 0 0 1 2 4.75ZM2 10a.75.75 0 0 1 .75-.75h14.5a.75.75 0 0 1 0 1.5H2.75A.75.75 0 0 1 2 10Zm0 5.25a.75.75 0 0 1 .75-.75h14.5a.75.75 0 0 1 0 1.5H2.75a.75.75 0 0 1-.75-.75Z"/></svg></button>
  <a class="brand" href="index.html"><span class="mark"><svg viewBox="0 0 32 32"><path d="M7 7h5.2l3.8 9.6L19.8 7H25l-7 17h-4L7 7Z"/><path d="M5 26.5c2 0 2.5-1.5 5.5-1.5s3.5 1.5 5.5 1.5 2.5-1.5 5.5-1.5 3.5 1.5 5.5 1.5V28c-2 0-2.5-1.5-5.5-1.5S18 28 16 28s-2.5-1.5-5.5-1.5S7 28 5 28v-1.5Z"/></svg></span>vinland-ui</a>
  <span class="ver">v0.1</span>
  <span class="grow"></span>
  <button class="search" type="button"><svg viewBox="0 0 20 20"><path fill="currentColor" fill-rule="evenodd" d="M9 3.5a5.5 5.5 0 1 0 0 11 5.5 5.5 0 0 0 0-11ZM2 9a7 7 0 1 1 12.452 4.391l3.328 3.329a.75.75 0 1 1-1.06 1.06l-3.329-3.328A7 7 0 0 1 2 9Z"/></svg>Search docs<kbd>Ctrl K</kbd></button>
  <nav class="links"><a href="index.html">Docs</a><a href="theme-tokens.html">Tokens</a><a href="showcase.html">Components</a></nav>
  <button class="theme" type="button" aria-label="Toggle dark mode"><svg class="sun" viewBox="0 0 20 20"><path fill="currentColor" d="M10 2a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0v-1.5A.75.75 0 0 1 10 2Zm0 13a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0v-1.5A.75.75 0 0 1 10 15Zm0-8a3 3 0 1 0 0 6 3 3 0 0 0 0-6Zm5.657-1.596a.75.75 0 1 0-1.06-1.06l-1.061 1.06a.75.75 0 0 0 1.06 1.06l1.06-1.06Zm-9.193 9.192a.75.75 0 1 0-1.06-1.06l-1.06 1.06a.75.75 0 0 0 1.06 1.06l1.06-1.06ZM18 10a.75.75 0 0 1-.75.75h-1.5a.75.75 0 0 1 0-1.5h1.5A.75.75 0 0 1 18 10ZM5 10a.75.75 0 0 1-.75.75h-1.5a.75.75 0 0 1 0-1.5h1.5A.75.75 0 0 1 5 10Zm9.596 5.657a.75.75 0 0 0 1.06-1.06l-1.06-1.061a.75.75 0 1 0-1.06 1.06l1.06 1.06ZM5.404 6.464a.75.75 0 0 0 1.06-1.06l-1.06-1.06a.75.75 0 1 0-1.061 1.06l1.06 1.06Z"/></svg><svg class="moon" viewBox="0 0 20 20"><path fill="currentColor" fill-rule="evenodd" d="M7.455 2.004a.75.75 0 0 1 .26.77 7 7 0 0 0 9.958 7.967.75.75 0 0 1 1.067.853A8.5 8.5 0 1 1 6.647 1.921a.75.75 0 0 1 .808.083Z"/></svg></button>
  <a class="gh" href="{REPO}" aria-label="GitHub repository"><svg viewBox="0 0 24 24"><path fill="currentColor" d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"/></svg></a>
</header>
<div class="body">
  <aside class="side"><nav>{"".join(nav)}</nav></aside>
  <div class="gutter"></div>
  <main>
    <article>
      <h1>{html.escape("vinland-ui: utility-first UI for Odin" if is_home else title)}</h1>
      <p class="lede">{rich(desc)}</p>
      {"".join(body)}
      {footer}
    </article>
  </main>
  <aside class="toc">{('<h5>On this page</h5><ul>' + toc_html + '</ul>') if toc else ''}</aside>
</div>
<div class="palette" hidden><div class="scrim"></div><div class="panel"><div class="field"><svg viewBox="0 0 20 20"><path fill="currentColor" fill-rule="evenodd" d="M9 3.5a5.5 5.5 0 1 0 0 11 5.5 5.5 0 0 0 0-11ZM2 9a7 7 0 1 1 12.452 4.391l3.328 3.329a.75.75 0 1 1-1.06 1.06l-3.329-3.328A7 7 0 0 1 2 9Z"/></svg><input type="search" placeholder="Search utilities and guides…" aria-label="Search"><kbd>Esc</kbd></div><ul class="results"></ul></div></div>
<script src="site.js" defer></script>
{live_script}
</body>
</html>
"""


def preserve_example_sizes(data: list, ref_path: str):
    """When --no-shots is used, carries over example image dimensions/skip flags from ref_path."""
    if not os.path.exists(ref_path):
        return
    old = {d["slug"]: d for d in json.load(open(ref_path)).get("docs", [])}
    for doc in data:
        prev = old.get(doc["slug"])
        if not prev:
            continue
        prev_ex = [b for b in prev.get("blocks", []) if b.get("kind") == "Example"]
        cur_ex = [b for b in doc.get("blocks", []) if b.get("kind") == "Example"]
        for cur, p in zip(cur_ex, prev_ex):
            if "size" in p:
                cur["size"] = p["size"]
            if "skip" in p:
                cur["skip"] = p["skip"]


def capture_only(img_parent: str, data_path: str, only: set, shots: bool = True):
    """Captures example images into <img_parent>/img and writes page data as JSON."""
    print("capturing pages from the showroom…", flush=True)
    pages, data = capture(img_parent, only, shots)
    if not shots:
        preserve_example_sizes(data, data_path)
    if only and os.path.exists(data_path):
        # partial capture: merge into the existing export, keeping showroom order
        old = {d["slug"]: d for d in json.load(open(data_path))["docs"]}
        old.update({d["slug"]: d for d in data})
        data = [old[p["slug"]] for p in pages if p["slug"] in old]
    os.makedirs(os.path.dirname(data_path), exist_ok=True)
    with open(data_path, "w") as f:
        json.dump({"pages": pages, "docs": data}, f, indent=1)
    print(f"wrote {len(data)} pages to {data_path}")


def build(out_dir: str, only: set, shots: bool):
    print("capturing pages from the showroom…", flush=True)
    pages, data = capture(out_dir, only, shots)
    if not shots:
        preserve_example_sizes(data, os.path.join(ROOT, "website/src/data/showroom.json"))
    groups = []
    for p in pages:
        if p["group"] not in groups:
            groups.append(p["group"])
    by_slug = {d["slug"]: d for d in data}
    order = [p for p in pages if p["slug"] in by_slug]
    for i, p in enumerate(order):
        doc = by_slug[p["slug"]]
        prev_p = order[i - 1] if i > 0 else None
        next_p = order[i + 1] if i + 1 < len(order) else None
        out = page_html(doc, pages, groups, prev_p, next_p)
        with open(os.path.join(out_dir, f"{p['slug']}.html"), "w") as f:
            f.write(out)
        if p["slug"] == "introduction":
            with open(os.path.join(out_dir, "index.html"), "w") as f:
                f.write(out)
    # assets
    here = os.path.dirname(os.path.abspath(__file__))
    for name in ("site.css", "site.js", "favicon.svg", "live.js"):
        shutil.copy(os.path.join(here, name), os.path.join(out_dir, name))
    fdir = os.path.join(out_dir, "fonts")
    os.makedirs(fdir, exist_ok=True)
    for f in ("Inter-Regular.ttf", "Inter-Medium.ttf", "Inter-SemiBold.ttf", "IBMPlexMono-Regular.ttf", "IBMPlexMono-Medium.ttf", "Inter-OFL.txt", "IBMPlexMono-OFL.txt"):
        shutil.copy(os.path.join(ROOT, "assets/fonts", f), os.path.join(fdir, f))
    og = os.path.join(ROOT, "docs/showroom-light.png")
    if shots and os.path.exists(og):
        subprocess.run(["magick", og, "-resize", "1200x", os.path.join(out_dir, "img/og.png")], check=True)
    with open(os.path.join(out_dir, "search.json"), "w") as f:
        json.dump([{"slug": p["slug"], "title": p["title"], "group": p["group"]} for p in pages], f)
    with open(os.path.join(out_dir, "sitemap.xml"), "w") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n')
        for p in order:
            loc = BASE_URL + ("" if p["slug"] == "introduction" else p["slug"] + ".html")
            f.write(f"  <url><loc>{loc}</loc><lastmod>{time.strftime('%Y-%m-%d')}</lastmod><changefreq>weekly</changefreq><priority>{'1.0' if p['slug'] == 'introduction' else '0.7'}</priority></url>\n")
        f.write("</urlset>\n")
    with open(os.path.join(out_dir, "robots.txt"), "w") as f:
        f.write(f"User-agent: *\nAllow: /\nSitemap: {BASE_URL}sitemap.xml\n")
    open(os.path.join(out_dir, ".nojekyll"), "w").close()
    with open(os.path.join(out_dir, "index.html")) as f:
        idx = f.read()
    nf = re.sub(r"<article>.*?</article>", '<article><h1>Page not found</h1><p class="lede">This page does not exist. Use the navigation or search (Ctrl K) to find a utility.</p><p><a href="index.html">Back to the introduction</a></p></article>', idx, flags=re.S)
    nf = nf.replace('<meta name="robots" content="index, follow">', '<meta name="robots" content="noindex">')
    nf = re.sub(r'<base[^>]*>', '', nf).replace('<head>', '<head>\n<base href="/vinland-ui/">', 1)
    with open(os.path.join(out_dir, "404.html"), "w") as f:
        f.write(nf)
    # live demos: wasm + Odin's JS runtime
    wasm = os.path.join(ROOT, "build/demos.wasm")
    if os.path.exists(wasm):
        shutil.copy(wasm, os.path.join(out_dir, "demos.wasm"))
        odin_root = subprocess.run(["odin", "root"], capture_output=True, text=True).stdout.strip()
        shutil.copy(os.path.join(odin_root, "core/sys/wasm/js/odin.js"), os.path.join(out_dir, "odin.js"))
    print(f"wrote {len(order)} pages to {out_dir}")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    out = os.path.abspath(args[0] if args else os.path.join(ROOT, "build/site"))
    only = set()
    for a in sys.argv[1:]:
        if a.startswith("--pages="):
            only = set(a.split("=", 1)[1].split(","))
    os.makedirs(out, exist_ok=True)
    if "--capture-only" in sys.argv:
        capture_only(out, os.path.join(ROOT, "website/src/data/showroom.json"), only, "--no-shots" not in sys.argv)
    else:
        build(out, only, "--no-shots" not in sys.argv)
