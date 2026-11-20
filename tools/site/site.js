// Theme toggle, table expanders, mobile nav, Ctrl+K search, active TOC entry.
(function () {
  const root = document.documentElement;
  document.querySelector('.theme').addEventListener('click', () => {
    const dark = root.classList.toggle('dark');
    try { localStorage.setItem('theme', dark ? 'dark' : 'light'); } catch (e) {}
  });
  document.querySelectorAll('.show-all').forEach(b => b.addEventListener('click', () => b.parentElement.classList.add('open')));
  document.querySelector('.menu').addEventListener('click', () => document.body.classList.toggle('nav-open'));
  const cur = document.querySelector('.side a[aria-current]');
  if (cur) cur.scrollIntoView({ block: 'center' });

  // search
  const pal = document.querySelector('.palette'), input = pal.querySelector('input'), list = pal.querySelector('.results');
  let pages = [], sel = 0, shown = [];
  fetch('search.json').then(r => r.json()).then(j => { pages = j; render(); });
  function render() {
    const q = input.value.trim().toLowerCase();
    shown = pages.filter(p => !q || p.title.toLowerCase().includes(q) || p.group.toLowerCase().includes(q) || p.slug.includes(q)).slice(0, 60);
    sel = Math.min(sel, Math.max(shown.length - 1, 0));
    list.innerHTML = shown.length ? shown.map((p, i) => `<li><a href="${p.slug}.html" aria-selected="${i === sel}">${p.title}<span>${p.group}</span></a></li>`).join('')
      : '<li style="padding:32px 12px;text-align:center;color:var(--ink-muted);font-size:14px">No pages match. Try a utility name like padding or shadow.</li>';
  }
  function open() { pal.hidden = false; input.value = ''; sel = 0; render(); input.focus(); }
  function close() { pal.hidden = true; }
  document.querySelector('.search').addEventListener('click', open);
  pal.querySelector('.scrim').addEventListener('click', close);
  input.addEventListener('input', () => { sel = 0; render(); });
  document.addEventListener('keydown', e => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); pal.hidden ? open() : close(); return; }
    if (pal.hidden) { if (e.key === '/' && document.activeElement === document.body) { e.preventDefault(); open(); } return; }
    if (e.key === 'Escape') close();
    if (e.key === 'ArrowDown') { sel = Math.min(sel + 1, shown.length - 1); render(); e.preventDefault(); }
    if (e.key === 'ArrowUp') { sel = Math.max(sel - 1, 0); render(); e.preventDefault(); }
    if (e.key === 'Enter' && shown[sel]) location.href = shown[sel].slug + '.html';
  });

  // active TOC entry
  const links = [...document.querySelectorAll('.toc a')];
  const heads = links.map(a => document.getElementById(a.getAttribute('href').slice(1))).filter(Boolean);
  function spy() {
    let i = 0;
    heads.forEach((h, k) => { if (h.getBoundingClientRect().top < 120) i = k; });
    links.forEach((a, k) => a.classList.toggle('active', k === i));
  }
  addEventListener('scroll', spy, { passive: true }); spy();
})();
