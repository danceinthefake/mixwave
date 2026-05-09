# mixwave UI primitives

A reference for the patterns that already exist in the studio. New UI work should copy from this canon instead of inventing its own — that's how a design system stays one.

The CSS variables and Tailwind theme tokens that back these classes live in `assets/css/app.css`. The motion timings live in `assets/vue/lib/motion.ts`. The fonts come from Google Fonts via `lib/mixwave_web/components/layouts/root.html.heex`.

---

## Color tokens

### Neutral surfaces (shadcn-vue zinc, with a deeper studio dark variant)

```
bg-background    near-black w/ faint hue 280 tint   (page background)
bg-card          one step lighter than background    (cards, dock, pads)
bg-muted         dark gray                            (kbd hint chips)
bg-accent        slightly lit                         (hover surface)
text-foreground  bright white                         (primary text)
text-muted-foreground  ~65% opacity                   (subdued text)
border           white / 8%                           (1px borders)
```

### Per-instrument neon accents

| Instrument | Token            | Hue                | Used for                                         |
| ---------- | ---------------- | ------------------ | ------------------------------------------------ |
| Drums      | `accent-drums`    | magenta `oklch(0.72 0.27 340)` | flash ring, glow, dock tab when active            |
| Keyboard   | `accent-keyboard` | cyan    `oklch(0.80 0.17 200)` | "                                                 |
| Guitar     | `accent-guitar`   | lime    `oklch(0.85 0.22 130)` | " + chord-diagram dots + barre line               |
| Bass       | `accent-bass`     | orange  `oklch(0.80 0.20 55)`  | " + fretboard pressed-fret tint                   |
| Pad        | `accent-pad`      | violet  `oklch(0.72 0.24 290)` | "                                                 |

Available as `bg-accent-{instrument}`, `ring-accent-{instrument}`, `text-accent-{instrument}`, `border-accent-{instrument}`, `glow-{instrument}`.

Remote flashes use `ring-orange-400` regardless of which instrument played them — a deliberately distinct colour so "someone else played this" always reads the same.

---

## Typography

```
font-display    Space Grotesk        wordmark, headings, hero copy
font-mono       JetBrains Mono       kbd hints, tabular numerics
default         system sans          body, labels, dock chip text
```

Use `font-display` for the brand wordmark and any prominent heading the user is meant to read first. `font-mono` for keyboard-shortcut chips and any number that the user reads as data (volume %, octave shift, BPM if we ever add one).

---

## Motion

```ts
// from @/lib/motion
FLASH_MS.tight  = 120   // percussive (drums)
FLASH_MS.medium = 200   // pitched single notes + chord strums (keyboard, bass, guitar)
FLASH_MS.long   = 450   // sustained ambient (pad)
REMOTE_FLASH_DELTA_MS = 80
```

Each pad's `flash()` and `flashRemote()` should clear the highlight after `FLASH_MS.{tier}` and `FLASH_MS.{tier} + REMOTE_FLASH_DELTA_MS` respectively. Don't pick a new number — pick the right tier.

---

## Layout primitives

### Stage (the big instrument area)

The studio breaks out of `Layouts.app`'s `max-w-3xl` constraint with a negative-margin wrapper, then applies its own `max-w-5xl` so the kit / fretboard / chord grid has room. See `studio_live.ex` for the wrapper.

### Floating dock (bottom)

```
class="fixed inset-x-0 bottom-4 px-4 z-40 pointer-events-none"
  └─ inner: class="mx-auto max-w-3xl pointer-events-auto"
     └─ content: class="flex items-center gap-2 rounded-2xl border bg-card/80 backdrop-blur-md px-2 py-1.5 shadow-2xl"
```

Holds the instrument switcher tabs, presence avatar stack, and "N jamming" count. The outer `pointer-events-none` means clicks fall through the empty area around the dock to whatever is behind.

### Floating mini-bar (top-right control strip)

Same visual language as the dock, lighter weight:

```
class="rounded-xl border bg-card/60 backdrop-blur-sm px-3 py-1.5 shadow-sm"
```

Used for the studio's Replay 30s + master volume strip.

### Full-screen overlay (tap-to-enter)

```
class="fixed inset-0 z-50 backdrop-blur-md bg-background/80 cursor-pointer"
```

Wrap with `<Transition>` for a fade in / out. The whole overlay is the click target; the visible button is just an affordance.

---

## Controls

### Style chip toggle (per-instrument flavor selector)

