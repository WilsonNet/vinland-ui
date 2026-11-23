#!/usr/bin/env python3
"""Generates the Astro Starlight docs (website/src/content/docs) from the showroom export.

    python3 tools/site/build.py website/public --capture-only   # images + website/src/data/showroom.json
    python3 tools/site/starlight.py                              # MDX pages
    cd website && npm run build
"""
import json
import os
import re
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WEB = os.path.join(ROOT, "website")
DOCS = os.path.join(WEB, "src/content/docs")


def slugify(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def mdx_text(text: str) -> str:
    """Escapes MDX-significant characters outside `inline code`."""
    parts = text.split("`")
    out = []
    for i, p in enumerate(parts):
        if i % 2:
            out.append("`" + p + "`")
        else:
            out.append(p.replace("{", "&#123;").replace("}", "&#125;").replace("<", "&lt;").replace(">", "&gt;"))
    return "".join(out)


def cell(s: str) -> str:
    # Markdown code spans keep `--` and `<...>` literal (no smart punctuation, no JSX)
    s = s.replace("|", "\\|").replace("`", "'")
    return f"`{s}`" if s else ""


def yaml_str(s: str) -> str:
    return json.dumps(s)


def page_mdx(doc, order: int) -> str:
    slug, title, desc, group = doc["slug"], doc["title"], doc["desc"], doc["group"]
    blocks = doc["blocks"]
    if blocks and blocks[0]["kind"] == "Para" and blocks[0].get("text") == desc:
        blocks = blocks[1:]
    meta_desc = desc if group in ("Getting started", "Core concepts") else f"{desc.rstrip('.')}. Tailwind-style {title} utilities for native Odin apps with vinland-ui, with live examples and copyable code."
    lines = [
        "---",
        f"title: {yaml_str(title)}",
        f"description: {yaml_str(meta_desc)}",
        "sidebar:",
        f"  order: {order}",
        "---",
        "",
        "import Preview from '../../../components/Preview.astro';",
        "",
        mdx_text(desc),
        "",
    ]
    heading = title
    k = 0
    for b in blocks:
        kind = b["kind"]
        if kind == "H2":
            heading = b["text"]
            lines += [f"## {mdx_text(b['text'])}", ""]
        elif kind == "H3":
            heading = b["text"]
            lines += [f"### {mdx_text(b['text'])}", ""]
        elif kind == "Para":
            lines += [mdx_text(b["text"]), ""]
        elif kind == "Note":
            lines += [":::note", mdx_text(b["text"]), ":::", ""]
        elif kind == "Table":
            lines += ["| Class | Effect |", "| --- | --- |"]
            for c, e in b["rows"]:
                lines.append(f"| {cell(c)} | {cell(e)} |")
            lines.append("")
        elif kind == "Code":
            lines += ["```" + b.get("lang", "odin"), b["code"], "```", ""]
        elif kind == "Example":
            if not b.get("skip") and b.get("size"):
                w, h = b["size"]
                live = f' live="vex-{k}" page="{slug}"'
                alt = f"{title}: {heading}".replace('"', "'")
                lines += [f'<Preview src="{slug}-{k}" width={{{w:.0f}}} height={{{h:.0f}}} alt="{alt}"{live} />', ""]
            lines += ["```odin", b.get("code", ""), "```", ""]
            k += 1
    return "\n".join(lines)


def main():
    data = json.load(open(os.path.join(WEB, "src/data/showroom.json")))
    pages, docs = data["pages"], {d["slug"]: d for d in data["docs"]}
    if os.path.isdir(DOCS):
        shutil.rmtree(DOCS)
    os.makedirs(DOCS)
    groups = []
    order_in_group = {}
    for p in pages:
        g = p["group"]
        if g not in groups:
            groups.append(g)
        order_in_group[g] = order_in_group.get(g, 0) + 1
        d = docs.get(p["slug"])
        if not d:
            continue
        gdir = os.path.join(DOCS, slugify(g))
        os.makedirs(gdir, exist_ok=True)
        with open(os.path.join(gdir, f"{p['slug']}.mdx"), "w") as f:
            f.write(page_mdx(d, order_in_group[g]))
    with open(os.path.join(DOCS, "index.mdx"), "w") as f:
        f.write(INDEX)
    with open(os.path.join(WEB, "src/data/groups.json"), "w") as f:
        json.dump([{"label": g, "directory": slugify(g)} for g in groups], f, indent=1)
    print(f"wrote {len(docs)} pages in {len(groups)} groups")


INDEX = """---
title: vinland-ui
description: A utility-first UI framework for Odin. Tailwind-style classes, design tokens, crisp GPU text at real pixel density, Metal and Vulkan with OpenGL fallback, and a CLI so agents can drive your app.
template: splash
hero:
  tagline: Write native UI in Odin, style it with Tailwind CSS class names that resolve through design tokens, and let a small GPU renderer draw it at your display's real pixel density.
  image:
    file: ../../assets/logo.svg
  actions:
    - text: Get started
      link: getting-started/introduction/
      icon: right-arrow
    - text: Component showcase
      link: getting-started/showcase/
      variant: minimal
    - text: View on GitHub
      link: https://github.com/WilsonNet/vinland-ui
      icon: external
      variant: minimal
---

import { Card, CardGrid } from '@astrojs/starlight/components';

<CardGrid>
  <Card title="Crisp text" icon="pencil">
    Glyphs are rasterized for the exact physical size and snapped to whole-pixel baselines, so fractional scales like 1.333 look as sharp as a browser.
  </Card>
  <Card title="Tailwind vocabulary" icon="seti:css">
    `flex`, `gap-4`, `rounded-xl`, `shadow-lg`, `hover:`, `dark:`, `md:`, `group-hover:`. The palette and scales are Tailwind CSS v4's.
  </Card>
  <Card title="Design tokens" icon="setting">
    Colors, spacing, radii, shadows, type and breakpoints live in a Theme. Tokens carry light and dark values and load from JSON.
  </Card>
  <Card title="Metal & Vulkan first" icon="rocket">
    SDL3's GPU API renders natively on Metal (macOS) and Vulkan (Linux), with OpenGL 3.3 as an automatic fallback, and WebGL2 for the live demos on this site.
  </Card>
  <Card title="Real layout" icon="list-format">
    Block flow, flexbox, grid, absolute and fixed positioning, and smooth scroll containers.
  </Card>
  <Card title="Agent-drivable" icon="laptop">
    `vui-ctl` clicks, types, scrolls, toggles dark mode, dumps the element tree and takes screenshots of a running app.
  </Card>
</CardGrid>
"""

if __name__ == "__main__":
    main()
