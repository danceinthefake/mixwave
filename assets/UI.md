# mixchamb UI primitives

A reference for the patterns that already exist in mixchamb. New UI work should copy from this canon instead of inventing its own — that's how a design system stays one.

The CSS variables and Tailwind theme tokens that back these classes live in `assets/css/app.css`. The motion timings live in `assets/vue/lib/motion.ts`. The fonts come from Google Fonts via `lib/mixchamb_web/components/layouts/root.html.heex`.

---

## Design principles

The visual language was re-anchored to the **brick-stack M** logo when mixchamb pivoted from music-only to multi-activity in v4. The mark is 23 small rounded-rectangle tiles arranged in seven horizontal courses; the M shape emerges from which cells are filled. Three properties carry into the rest of the system:

- **Modular.** Compose UI from repeating units with consistent proportions. A row of voting cards, a participant strip, an instrument switcher tab strip — they should all read as the same kind of object at a different scale. Avoid one-off shapes when a tile rhythm fits.
- **Gridded.** Spacing rhythm is 2 / 4 / 8 / 16 / 24 — the proportions of bricks-and-gaps in the logo. Pick the increment that matches the relationship being drawn (2 px between siblings in a tight cluster, 8 px between sections of a card, 24 px between unrelated regions). Don't pick 6, 10, 14.
- **Restrained.** The gradient and the per-activity accents do the chromatic work; everything else is neutral. The logo doesn't carry effects (shadows, glow, outline) and neither should card chrome — surfaces are flat, borders are 1 px, motion is in service of state transitions only.

Where these principles point at concrete numbers, see *Spacing & radius* below.

---

## Color tokens

### Brand gradient

The mixchamb mark fills with a 3-stop linear gradient, running left → right across the whole logo (`userSpaceOnUse`, not per-element), with the cyan stop at the true centre so pink and green each hold a full third of the visible mark:

```
0%    #e94886   pink / magenta
50%   #56d2e6   cyan
100%  #b5e651   lime / spring green
```

The horizontal direction matches the original mixwave wave-M wordmark — left column of bricks reads pink, middle column cyan, right column green. A 135° diagonal version was tried in 2026-05 and shipped briefly; cyan ended up dominating because the middle of the brick stack sits at ~50% offset on the diagonal, leaving pink and green only at the two corner bricks.

Use this gradient on:

- the logo (canonical use in `priv/static/images/logo.svg`)
- "primary" hero treatments where the brand needs to lead (landing page hero copy via `.brand-gradient-text`, OG image background, optional first-paint splash)

Don't use it as a fill on small UI chrome — small gradient bands read as noise, and the per-activity accents are the right palette there.

### Neutral surfaces (shadcn-vue zinc, with a deeper mixchamb dark variant)

```
bg-background    near-black w/ faint hue 280 tint   (page background)
bg-card          one step lighter than background    (cards, dock, pads)
bg-muted         dark gray                            (kbd hint chips)
bg-accent        slightly lit                         (hover surface)
text-foreground  bright white                         (primary text)
text-muted-foreground  ~65% opacity                   (subdued text)
border           white / 8%                           (1px borders)
```

### Music palette (per-instrument)

These tokens are scoped to the music activity. They're available everywhere but should only render when `chamber.activity == "music"`. Other activities reach for their own palette (see *Activity palette* below).

| Instrument | Token             | Hue                            | Used for                                          |
| ---------- | ----------------- | ------------------------------ | ------------------------------------------------- |
| Drums      | `accent-drums`    | magenta `oklch(0.72 0.27 340)` | flash ring, glow, dock tab when active            |
| Keyboard   | `accent-keyboard` | cyan    `oklch(0.80 0.17 200)` | "                                                 |
| Guitar     | `accent-guitar`   | lime    `oklch(0.85 0.22 130)` | " + chord-diagram dots + barre line               |
| Bass       | `accent-bass`     | orange  `oklch(0.80 0.20 55)`  | " + fretboard pressed-fret tint                   |
| Pad        | `accent-pad`      | violet  `oklch(0.72 0.24 290)` | "                                                 |
| Suling     | `accent-suling`   | gold    `oklch(0.85 0.18 85)`  | "                                                 |
| Kendang    | `accent-kendang`  | rust    `oklch(0.70 0.22 25)`  | "                                                 |