```
Inactive:
  class="px-3 py-1 text-xs rounded-md border bg-card hover:bg-accent text-muted-foreground border-input"

Active:
  class="px-3 py-1 text-xs rounded-md border bg-accent-{instrument} text-background border-accent-{instrument}"
```

Substitute `{instrument}` with the pad's accent — the chip tints in the same neon as the rest of that pad's UI.

### Octave +/- stepper

```
class="px-2 py-1 text-xs rounded-md border bg-card hover:bg-accent text-muted-foreground border-input disabled:opacity-30 disabled:cursor-not-allowed"
```

The numeric display between the `−` and `+` buttons:

```
class="text-sm tabular-nums font-mono w-{6|8|20} text-center"
```

Width depends on what's displayed: `w-6` for a single digit ("2"), `w-8` for a signed integer ("+2"), `w-20` for a range ("C3–C6").

### Pad button (drum / chord / fret / piano key)

Idle:

```
class="rounded-md border bg-card flex flex-col items-center justify-center gap-2 select-none transition-all active:scale-95 hover:bg-accent"
```

Local press flash (tap on this device):

```
'ring-2 ring-accent-{instrument} scale-95 glow-{instrument}'
```

Drums use `ring-4` (their pads are bigger). Keyboard's white keys instead use `bg-accent-keyboard text-background border-accent-keyboard glow-keyboard` because a ring inside a piano-key shape doesn't read.

Remote flash (someone else played this):

```
'ring-{2|4} ring-orange-400'
```

Always orange — not the instrument's own accent — so remote vs. local is immediately distinguishable.

### kbd hint chip

```
class="text-xs px-1.5 py-0.5 rounded bg-muted text-muted-foreground font-mono"
```

Smaller variants for keyboard pad's white / black keys override the bg/text but keep the rest:

```
white-key:  "text-[10px] px-1 py-0.5 rounded bg-slate-200 text-slate-600 font-mono"
black-key:  "text-[9px]  px-1       rounded bg-slate-700 text-slate-300 font-mono"
```

---

## Logo

The mark is the M-wave: two pillars + a wave-shaped top edge, drawn as one continuous stroke. Two SVG variants ship at `assets/public/images/`:

| File             | Stroke fill                          | When to use                                                                  |
| ---------------- | ------------------------------------ | ---------------------------------------------------------------------------- |
| `logo.svg`       | magenta → cyan → lime gradient       | Default. Header wordmark, favicon, branding moments.                          |
| `logo-mono.svg`  | `currentColor` — inherits from text   | Monochrome contexts: print, OG cards if reduced-color, single-tone embeds.    |

### Sizes

| Size  | Use                                                                |
| ----- | ------------------------------------------------------------------ |
| 16 px | favicon                                                             |
| 32 px | header chip alongside the wordmark                                  |
| 80 px | tap-to-enter overlay, "hero" moments                                |
| ≥256 px | print, OS app icon, social card                                  |

PNG exports at 16 / 32 / 48 / 64 / 128 / 256 / 512 / 1024 + a multi-size `.ico` live in `branding/`. Re-export after editing the SVG with the snippet in that commit (`8e8137c`).

### Clearspace

