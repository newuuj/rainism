# Wanted Design System

A faithful, code-first recreation of the **Wanted Design System** — the component library, token set, iconography and brand assets used across Wanted's career-platform products (원티드). Built for design agents to generate on-brand Wanted interfaces, prototypes and assets in HTML.

> **Wanted** (운영: 주식회사 원티드랩 / Wanted Lab) is a Korean career & recruiting platform — job discovery, referral-based hiring with 채용보상금 (referral rewards), professional social, and career tools. The product surface is bilingual-leaning-Korean, dense, and utility-first.

## Source of truth
This system was extracted from the attached Figma file **"Wanted Design System (Community)"** (mounted as a read-only VFS). Everything here — token values, component specs, icon geometry, the Wanted wordmark — was read from that file with `fig_materialize` / `fig_read`, not from memory of the public brand.

- Figma file: *Wanted Design System (Community)* — pages `1-Theme` / `2-Element` / `3-Component` carry the canonical, current taxonomy (Theme → Element → Component).
- Kit scale: **959 component families**, **488 Figma Variables** (6 collections, multiple theme modes), **~325 icon glyphs**, Wanted brand logos.
- No separate codebase or product screenshots were provided; the file is a component library.

## What's in this project (manifest)
- **`styles.css`** — the single global entry point consumers link. `@import`-only manifest.
- **`tokens/`**
  - `fonts.css` — webfont `@import`s (Pretendard JP, Wanted Sans; CDN).
  - `fig-tokens.css` — all 488 Figma Variables as CSS custom properties, incl. Dark mode (`:root[data-theme="dark"]`, `.dark`) and Mobile/Desktop/breakpoint modes.
  - `typography.css` — families, weight ramp, and the semantic type scale (Display/Title/Heading/Body/Label/Caption) + `.wds-*` utility classes.
  - `semantic.css` — spacing, radius, elevation, motion tokens, base resets, keyframes.
- **`assets/`**
  - `icons/` — `icon-data.js` (325 glyphs) + `Icon.jsx` wrapper + `Icon.d.ts` name index.
  - `logos/` — Wanted wordmark, symbol, and Agent lockup as real vector components (+ `fig-assets.css`).
  - `samples/` — one real sample portrait used in cards/kit.
- **`components/`** — reusable React primitives (see list below), grouped by concern.
- **`guidelines/`** — foundation specimen cards (Colors, Type, Spacing, Brand).
- **`ui_kits/wanted/`** — interactive job-platform web recreation.
- **`SKILL.md`** — Agent-Skill manifest for use in Claude Code.

## Components
Grouped by concern; each is `<Name>.jsx` + `<Name>.d.ts` (+ a `@dsCard` per directory). Namespace: `window.WantedDesignSystem_13daa8`.

