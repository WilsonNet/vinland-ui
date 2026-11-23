---
name: "vinland-ui showroom"
description: "Documentation app for vinland-ui: Tailwind-docs calm, native Odin rendering, one violet accent."
---

# Design System: vinland-ui showroom

Derived from the shipped showroom (`showroom/main.odin` `theme_setup`, `shell.odin`, `kit.odin`)
and the published site (`tools/site/site.css`, plus `website/src/styles/custom.css` in the Starlight draft). The framework itself is unstyled; this
file describes the showroom's own look, which is also the reference for the website.

## 1. Overview

**North star: "the docs you already trust, running natively."** The layout and rhythm follow
Tailwind's documentation: a quiet top bar, a grouped sidebar, a single reading column with an
"On this page" rail, and examples presented as previews in a soft well with their real source
directly underneath. Nothing competes with the examples: chrome is gray, type is Inter, and a
single violet accent marks the current page, links and focus.

Key traits:

- Light and dark are equal citizens; every semantic token carries both values.
- Flat surfaces, hairline rules (5–15% ink), no decorative shadows in chrome.
- Hatched gutters (diagonal stripes at 5–8% ink) frame the reading column, the one ornament.
- Code is first-class: IBM Plex Mono, highlighted Odin, same panel in both themes.

## 2. Color

Semantic tokens (light / dark), all built on the Tailwind v4 palette:

| Token | Light | Dark | Use |
|---|---|---|---|
| `canvas` | white | gray-950 | page background |
| `ink` | gray-950 | white | headings, body emphasis |
| `ink-muted` | gray-600 | gray-400 | body copy, sidebar items |
| `ink-soft` | gray-500 | gray-500 | captions, group labels |
| `accent` | violet-600 | violet-400 | current page, links, focus, TOC marker |
| `accent-soft` | violet-500 / 10% | violet-400 / 15% | selected backgrounds |
| `rule` | gray-950 / 5% | white / 10% | dividers |
| `rule-strong` | gray-950 / 10% | white / 15% | panel outlines |
| `hatch` | gray-950 / 5% | white / 8% | gutter stripes |
| `well` | gray-950 / 2.5% | white / 5% | example wells |

Rules:

- **One accent.** Violet is the only chromatic color in chrome. Examples may use any palette color.
- **Alpha hairlines.** Rules and outlines are ink at low alpha, never a separate gray, so they sit
  correctly on any surface.
- New colors may be authored in OKLCH (`ui.oklch`) to stay in Tailwind v4's space.

## 3. Typography

- **Inter** for all UI and prose (400 body, 500 nav, 600 headings).
- **IBM Plex Mono** for code, class names, keyboard hints and reference tables.
- Scale: page title `text-4xl font-semibold tracking-tight`, section `text-xl font-semibold`,
  body `text-base/7`, sidebar `text-sm`, group labels `text-xs` mono uppercase with wide tracking.
- Text is rasterized at exact physical size with subpixel positioning; never scale text with
  transforms.

## 4. Layout

- Top bar 56 px (`h-14`); sidebar 288 px (`w-72`); reading column `max-w-2xl` (672 px); TOC rail from `xl`.
- Below `lg` the sidebar becomes a drawer; below `xl` the TOC hides.
- Example: `rounded-xl` well with `p-1` inset ring, preview `rounded-lg`, code panel beneath.
- Spacing on the 4 px Tailwind scale; sections separated by `mt-16`, paragraphs by `mt-4`.

## 5. Components

- **Sidebar item:** muted ink, accent text + 1 px accent left rule when current.
- **Search palette (Ctrl+K):** centered panel, `rounded-xl`, `shadow-2xl`, results grouped by section.
- **Reference table:** two columns (class in accent mono, effect in mono soft ink), hairline rows.
- **Note:** soft well with an accent icon; one sentence.
- **Canvas examples:** charts and dials use `accent` for strokes, a 30% → 0% accent area fill,
  and `rule`-alpha grid lines.

## 6. Motion

150–200 ms color/opacity transitions on hover and focus; smooth scrolling with fading overlay
scrollbars; no decorative animation in chrome. Live examples may animate (spin, ping, pulse,
sparklines) because they demonstrate the feature.

## 7. Performance is part of the design

The showroom must feel faster than a browser: it idles when nothing changes, renders a full docs
page in about 3–4 ms with one instanced draw call, and scrolls at display refresh. Designs that
need hundreds of extra elements per frame should become one `ui.canvas` instead.

## Do / Don't

- Do keep examples the loudest thing on the page.
- Do use semantic tokens in chrome so both themes come for free.
- Don't add eyebrow/kicker labels above headings.
- Don't introduce a second accent, gradients in chrome, or decorative shadows.
- Don't draw with many tiny boxes what a canvas primitive draws in one instance.
