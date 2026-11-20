---
version: 1
slug: "showroom-main-odin"
primary_target: "showroom/main.odin"
related_targets: []
---

# Showroom (desktop docs app)

Scope: the vinland-ui showroom app (`showroom/`), a native desktop documentation app and live storybook. Visitor mode: Read.

Audience and job: Odin developers (first the author) looking up a utility, seeing it rendered live by the framework, and copying the Odin code. Also proof for the author that native Odin UI can match a top-tier web docs site.

Content: every Tailwind CSS docs utility page, with a quick-reference table (class -> effect), live examples rendered by vinland-ui, and the exact Odin source of each example extracted from the showroom's own code. Plus framework pages: introduction, installation, core concepts (tokens, variants, dark mode, layout model, interactivity, control CLI).

Constraints: native Odin, rendered by vinland-ui itself; dark and light mode; responsive to window width (sidebar collapses, TOC hides); every page reachable by `vui-ctl nav page=<slug>`.

## Direction contract

THESIS: Documentation that reads like the Tailwind CSS docs (the user pinned that quality bar) but is rendered natively by the framework it documents; it refuses the generic "native tool" look of grey panels and system widgets.

OWN-WORLD: Near-white ground (white / gray-950 in dark) with hairline gray-950/5 rules, diagonal hatched gutters framing the reading column, Inter for reading, IBM Plex Mono for class names, code and sidebar group labels, a single violet accent (violet-600 / violet-400) for the active nav item, links and the brand mark, example canvases on soft gray wells with an inset ring, code panels in gray-950 with a restrained syntax palette.

STORY: The reader picks a utility from the sidebar or Ctrl+K search, sees what it does in one sentence, scans the class table, then sees live examples with the Odin code beneath; they leave knowing the exact string to type.

FIRST VIEWPORT: 56px top bar (brand mark + wordmark + version pill left; search field with Ctrl K hint, Docs/GitHub links, theme switch right). Left sidebar 288px with grouped nav (mono group labels, items with a 1px rail and violet active marker). Hatched 40px gutter. Reading column max 672px: breadcrumb line, h1 (30px/36 medium, tight tracking), lede (18px gray), class/effect table, then first example. Right rail 240px "On this page" contents on wide windows.

FORM: Pinned whole by the user ("the tailwind docs is beautiful, our showroom has to be beautiful"; "think of our showroom to be a very nice storybook"). seed: none (pinned). Signature interaction: live variants (hover, focus, dark) work inside examples, and the theme switch re-skins the whole app instantly through tokens.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

Unresolved: syntax highlighting is a lightweight Odin tokenizer, not a full grammar.
