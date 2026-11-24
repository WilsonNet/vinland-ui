---
trigger: model_decision
description: >-
  Documents how to regenerate website/ Starlight MDX and live gh-pages HTML from showroom/
  on macOS or Linux without losing preview images or demos.wasm.
---

# Showroom & Website Publishing Rules

1. **Single source of truth**: edit documentation prose in `showroom/pages_intro.odin` and `showroom/pages_testing.odin` — never hand-edit generated files in `website/src/content/docs/` or on `gh-pages`.
2. **Updating text without re-capturing screenshots** (e.g. on macOS without `magick` / `wasm-ld`):
   ```bash
   ./build.sh
   python3 tools/site/build.py website/public --capture-only --no-shots --pages=<comma,slugs>
   python3 tools/site/starlight.py
   ```
   `--no-shots` carries over existing example `size` / `skip` fields from `website/src/data/showroom.json` so preview images stay intact.
3. **Updating `gh-pages` static HTML**:
   - Check out `gh-pages` in a temporary worktree (`git worktree add /tmp/vinland-gh-pages gh-pages`).
   - Run `python3 tools/site/build.py /tmp/vinland-gh-pages --no-shots` (across all pages so nav/sitemap/prev-next links stay consistent while `img/`, `demos.wasm`, and `odin.js` remain untouched).
   - Verify preview `<img>` tags on `index.html` and `showcase.html`, commit, push `origin gh-pages`, and remove the worktree.
4. **Full image + WASM rebuild**:
   ```bash
   ./build.sh release
   python3 tools/site/build.py <out_dir>
   ```
   On macOS: `wasm-ld` ships with Homebrew `lld` (`PATH=/opt/homebrew/opt/lld@22/bin:$PATH odin build showroom -target:js_wasm32 -o:size -out:website/public/vui.wasm`), and `build.py` falls back to `cwebp` + `sips` when ImageMagick is missing. Astro needs Node >= 22.23 (`/opt/homebrew/bin/node`). After a full capture, keep only images whose pixels really changed (animation frames vary between runs).
