# vinland-ui website

Astro Starlight site published at https://wilsonnet.github.io/vinland-ui/.

Page content and example images come from the native showroom, and every example is also
live: `public/vui.wasm` is the showroom itself compiled to WebAssembly (WebGL2). On each page
the wasm runs the same page code in "web mode", where only the example belonging to a canvas
renders, so the live examples are exactly the showroom's examples with no duplicated code.
Screenshots show first and are replaced by live canvases once the wasm loads (lazily, when the
first example nears the viewport).

```bash
./build.sh release                                         # build/showroom, build/vui-ctl
PATH=/usr/lib/llvm20/bin:$PATH odin build showroom -target:js_wasm32 -o:size -out:website/public/vui.wasm
python3 tools/site/build.py website/public --capture-only  # example screenshots + src/data/showroom.json
python3 tools/site/starlight.py                            # src/content/docs/**/*.mdx
cd website && npm install && npm run build
```

Validate with Playwright (Chromium on SwiftShader, so no GPU is used): every live canvas must
mount, render non-blank, and log no errors, in light and dark mode.

```bash
cd website && npx playwright install chromium   # once
npx astro preview & npm run validate             # PAGES=a/b,c/d THEMES=light to narrow
```

Pushing to `main` deploys through `.github/workflows/pages.yml`.