- **buttons/** — `Button` (solid/outlined/text × primary/assistive × 3 sizes), `IconButton` (normal/outlined/solid/background), `RoundButton` (pill: primary/secondary/assistive/alternative), `FloatingActionButton` (circular + extended).
- **forms/** — `Checkbox`, `Radio`, `Switch`, `Chip` (filter/toggle), `TextField`, `Select` (dropdown), `SearchField`, `Textarea`, `Slider`, `Stepper`.
- **data-display/** — `Badge` (dot/number/status), `ContentBadge`, `Avatar` + `AvatarGroup`, `Card` (content/job card), `Divider`, `Tag`, `ListCell`, `Skeleton`, `ProgressBar`, `Bubble` (chat), `Accordion`, `Rating`.
- **feedback/** — `Alert` (modal dialog), `Toast`, `Tooltip`, `Spinner`, `Banner`, `EmptyState`.
- **navigation/** — `BottomNavigation`, `Pagination`, `SegmentedControl`, `Tabs`, `TopNavigation`, `Breadcrumb`.
- **overlay/** — `BottomSheet`, `Menu` (dropdown).
- **assets/icons/** — `Icon` — the 325-glyph set.
- **assets/logos/** — Wanted brand vector components: `LogoResourceNormalHorizontalWanted`, `LogoResourceSquareSymbolWanted`, `LogoResourceNormalVerticalWanted`, `LogoResourceAssetLogotypeWanted`, `LogoResourceAssetSymbolWanted`, `LogoResourceAssetSymbol`, plus the Wanted Agent lockup `LogoResourceAssetLogotypeAgent` and `LogoResourceAssetSymbolAgent`.

### Coverage & intentional scope
The source defines 959 component *families*, but that count includes heavy duplication (the same family re-published across `1-Theme`/`2-Element`/`3-Component`, platform variants, deprecated sets, and hundreds of internal `Resource/*` sub-parts that are slots, not standalone components). This system implements the **distinct, consumer-facing families** — one clean React component per real UI primitive (50 components), covering every one of the 8 taxonomy groups in `3-Component` (Layout, Action, Selection & Input, Content, Loading, Navigation, Feedback, Presentation). Deep internal resource sub-parts, per-platform (iOS/Android/Web) duplicates, and deprecated sets are intentionally folded into props rather than shipped as separate components.

**Intentional additions:** `Icon` (a React wrapper over the extracted glyph data — the source ships icons as Figma symbols, not a code component) and `AvatarGroup` convenience export. Everything else maps to a source family.

---

## CONTENT FUNDAMENTALS
How Wanted writes.

- **Language:** Korean-first. UI copy, labels, and content are Korean; English appears for product/feature names (AI, PM, React) and the wordmark. Recreations should default to natural, concise Korean.
- **Tone:** Warm-professional and encouraging, never stiff. The product roots for the user: "당신에게 딱 맞는 포지션을 찾았어요", "합격하면 채용보상금 500만원". It nudges action rather than commanding it.
- **Address:** Speaks *to* the user with polite endings (해요체 — "…했어요", "…해 보세요"), not formal 합니다체 in most UI, and not casual 반말. Friendly-but-respectful.
- **Casing:** Korean has no case; Latin runs use sentence/Title Case for feature names. No ALL-CAPS shouting in body copy (caps reserved for tiny eyebrow labels like "WANTED AI 추천").
- **Numbers:** Comma-grouped KRW ("500,000원", "채용보상금 1,000,000원"); relative time ("3일 전"); ranges with 물결 ("경력 3-7년").
- **Buttons/CTAs:** Short verb phrases — 지원하기, 이력서 등록하기, 전체보기, 팔로우, 더보기. Verb + 하기 is the dominant CTA pattern.
- **Emoji:** Not used in core UI. Status is carried by colored badges and icons, not emoji.
- **Vibe:** Trustworthy, momentum-driven, "your career is moving." Confident but not hypey.

## VISUAL FOUNDATIONS
- **Color:** A crisp, high-contrast neutral system (cool-neutral greys, true black text `rgb(23,23,25)` on white) anchored by one decisive brand blue — **Blue 50 `rgb(0,102,255)`** for all primary actions, links, and focus. Violet `rgb(101,65,242)` is the secondary/AI accent. Status = green (positive), red `rgb(255,66,66)` (negative), orange (cautionary). Accent foregrounds (cyan/lime/pink/purple…) exist for content tagging but are used sparingly. Text uses *alpha-based* label tokens (`--label-normal/neutral/alternative/assistive/disable`) so hierarchy reads on any surface.
- **Type:** **Pretendard JP** is the workhorse for 100% of UI; **Wanted Sans** appears for large brand/display moments. Weights: Medium (500) is the default body weight, SemiBold (600) for labels/buttons/emphasis, Bold (700) for titles/display. Tight tracking on large type (−0.02 to −0.032em), slightly positive on body (+0.006em). Sizes are exact, not grid-snapped (e.g. 13/15/17/21px all appear).
- **Backgrounds:** Predominantly clean white / near-white (`--background-normal-alternative` `rgb(247,247,248)`). No busy textures. Hero/marketing moments use a single confident blue→violet gradient; everything else is flat. Elevated surfaces are pure white with shadow, not tinted.
- **Corners:** A graduated radius scale — controls 8–12px (small button 8, medium 10, large 12), cards 16px, dialogs 20px, chips/pills/avatars fully round. Never sharp (0) except hairlines.
- **Cards:** White (`--background-elevated-normal`), 16px radius, **soft layered low-alpha shadow** (`--shadow-normal`: `0 1px 4px rgba(23,23,23,.06)`), no border. Hover lifts the shadow (→ `--shadow-strong`). This is the signature surface treatment — shadow, not stroke.
- **Borders:** When present, borders are *translucent* neutral hairlines (`rgba(112,115,124,0.16–0.32)` = `--line-normal-*`) rendered as `inset box-shadow` (so they don't affect layout box size). Outlined buttons/fields use exactly this.
- **Elevation system:** Layered, very low alpha, tuned near-black — emphasize → normal → strong → heavy → overlay. Shadows are the primary depth cue.
- **Fills:** Translucent grey fills (`--fill-normal` `rgba(112,115,124,0.08)`, `--fill-strong` `0.16`) for assistive buttons, chips, switch tracks, avatars, search bars. Assistive solid buttons add `backdrop-filter: blur(64px)` — a frosted treatment.
- **Motion:** Short and soft. `--duration-fast 120ms` for hover/press color changes, `--duration-normal 200ms` for toggles/slide-overs, ease-out (`cubic-bezier(0.16,1,0.3,1)`). Fades and small translate-ups (toasts rise 8px). No bounce, no long or decorative loops. The only continuous animation is the loading spinner.
- **Hover states:** Subtle — buttons darken (primary → Blue 45), ghost/icon controls gain a translucent fill wash, cards raise shadow. Never scale-up on hover.
- **Press states:** Color deepens a further step; no shrink transform in the source.
- **Focus:** Blue focus ring token (`--focus-ring`, `rgba(51,102,255,0.28)`); fields switch their inset border to Blue 50 at 1.5px.
- **Transparency & blur:** Sticky nav is white at 86% + `blur(20px)`; image overlay controls (bookmark on a photo) use `rgba(0,0,0,0.28)` + blur; assistive buttons use frosted blur. Used deliberately for chrome-over-content, not decoration.
- **Imagery:** Bright, clean, natural-light Korean lifestyle/portrait photography on near-white backgrounds — warm-neutral, un-grainy, optimistic. Company marks are square-rounded; person avatars are circular.
- **Layout:** Centered content column, `--width-max 1060px`. Generous but not airy; dense utility screens. Sticky top nav, sticky action bars in slide-overs.
- **Dark mode:** Fully tokenised (`:root[data-theme="dark"]` / `.dark`) — the whole semantic layer flips.

## ICONOGRAPHY
- **Set:** A single cohesive **325-glyph in-house icon family**, extracted from the file's Figma symbols to `assets/icons/icon-data.js` and rendered by `<Icon name="…" size={24} />`.
- **Style:** 24×24 grid, geometric rounded-stroke outlines with matching **filled counterparts** — most glyphs ship as an outline/`…Fill` pair (e.g. `bell`/`bellFill`, `heart`/`heartFill`, `bookmark`/`bookmarkFill`). Fills are used for active/selected states, outlines for default. Some glyphs also have `…Thick`, `…Tight`, and `…Small` optical variants (chevrons especially).
- **Color:** Single-color, painted with `currentColor` — recolor by setting CSS `color` (or the `color` prop). Never multi-color.
- **Coverage:** Navigation (home, businessBag, persons, bubble), actions (plus, check, close, share, bookmark, filter), status (circleCheck/Exclamation/Info, triangleExclamation), brand/social logos (logoKakao, logoNaver­Blog, logoLinkedIn, logoApple, logoGoogle…), and rich content glyphs (crown, fire, sparkle, magicWand, graduation, coins, trophy).
- **Emoji / unicode:** Not used as iconography anywhere. Everything is the vector set. Chevrons/arrows are glyphs, never text characters.
- **Usage:** Icons sit inside Button/IconButton/Chip/BottomNavigation via the `leadingIcon`/`icon` props, or standalone via `<Icon>`. Default size 24; 20 in medium controls, 16 in small.

## Fonts
Both faces are the **real** brand fonts, open-source under SIL OFL, loaded from jsDelivr CDN — **no substitutions were made**:
- **Pretendard JP** — `pretendard-jp.min.css` → family `"Pretendard JP"`.
- **Wanted Sans** (by Wanted Lab) — `WantedSansVariable.min.css` → family `"Wanted Sans Variable"`.

If you need self-hosted/offline font binaries, download the woff2 files from the Pretendard and Wanted-Sans GitHub releases and add local `@font-face` rules to `tokens/fonts.css`. (Flag to the user if offline use is required.)

## Notes / caveats
- No company **logo** other than Wanted's own was in the source; partner/company marks in the UI kit are neutral tinted-initial placeholders (never fabricated brand logos).
- Named text styles: the file defines **0** reusable text styles (type is applied as raw runs), so the type scale here is reconstructed from the file's actual size/weight/tracking values.
- Component coverage is by distinct family, not by raw family count — see "Coverage & intentional scope".
