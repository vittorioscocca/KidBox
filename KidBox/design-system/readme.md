# KidBox Design System

KidBox is an Italian family-organizer / co-parenting app — "app di
co-genitorialità" — for iOS (SwiftUI) and Android (Jetpack Compose), plus a
Firebase backend and an internal admin console. It gives parents (together or
separated) one shared, neutral place for everything about their kids: daily
routines, a shared calendar, health records, documents, a shopping list, a
family wallet, passwords, pet/vehicle/home tracking, location sharing, and
five specialised AI agents (family assistant, health advisor, trip planner,
proactive daily/weekly/monthly briefings, and document intelligence). Its own
positioning line: *"Non è una chat. Non è un gestionale. È una box condivisa
del carico mentale legato ai bambini."*

## Sources

This system was built by reading the real product source — not screenshots:

- **iOS app** — [github.com/vittorioscocca/KidBox](https://github.com/vittorioscocca/KidBox) (SwiftUI, SwiftData, Firebase). Key files read: `KidBox/UIComponent/*.swift` (the real reusable primitives), `KBTheme.swift` (color system), `Features/Home/HomeView.swift` (the Home grid — full 18-category inventory + tints), `Features/Auth/LoginView.swift`, `Features/Settings/SettingsView/SettingsView.swift`, `Features/Documents/*`.
- **Android app** — [github.com/vittorioscocca/KidBoxAndroid](https://github.com/vittorioscocca/KidBoxAndroid) (Jetpack Compose). Key file: `ui/theme/Theme.kt` (light/dark `KidBoxColorScheme`, Nunito typography) — the Nunito font files shipped in `assets/` come from `res/font/` in this repo.
- **Marketing website** — `KidboxLanding/public/index.html` inside the KidBox repo (kidbox.app landing page, static HTML/CSS, DM Sans).
- **Admin console** — `KidboxConsole/public/index.html` (internal Firestore dashboard) — reviewed for completeness but **not** built into a UI kit; it's a personal ops tool, not a designed product surface. Mentioned here for transparency.

If you have access to these repos, go read them directly for anything this
system simplified or omitted — especially `KidBox/KidBox/ARCHITECTURE.md` and
`KidBoxAndroid/ARCHITECTURE.md`, which document the full feature set in depth.

## Components

Built from the real SwiftUI `UIComponent/` inventory (not an invented generic
kit) — group **Core**: `Button`, `Chip`, `Badge`, `Avatar`. Group **Cards**:
`HomeCard` (Home-grid category tile), `HeroCard` (family photo hero),
`SettingsCard`, `CategoryCard` (Documents folder tile), `InviteCard`. Group
**AI**: `AskAIButton` (the orange gradient "parla con l'AI" FAB).

**Intentional additions** — none of the above were invented; every component
mirrors a real SwiftUI view. `Chip` and `Avatar` are the two components with
no 1:1 SwiftUI file (the app inlines pill/avatar views ad hoc) but both patterns
recur constantly (visibility pills, sync pills, profile avatars), so they were
extracted as reusable primitives.

## UI Kits

- `ui_kits/mobile-app/` — the iOS/Android app: Login → Home (hero + 18-tile
  category grid + Ask-AI FAB) → Documents → Settings, in a phone frame.
- `ui_kits/website/` — the kidbox.app marketing landing page (hero + AI-agents
  section).

## Content fundamentals

- **Language & person:** all copy is Italian, second person informal ("tu"):
  *"La tua famiglia, in un'unica app"*, *"Continuando, accetti…"*. Never
  formal "Lei".
- **Tone:** warm but plain-spoken, zero corporate jargon. The README states
  the philosophy directly: *"Child-centric… Neutral tone: niente giudizi,
  niente punteggi"* (no judgment, no scoring) — copy never guilt-trips or
  gamifies parenting.
  The landing page pitch is short declarative sentences, not hype: *"Cinque
  specialisti. Una sola app."*, *"Non aspetta che tu faccia domande."*
- **Structure:** headlines are frequently two short lines split by a line
  break, with one word in the brand orange (`<em>`) — e.g. *"La famiglia /
  organizzata. / Grazie all'AI."* Feature copy leads with the action or
  benefit, not the feature name.
- **Casing:** sentence case everywhere (titles, buttons, nav) — never Title
  Case, never ALL CAPS except tiny uppercase eyebrow labels (`section-label`,
  10–11px, letterspaced) and pill/badge micro-text ("SINCRONIZZATO").
  Card titles in the app are short nouns: "Note", "To-Do", "Documenti",
  "Garage" — never full sentences.
  In-app labels favor Italian conventions: "Lista della Spesa", "Casa e
  veicoli" — precise but plain.
- **Emoji:** used sparingly and only on the marketing site as section iconography
  (🧠 🩺 ✈️ ⚡ 🔍 for the five agents; 📅 🏥 🛒 for the features grid) and nav
  micro-icons (📖 💳). **Never** inside the native app UI itself — the app uses
  SF Symbols/Material icons exclusively, no emoji in SwiftUI/Compose views.
- **Numbers/proof:** the site leans on a small stats bar (5 agents, 100%
  italiano, E2E encryption, 0 extra apps needed) rather than long claims.

## Visual foundations

- **Palette:** warm, sunny, food-and-family — not corporate-blue, not
  bluish-purple. Primary brand color is a warm **orange** (`#E8833A`
  marketing accent / `#F28C33` in-app bubble tint), with a distinct, more
  saturated **AI orange** (`#FF6B00`→`#EB5205` gradient) reserved *only* for
  AI entry points (the Ask-AI FAB and gradient CTAs) so "AI" reads as a
  distinct affordance from ordinary brand orange.
  Backgrounds are a warm off-white/cream (`#F5F3EE` in-app, `#FDF7F0`
  marketing) — never pure white or cold gray. Cards sit on that cream in pure
  white (`#FFFFFF`).
- **Category color system:** the Home grid assigns each of its 18 sections a
  distinct iOS-system-style tint (yellow/blue/green/purple/red/orange/mint/
  indigo/cyan/pink/teal/brown/ink) — see the Colors → "Category Colors" card.
  This is the app's main source of visual variety against an otherwise
  minimal neutral UI.
- **Type:** native apps set text in **Nunito** (Android explicit; this system
  uses it as the cross-platform stand-in for iOS's system SF Pro too, since
  Nunito's rounded, friendly forms read closest to the brand's warmth). One
  deliberate exception: the Login/Onboarding hero title and tagline switch to
  SwiftUI's **serif** design (`New York` on device) — a soft, editorial accent
  reserved for that single arrival moment, never used elsewhere. The marketing
  website sets everything in **DM Sans**.
- **Spacing/density:** compact and information-dense by design (a family
  organizer, not a lifestyle app) — card padding is 14px, grid gaps 12px, a
  2-column grid is the default density for both the Home category grid and
  Documents folders.
- **Corner radii:** 16px is the standard card radius everywhere (Home tiles,
  settings rows, folders); the photo hero card is slightly rounder at 18px;
  marketing panels/sections use 24px; buttons and pills are fully capsule
  (999px).
- **Cards:** flat, not skeuomorphic — a hairline border (not a drop shadow) is
  the primary separation device in-app (`rgba(0,0,0,0.08–0.18)` depending on
  context); native iOS cards add only a very soft 1–3px shadow
  (`rgba(0,0,0,0.07)`). Marketing-site cards use a slightly stronger soft
  shadow (`0 2px 20px rgba(180,100,30,0.08)`) since they sit on a page, not a
  scroll list. **No left-border accent cards anywhere in the source** —
  category identity comes from a *tinted fill + tinted border*, both at low
  opacity (10%/18%), not a colored bar.
- **Backgrounds:** solid warm neutrals; no patterns, textures or illustrated
  backgrounds anywhere in the app. The one full-bleed image moment is the Home
  hero (family photo) and the marketing hero (a warm lifestyle photograph) —
  both get a dark bottom-up "protection" gradient so overlaid text stays
  legible, not a scrim rectangle.
- **Photography:** warm, natural-light, real-family lifestyle photography (see
  the landing hero) — never cool/blue-toned or studio/stock-corporate.
- **Gradients:** used exactly once as a UI device — the Ask-AI button/CTAs
  (orange→deep-orange diagonal). Not used on cards, headers, or backgrounds.
  This scarcity is what makes the AI gradient legible as "AI" at a glance.
- **Animation:** minimal and functional, never decorative-only. Observed
  patterns: a slow breathing pulse (scale 0.98↔1.02, 1.6s ease-in-out,
  infinite) on the Ask-AI FAB to draw the eye without being loud; a soft green
  "ripple" pulse (two expanding rings, 1.4s ease-out) for live location
  sharing; a small pulsing dot for "live" states on the marketing badge;
  drag-and-reorder with a spring (`response:0.28, dampingFraction:0.75`) on
  Home grid tiles. No page-transition bounces, no confetti, no gratuitous
  micro-interactions.
- **Press/hover states:** press = subtle scale-down (~0.97–0.98) on buttons
  and cards, not a color change; marketing hover = small lift
  (`translateY(-3px)`) + shadow increase, plus border tinting toward the
  brand orange. No darkening overlays.
- **Blur/transparency:** `.ultraThinMaterial`/frosted-glass is used narrowly
  for two purposes only — the busy/loading overlay on Login, and the
  `InviteCard` surface — plus `backdrop-filter: blur(20px)` on the marketing
  nav bar when scrolled. Not used as a general card material.
- **Badges:** a plain solid red circle (count <10) or red capsule (10+),
  white bold text, small drop shadow — used for unread counts only, never for
  status/semantic meaning (status uses tinted pills/chips instead).
- **Dark mode:** fully supported and distinct per platform — iOS dark
  background `#212121`/card `#2E2E2E`; Android dark background `#1C1C1E`/card
  `#2C2C2E`. Same category tints, same orange accent (slightly lightened to
  `#F09050` for contrast).

## Iconography

- **iOS app:** SF Symbols exclusively (e.g. `note.text`, `checklist`,
  `heart.fill`, `sparkles`, `key.fill`) — a system font, not shippable assets.
- **Android app:** Material icons (equivalent glyphs, same names conceptually).
- **Marketing website:** emoji as section iconography (see Content
  Fundamentals) plus two inline brand SVGs (the Apple logo App-Store badge).
- **This design system's substitution:** since SF Symbols/Material icon files
  can't be copied out, UI-kit screens load **[Lucide](https://lucide.dev)**
  from CDN (`unpkg.com/lucide`) — picked for its rounded, ~1.8px stroke weight
  being the closest open match to SF Symbols' line style. This is flagged
  here explicitly: if you have Figma/Xcode access to the real SF Symbol set,
  prefer it for production work. Component `.jsx` files accept icons as a
  `icon` **ReactNode prop** — pass whatever glyph system you like; nothing is
  hard-wired to Lucide except the UI-kit screens.
- No custom icon font, no PNG icon sprite in the source repos.

## Logo

**No standalone logo/wordmark file exists in either repo** — only the app
icon (`assets/kidbox-icon.png`, white family line-mark on an orange gradient,
1024×1024) was found. The wordmark is always just set in plain type — "Kid" in
ink, "Box" in brand orange — as seen on kidbox.app; this system does the same
rather than inventing a mark. See `guidelines/brand-mark.card.html`.

## Fonts — substitution flag

**DM Sans** (marketing) is referenced via Google Fonts `<link>`/`@import` in
the two places it's used (`guidelines/type-marketing.card.html`,
`ui_kits/website/`) since no font file exists in the repos to copy — it's
loaded live from Google Fonts, not fully self-hosted. If you'd rather it be
fully offline-capable, upload the DM Sans static/variable font files and this
system's author can wire a proper `@font-face`.
**Nunito** (app) is fully self-hosted — `.ttf` files copied straight from
`KidBoxAndroid/app/src/main/res/font/`.

## Index

```
styles.css              — entry point (imports tokens/*)
tokens/
  fonts.css              — @font-face (Nunito)
  colors.css             — brand, neutral, category, status, dark-mode tokens
  typography.css         — font stacks, weights, SwiftUI-role type scale
  spacing.css            — spacing scale, radii, hit-target
fonts/                   — Nunito .ttf (regular/semibold/bold/extrabold)
assets/
  kidbox-icon.png         — the only real brand asset found (app icon)
components/
  core/    Button, Chip, Badge, Avatar
  cards/   HomeCard, HeroCard, SettingsCard, CategoryCard, InviteCard
  ai/      AskAIButton
guidelines/              — foundation specimen cards (Colors/Type/Spacing/Brand)
ui_kits/
  mobile-app/            — iOS/Android app kit (Login → Home → Documents/Settings)
  website/                — marketing landing page kit
SKILL.md                 — portable skill wrapper for this design system
```
