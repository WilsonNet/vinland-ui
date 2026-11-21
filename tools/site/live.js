// Mounts the WebAssembly showcase demos (vinland-ui rendered with WebGL2) over the
// static screenshots. If WebGL2 or WebAssembly is unavailable the screenshots stay.
(function () {
  if (!document.querySelector('canvas[id^="vui-"]') || !window.odin || !window.WebAssembly) return;
  try {
    const c = document.createElement('canvas');
    if (!c.getContext('webgl2')) return;
  } catch (e) { return; }
  window.odin.runWasm('demos.wasm').catch(err => console.warn('vinland-ui live demos unavailable:', err));
})();
