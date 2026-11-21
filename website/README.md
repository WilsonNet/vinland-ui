# vinland-ui website

Astro Starlight site published at https://wilsonnet.github.io/vinland-ui/.

Page content and the example images come from the native showroom, so the docs always show
what the framework really renders:

```bash
./build.sh release                                         # build/showroom, build/vui-ctl
PATH=/usr/lib/llvm20/bin:$PATH odin build web/demos -target:js_wasm32 -o:size -out:website/public/demos.wasm
python3 tools/site/build.py website/public --capture-only  # example screenshots + src/data/showroom.json
python3 tools/site/starlight.py                            # src/content/docs/**/*.mdx
cd website && npm install && npm run dev
```

Pushing to `main` deploys through `.github/workflows/pages.yml`. The showcase page mounts the
WebAssembly build of `showroom/demos` (WebGL2) over its screenshots.
