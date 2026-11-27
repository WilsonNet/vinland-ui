# Product

<!-- impeccable:product-schema 1 -->

## Platform

desktop (native Linux and macOS; SDL3 GPU Metal on macOS and Vulkan on Linux, with OpenGL 3.3 automatic fallback; plus WebAssembly/WebGL2 for live showroom demos; Windows untested)

## Stack

Odin. Framework packages in pure Odin on vendored libraries only (SDL3, OpenGL, stb_truetype, stb_image). No web runtime, no separate UI language.

## Users

Primary: the author, an Odin developer building native desktop apps and games (sibling projects `dreamcraft`, an RTS on raylib, and `tracker`, a multitrack audio recorder on SDL). They want to stop rebuilding a UI framework per project and want native UIs that hold up next to a modern web UI.

Secondary: other Odin developers who find the public repo and want a styling-first UI layer.

## Product Purpose

vinland-ui is a reusable, unstyled-by-default UI framework for Odin: UI written in Odin itself (Jetpack Compose style), styled with Tailwind-like utilities that resolve through design tokens, laid out with flexbox and grid, rendered with browser-grade text and shapes. Success means a dreamcraft or tracker screen can be rebuilt on it and look as crisp and polished as a good web app, and a theme swap re-skins it without code changes.

The showroom is a desktop app that is both the documentation and the proof: it covers the Tailwind CSS documentation's utility surface with live examples rendered by the framework itself.

## Positioning

Tailwind's vocabulary and design-token model, inside a native Odin immediate-mode tree, with Flutter-like ownership of rendering (no host widgets, no webview) and a CLI control channel so agents and tests can drive and screenshot the app.

## Operating Context

- Built and run from the terminal (`odin build`, shell scripts). Linux/Hyprland (1.333 fractional scaling on 3440x1440, Vulkan) and macOS (Apple Silicon Retina 2x, Metal): the framework renders at native physical pixels.
- Agent-driven feedback loop: `vui-ctl` CLI talks to the running app (navigate, click, scroll, type, theme, resize, dump tree, screenshot) with headless (`VUI_HIDDEN=1`) and non-focusable background (`VUI_BACKGROUND=1`) modes; `vui-test` runs Playwright-style e2e suites.
- Optional hot reload for development: `vui-hot` rebuilds the app as a shared library on save and swaps it into the running window (state kept via `app.run` + `app.keep`, migrated across type changes). Plain `odin build` stays the default path and contains no reload code.
- References the user named: Quickshell (widgets/animation on Linux), Jetpack Compose (UI in the host language), Flutter (owns its renderer, game-engine-like), Tailwind CSS (utility vocabulary, docs quality bar).

## Capabilities and Constraints

- Unstyled core: no default look baked into primitives; everything is utilities + tokens.
- Design tokens (palette, spacing, radius, shadows, typography, semantic colors) with light and dark variants, swappable at runtime.
- Must support sibling UIs such as `dreamcraft` (raylib renderer) and `tracker` (SDL); core stays renderer-agnostic so custom renderers can consume `Draw_List`.
- Web/WASM + WebGL2 backend (`vui/web/`) powers live interactive demos on the website; remaining undecided areas: accessibility tree integration, IME composition beyond basic text input.

## Brand Commitments

- Name: vinland-ui. License: MIT. Public GitHub repo.
- Showroom quality bar pinned by the user: match the Tailwind CSS docs ("the tailwind docs is beautiful, our showroom has to be beautiful"), storybook-like, both dark and light mode.

## Evidence on Hand

Used by sibling app `tracker` (multitrack recorder); frame-time and GPU-memory measurements are recorded in `README.md`. External adoption is still early.

## Product Principles

1. Text quality is the first impression: crisp glyphs at native pixels beat every other polish.
2. The framework styles nothing by itself; the showroom proves what the tokens can do.
3. Everything is Odin: no DSL files, no codegen required.
4. Every visual claim in the docs is rendered live by the framework, never a screenshot.
5. Agent-drivable by design: every screen reachable and capturable from the CLI.