Available as `bg-accent-{instrument}`, `ring-accent-{instrument}`, `text-accent-{instrument}`, `border-accent-{instrument}`, `glow-{instrument}`.

Remote flashes use `ring-orange-400` regardless of which instrument played them — a deliberately distinct colour so "someone else played this" always reads the same.

### Activity palette

Each new activity gets one accent token that carries its primary affordances (button highlights, chip-strip tints, presence dot when the activity is in play). Music is special — it uses the per-instrument palette above instead of a single accent.

| Activity | Token              | Hue                            | Status                              |
| -------- | ------------------ | ------------------------------ | ----------------------------------- |
| Music    | (uses Music palette) | per-instrument               | active                              |
| Poker    | `accent-poker`     | cyan `oklch(0.78 0.13 215)`    | **active** — `#56d2e6` from the brand gradient. Tints the activity chip's poker-active state, the "vote pending" silhouette border, and the reveal panel's distribution bars |
| Standup  | `accent-standup`   | —                              | reserved — not yet shipped          |
| Retro    | `accent-retro`     | —                              | reserved — not yet shipped          |

When a new activity ships, add one `oklch(...)` entry under `@theme inline` in `assets/css/app.css` and a row here. Don't introduce ad-hoc colors per component.

### Semantic accents

Tokens that carry meaning rather than activity identity. Use these where the *state* of a surface matters (action completed, error, etc.) regardless of which activity is in play.

| Token        | Hue                            | Used for                                                          |
| ------------ | ------------------------------ | ----------------------------------------------------------------- |
| `--primary`  | pink `oklch(0.68 0.21 5)`      | "your action" — Reveal / Next round buttons, selected vote card, current-user avatar, `--ring` focus outline. Same hue as the logo's leftmost stop (`#e94886`); intentionally not gradient-tinted so primary affordances stay legible on every background |
| `--success`  | lime `oklch(0.86 0.20 125)`    | confirmation / outcome / "the number you walked away with" — currently the Avg / Median / Mode values in `RevealPanel`. Same hue as the logo's rightmost stop (`#b5e651`). Reserve for positive feedback states; don't use as a generic "active" tint |
| `--destructive` | red                         | shadcn default — keep for destructive confirms (delete, reset) and inline error states. Don't replace with brand colours |

---

## Typography

```
font-display    Space Grotesk        wordmark, headings, hero copy
font-mono       JetBrains Mono       kbd hints, tabular numerics
default         system sans          body, labels, dock chip text
```

Use `font-display` for the brand wordmark and any prominent heading the user is meant to read first. `font-mono` for keyboard-shortcut chips and any number that the user reads as data (volume %, octave shift, BPM if we ever add one).

---

## Spacing & radius

### Spacing scale (the brick rhythm)

The brick-stack logo has small consistent gaps between tiles — ~16% of a tile's width. Scaled up to component land that becomes the increments below. Pick the one that names the relationship, not the one that "looks about right":

| Tailwind | px | Use                                                                                  |
| -------- | -- | ------------------------------------------------------------------------------------ |
| `gap-0.5` / `p-0.5` | 2 | inside a single visual unit (icon ↔ label inside a chip)                          |
| `gap-1` / `p-1`     | 4 | between siblings of the same kind (vote cards in a deck, chips in a strip)         |
| `gap-2` / `p-2`     | 8 | inside-card gutters, between control + its hint                                   |
| `gap-4` / `p-4`     | 16 | between sections of a card                                                       |
| `gap-6` / `p-6`     | 24 | between cards / unrelated regions                                                |

`gap-3` (12 px) is the one in-between value that's allowed — used inside the floating dock and other mid-density horizontal layouts. Avoid `gap-1.5`, `gap-2.5`, `gap-5`, `gap-7` unless you can name what they're for.