Reserve at least one **stroke-width** of empty space (≈ 8% of the logo's height) on every side. The wordmark next to the logo in the header gets `gap-2` (8 px) — that's the floor.

### Wordmark + logo combination

When both appear together (header pattern), set the wordmark in `font-display font-bold tracking-tight` at the same vertical scale as the logo's height. Don't use the wordmark without the mark in primary navigation.

### Don'ts

- Don't recolor the gradient. If you need a different colour, use `logo-mono.svg` and let `currentColor` carry the brand.
- Don't apply effects (shadow, glow, outline) — the mark is meant to read as pure line art.
- Don't crop or distort. The viewBox is square; if you need a wordmark-only layout, use plain `font-display` text instead.

---

## Voice

### Tone

Casual but capable. Like a friend showing you a tool they built, not a corporate dashboard. The user is here to make music — copy should stay out of the way and, when it does speak, sound like another musician would.

### Rules

- **Sentence case** for buttons, labels, and prompts. Not Title Case, not ALL CAPS — except for the small uppercase control labels (`Vol`, `Oct`, `Style`) which are visual badges, not sentences.
- **Verb-led button labels.** "Enter studio" not "Click here", "Replay 30s" not "Replay last 30 seconds", "Stop replay" not "Cancel".
- **Speak like a musician.** "jam", "strum", "hold", "tap" — not "submit", "execute", "perform action".
- **Be short.** A control label that needs to wrap is too long; rename it.
- **No exclamation points** unless something genuinely critical happens (audio failure, disconnect). Casual ≠ excitable.
- **Numbers stay numerals.** "3 jamming" not "three jamming". Tabular-nums + `font-mono` everywhere a count appears.

### Audit of current copy

| Surface             | Current text                                              | Notes                                                  |
| ------------------- | --------------------------------------------------------- | ------------------------------------------------------ |
| Header subtitle     | "a real-time jam room"                                    | ✓ on tone                                               |
| Tap-to-enter title  | "Tap to start jamming"                                    | ✓ on tone                                               |
| Tap-to-enter helper | "Browsers need a gesture before audio can play"           | ✓ informative, neutral                                  |
| Tap-to-enter button | "Enter studio"                                            | ✓ verb-led                                              |
| Replay button       | "Replay 30s" / "Stop replay"                              | ✓ short + verb-led                                      |
| Dock count          | "{N} jamming"                                             | ✓ casual, action-coloured                               |
| Volume / octave     | `Vol` / `Oct`                                             | ✓ uppercase = control badge, fine                       |

### Empty / error states (when we add them)

- **Empty room**: "Quiet here — start a chord and someone'll join." (suggest action, don't shame the count)
- **Audio failure**: "Audio dropped. Tap to try again." (specific, recoverable)
- **Disconnect**: "Reconnecting…" (calm, ephemeral)

---

## Responsive

The studio is designed desktop-first, but every primitive has a mobile fallback. Tailwind breakpoints we use:

```
default: mobile           (< 640 px)
sm:      tablet            (≥ 640 px)
lg:      laptop / desktop  (≥ 1024 px)
```

`md:` is rarely used — most layouts shift cleanly between mobile and `sm:`.

### Stage container

```
class="-mx-4 sm:-mx-6 lg:-mx-8 -my-10 px-4 sm:px-6 lg:px-8 pt-4 pb-28"
```

Negative margins to break out of `Layouts.app`'s `max-w-3xl`; padding scales by breakpoint. Bottom padding keeps content from sliding under the fixed dock.

### Floating dock

`max-w-3xl` ensures it doesn't stretch on wide screens; `inset-x-0 px-4` lets it shrink on narrow screens. Inside, `flex items-center gap-2 overflow-x-auto` on the tabs means the tabs scroll horizontally when there are too many to fit.

### Pad-specific

| Pad      | Mobile pattern                                                                      |
| -------- | ----------------------------------------------------------------------------------- |
| Drums    | Fixed aspect-ratio container, `max-w-540px`, scales naturally                        |
| Keyboard | 22 white keys + 15 blacks; `min-width: 720px` + `overflow-x-auto` so phones scroll  |
| Guitar   | Chord grid `grid-cols-2 sm:grid-cols-4` — 2 cols on mobile, 4 on desktop             |
| Bass     | Fretboard `min-width: 560px` + `overflow-x-auto`                                     |
| Pad      | Chord grid `grid-cols-2 sm:grid-cols-4` (same as guitar)                             |

The keyboard and bass scroll horizontally on phones rather than crush. A 22-key keyboard at 16px per key is unreadable; better to scroll than to shrink past usability.

### Style chip strips

Wrap with `flex flex-wrap gap-1`. Five-chip strips (guitar) wrap to a second line on narrow screens; three-chip strips (drums, bass, keyboard, pad) usually fit on one line.

### Tap targets

Minimum 44 × 44 px for any interactive element on touch (Apple HIG). Most pads are well above this; the smallest currently is the drum HH Pedal at ~12% width × 12% height of a 540 × 324 px container ≈ 65 × 39 px. Acceptable — barely.

### Don'ts

- Don't use `lg:` to fundamentally change layout (sidebar in/out). Stage + dock works at every width; let it scale.
- Don't hide content on mobile. If something is needed on desktop, it's needed on mobile.
- Don't rely on hover. Pads and dock tabs all have explicit press / active states for touch.

---

## When in doubt

If you find yourself reaching for a fresh class string that's *almost* one of these but tweaked, lift it into this doc as a new primitive instead. Same for any `setTimeout(..., 250)` that doesn't match a `FLASH_MS` tier — figure out which tier it belongs to.

Keeping the canon small is the whole point.
