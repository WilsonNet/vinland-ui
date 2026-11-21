// Usage (from website/): npm run build && npx astro preview & then npm run validate
//   PAGES=core-concepts/canvas,effects/box-shadow THEMES=light npm run validate
// Validates the vinland-ui website's live WebAssembly examples with Playwright.
// Chromium is forced onto SwiftShader (software WebGL): validation never touches the GPU.
import { chromium } from 'playwright';
import fs from 'node:fs';

const BASE = process.env.BASE || 'http://localhost:4321/vinland-ui';
const OUT = process.env.OUT || '/tmp/vui-site-validate';
const PAGES = (process.env.PAGES || [
  'core-concepts/canvas', 'getting-started/showcase', 'getting-started/introduction',
  'effects/box-shadow', 'flexbox-grid/justify-content', 'spacing/padding',
  'typography/font-weight', 'interactivity/cursor', 'backgrounds/background-color',
].join(',')).split(',');
fs.mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch({
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});
const results = [];
let failed = 0;
for (const theme of (process.env.THEMES || 'light,dark').split(',')) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1, colorScheme: theme });
  for (const path of PAGES) {
    const page = await ctx.newPage();
    const errors = [];
    page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
    page.on('pageerror', (e) => errors.push(String(e)));
    const res = await page.goto(`${BASE}/${path}/`, { waitUntil: 'load' });
    if (!res || res.status() !== 200) {
      results.push({ theme, path, ok: false, msg: `HTTP ${res && res.status()}` }); failed++; await page.close(); continue;
    }
    await page.evaluate((t) => { localStorage.setItem('starlight-theme', t); document.documentElement.dataset.theme = t; }, theme);
    const n = await page.locator('.vui-preview canvas').count();
    const r = { theme, path, ok: true, canvases: n, live: 0, blank: [], msg: '' };
    if (n > 0) {
      await page.locator('.vui-preview').first().scrollIntoViewIfNeeded();
      try {
        await page.waitForFunction(() => [...document.querySelectorAll('.vui-preview canvas')].some((c) => c.style.display === 'block'), null, { timeout: 30000 });
      } catch { r.ok = false; r.msg = 'wasm never mounted a canvas'; }
      for (let i = 0; i < n; i++) {
        const c = page.locator('.vui-preview canvas').nth(i);
        await c.evaluate((el) => el.parentElement.scrollIntoView({ block: 'center' }));
        await page.waitForTimeout(250);
        const live = await c.evaluate((el) => el.style.display === 'block');
        if (!live) { r.ok = false; r.msg += ` vex-${i} not live;`; continue; }
        r.live++;
        const shot = `${OUT}/${theme}-${path.replace(/\//g, '_')}-${i}.png`;
        const buf = await c.screenshot({ path: shot });
        // blank check: count distinct sampled colors in the PNG via a canvas round trip
        const distinct = await page.evaluate(async (b64) => {
          const img = new Image(); img.src = 'data:image/png;base64,' + b64; await img.decode();
          const cv = new OffscreenCanvas(img.width, img.height); const g = cv.getContext('2d'); g.drawImage(img, 0, 0);
          const d = g.getImageData(0, 0, img.width, img.height).data; const set = new Set();
          for (let p = 0; p < d.length; p += 4 * 97) set.add((d[p] >> 3) << 10 | (d[p + 1] >> 3) << 5 | (d[p + 2] >> 3));
          return set.size;
        }, buf.toString('base64'));
        if (distinct < 3) { r.ok = false; r.blank.push(i); }
      }
      // interaction: click the first canvas center and make sure nothing throws
      await page.locator('.vui-preview canvas').first().click({ force: true }).catch(() => {});
      await page.waitForTimeout(200);
    }
    const lost = errors.filter((e) => !/favicon/i.test(e));
    if (lost.length) { r.ok = false; r.msg += ' console: ' + lost.slice(0, 3).join(' | '); }
    if (!r.ok) failed++;
    results.push(r);
    await page.screenshot({ path: `${OUT}/${theme}-${path.replace(/\//g, '_')}-page.png` });
    await page.close();
  }
  await ctx.close();
}
await browser.close();
for (const r of results) console.log(`${r.ok ? 'PASS' : 'FAIL'} ${r.theme.padEnd(5)} ${r.path.padEnd(34)} live ${r.live ?? 0}/${r.canvases ?? 0}${r.blank && r.blank.length ? ' blank:' + r.blank : ''} ${r.msg}`);
console.log(`\n${results.length - failed}/${results.length} passed`);
process.exit(failed ? 1 : 0);