Named exception: **`gap-1.5` (6 px) for the icon-plus-label gutter inside a chip / button.** 4 px is too tight when a 14-or-16-px icon sits next to text, 8 px reads as a sibling separator rather than as "part of the same chip." 6 px is the one place that "between an icon and its label" needs its own value, and the codebase already uses it consistently for this — recording chips, dock tabs, the activity-switch chip-strip. Don't reach for `gap-1.5` anywhere else.

### Radius scale

Tighter than the previous default. The brick mark's tiles use `rx ≈ 6%` — modest rounding, not pill-like.

| Tailwind  | px | Use                                                                                |
| --------- | -- | ---------------------------------------------------------------------------------- |
| `rounded-sm` | 2 | kbd hint chips, the smallest interactive elements                                |
| `rounded-md` | 6 | buttons, chips, control toggles — the workhorse                                  |
| `rounded-lg` | 8 | pad surfaces, vote cards, instrument tiles                                       |
| `rounded-xl` | 12 | cards, dock, modals, mini-bar                                                   |
| `rounded-2xl` | 16 | hero containers, the chamber landing-page entry cards                          |

`rounded-full` is reserved for avatar circles and presence dots only. Don't reach for it on rectangles — the brick motif is square-ish.

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

### Stage (the chamber's big interactive area)

A chamber breaks out of `Layouts.app`'s `max-w-3xl` constraint with a negative-margin wrapper, then applies its own `max-w-5xl` so the kit / fretboard / chord grid / poker board has room. See `chamber_live.ex` for the wrapper.

### Floating dock (bottom)

```
class="fixed inset-x-0 bottom-4 px-4 z-40 pointer-events-none"
  └─ inner: class="mx-auto max-w-3xl pointer-events-auto"
     └─ content: class="flex items-center gap-2 rounded-2xl border bg-card/80 backdrop-blur-md px-2 py-1.5 shadow-2xl"
```

Holds the instrument switcher tabs (music only), presence avatar stack, and the activity-aware count ("N jamming" for music, "N here" otherwise). The outer `pointer-events-none` means clicks fall through the empty area around the dock to whatever is behind.

### Floating mini-bar (top-right control strip)

Same visual language as the dock, lighter weight:

```
class="rounded-xl border bg-card/60 backdrop-blur-sm px-3 py-1.5 shadow-sm"
```

Used for the music chamber's Replay 30s + master volume strip. Reuse the same class for any future per-activity floating mini-bar.

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

The mark is the **brick-stack M**: 23 small rounded-rectangle tiles arranged in seven horizontal courses, gradient-filled, the M shape emerging from which cells are present. Replaced the earlier M-wave mark when the brand broadened past music in v4 — the modular brick metaphor maps to mixchamb's "chambers of activities" framing in a way a single audio waveform never could.

Two SVG variants ship at `assets/public/images/`:

| File             | Fill                                          | When to use                                                                |
| ---------------- | --------------------------------------------- | -------------------------------------------------------------------------- |
| `logo.svg`       | brand gradient (pink → cyan → lime)            | Default. Header wordmark, favicon, branding moments.                       |
| `logo-mono.svg`  | `currentColor` — inherits from text            | Monochrome contexts: print, OG cards if reduced-color, single-tone embeds. |

### Sizes

| Size       | Use                                                                |
| ---------- | ------------------------------------------------------------------ |
| 16 px      | favicon (brick rhythm blurs into a textured M — acceptable)        |
| 32 px      | header chip alongside the wordmark                                 |
| 80 px      | hero moments, larger header treatments                             |
| ≥256 px    | print, OS app icon, social card, marketing                         |

PNG exports at 16 / 32 / 48 / 64 / 128 / 256 / 512 / 1024 + a multi-size `.ico` live in `branding/`. Re-render with `rsvg-convert -w <size> -h <size> priv/static/images/logo.svg > branding/logo-<size>.png` after editing the SVG, then repack the `.ico` with `magick branding/logo-16.png branding/logo-32.png branding/logo-48.png branding/logo.ico`.

### Clearspace

Reserve at least one **brick-height** of empty space on every side (~8% of the logo's height — same proportional rule as before, just measured against the brick instead of the old wave-stroke). The wordmark next to the logo in the header gets `gap-2` (8 px) — that's the floor.

### Wordmark + logo combination

When both appear together (header pattern), set the wordmark in `font-display font-bold tracking-tight` at the same vertical scale as the logo's height. Don't use the wordmark without the mark in primary navigation.

### Don'ts

- Don't recolor the gradient. If you need a different colour, use `logo-mono.svg` and let `currentColor` carry the brand.
- Don't apply post-process effects **to the mark itself** — no CSS filters, no `box-shadow` on the `<img>`, no `drop-shadow` SVG filter, no `outline`. The bricks carry the gradient; layering filters on top reads as noise.
- *Background* halos behind the mark are allowed on hero surfaces (e.g., the landing-page `.brand-glow` radial bloom behind the hero logo). They sit on a lower stacking layer; the mark itself is untouched. Use sparingly — at most one hero per page.
- Don't rebuild the M out of different tile counts or layouts to "fit" a new context. The 7-course, 23-tile composition is fixed.
- Don't crop or distort. The viewBox is square; if you need a wordmark-only layout, use plain `font-display` text instead.
- Don't try to animate individual bricks. The mark is meant to read as one object.

---

## Voice

### Tone

Casual but capable. Like a friend showing you a tool they built, not a corporate dashboard. The user is here to *do something together with other people* — music, planning poker, whatever the chamber's activity is. Copy stays out of the way and, when it speaks, sounds like another teammate would.

### Rules

- **Sentence case** for buttons, labels, and prompts. Not Title Case, not ALL CAPS — except for the small uppercase control labels (`Vol`, `Oct`, `Style`, `Kind`, `Activity`) which are visual badges, not sentences.
- **Verb-led button labels.** "Enter chamber" not "Click here", "Replay 30s" not "Replay last 30 seconds", "Stop replay" not "Cancel".
- **Speak in the activity's idiom.** Music UI says "jam", "strum", "hold", "tap". Poker UI says "vote", "reveal", "re-vote". Don't import music vocabulary into non-music UIs or vice versa.
- **Be short.** A control label that needs to wrap is too long; rename it.
- **No exclamation points** unless something genuinely critical happens (audio failure, disconnect). Casual ≠ excitable.
- **Numbers stay numerals.** "3 jamming" not "three jamming". Tabular-nums + `font-mono` everywhere a count appears.

### Audit of current copy

| Surface             | Current text                                              | Notes                                                  |
| ------------------- | --------------------------------------------------------- | ------------------------------------------------------ |
| Header subtitle     | "realtime collaborative chambers"                         | ✓ on tone; broadened past music for v4 multi-activity   |
| Tap-to-enter title  | "Tap to start jamming"                                    | ✓ music-specific (gate is music-only)                   |
| Tap-to-enter helper | "Browsers need a gesture before audio can play"           | ✓ informative, neutral                                  |
| Tap-to-enter button | "Enter chamber"                                           | ✓ verb-led                                              |
| Replay button       | "Replay 30s" / "Stop replay"                              | ✓ short + verb-led                                      |
| Dock count (music)  | "{N} jamming"                                             | ✓ casual, action-coloured                               |
| Dock count (other)  | "{N} here"                                                | ✓ neutral when no activity idiom fits                   |
| Volume / octave     | `Vol` / `Oct`                                             | ✓ uppercase = control badge, fine                       |
| Poker · pick prompt | "Pick a card"                                             | ✓ verb-led, in the poker idiom                          |
| Poker · re-vote     | "Re-vote" / "Next round"                                  | ✓ short, names the action precisely                     |

### Empty / error states (when we add them)

- **Empty music chamber**: "Quiet here — start a chord and someone'll join." (suggest action, don't shame the count)
- **Empty poker chamber**: "Waiting for the team. Share the link to start." (action + reason)
- **Audio failure**: "Audio dropped. Tap to try again." (specific, recoverable)
- **Disconnect**: "Reconnecting…" (calm, ephemeral)

---

## Responsive

Chambers are designed desktop-first (music in particular needs the horizontal room for keyboards and fretboards), but every primitive has a mobile fallback. Tailwind breakpoints we use:

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
