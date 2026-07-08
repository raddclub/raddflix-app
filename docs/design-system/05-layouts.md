# Volume V — Layouts

## Text Wireframes (Figma-style, per screen)

### Home
```
────────────────────────────────────────────
 Status bar (transparent, content bleeds under)
────────────────────────────────────────────
 [ON AIR — full bleed, 62% of viewport height]
   ┌──────────────────────────────────────┐
   │           poster art (full)           │
   │        gradient fade → bg at base     │
   │                                        │
   │  ⚡ Data-Free            (top-right)   │
   │                                        │
   │  Title (display, 34sp)                │
   │  ● 2h 14m · 2025 · ⭐8.4  (bodyStrong) │
   │  [▶ Play]  [Ghost: + Watchlist]        │
   │                                        │
   │  ↕ swipe for next   ·   dot indicator  │
   └──────────────────────────────────────┘
────────────────────────────────────────────
 [Bottom-left overlay, pinned to hero base]
 ⚡ 4.2 GB saved this month  (signalNumeral)
────────────────────────────────────────────
 Category chips (scrollable)   [All][Movies][Shows][Free]
────────────────────────────────────────────
 Trending                                  →
 [Card][Card][Card][Card]…
────────────────────────────────────────────
 Continue Watching                         →
 [ResumeFab row, 64dp tall each]
────────────────────────────────────────────
 Free to Watch  ⚡                          →
 [Card+badge][Card+badge][Card+badge]…
────────────────────────────────────────────
 … more rails …
────────────────────────────────────────────
 Bottom Nav: Home● Search Downloads Profile
────────────────────────────────────────────
```
Padding: 16dp screen margins throughout; rail vertical gap 24dp; card gutter 8dp.

### Search
```
────────────────────────────────────────────
 [Search bar — focus-glow border, 52dp tall]
  🔍 Search movies, shows...
────────────────────────────────────────────
 Mood chips:  [Free tonight ⚡][Short][Feel-good][Filters ⚙]
────────────────────────────────────────────
 Recent searches (chip row w/ thumbnails)
────────────────────────────────────────────
 Results grid (2:3 cards, 3-column phone / 5-column tablet)
 [Card][Card][Card]
 [Card][Card][Card]
────────────────────────────────────────────
```
Filter tap → `RaddSheet` slides up (genre/rating/year/status).

### Show Detail
```
────────────────────────────────────────────
 [Parallax hero art, 45% viewport, SliverAppBar]
  ← back            ⋮ more
────────────────────────────────────────────
 Title (headline)         ⚡ Data-Free
 ⭐8.4 · 2025 · 2h14m · 16+        (bodyStrong)
 [▶ Play — full width, Signal]
 [Ghost: + Watchlist]  [Ghost: ⬇ Download]
────────────────────────────────────────────
 Synopsis (body, 3-line clamp)  "more"
────────────────────────────────────────────
 Cast                                      →
 [avatar+name][avatar+name]…
────────────────────────────────────────────
 Episodes ▾ (Season 1)
 [thumb | title | runtime | ⬇]
────────────────────────────────────────────
 More Like This                            →
 [Card][Card][Card]
────────────────────────────────────────────
```

### Player (default HUD — collapsed)
```
────────────────────────────────────────────
[ video surface, full bleed, edge-to-edge ]

  ⚡ pulse (top-left, if data-free)          ⋯ More (top-right)

        (center third — kept clear)

  ◀◀    ▶ / ⏸ (56dp, centered)    ▶▶

────────────────────────────────────────────
 00:14:22 ━━━━━●───────────── 01:58:03   [CC] [⤢]
────────────────────────────────────────────
```
Gesture zones (invisible): left third = brightness (vertical drag), right third = volume (vertical drag), full width = seek (horizontal drag + preview label), pinch anywhere = zoom.

### Player — "More" sheet (3 tabs)
```
────────────────────────────────────────────
 ▔▔▔  (drag handle)
 [ Playback | Audio & Video | Extras ]   ✕
────────────────────────────────────────────
 Playback tab:
   Speed        0.5x ─●───── 2x
   Sleep Timer  Off ▾
   Subtitles    English ▾
────────────────────────────────────────────
```

### Settings Hub
```
────────────────────────────────────────────
 Settings                                 (headline)
────────────────────────────────────────────
 ▸ Playback
 ▸ Privacy & Vault
 ▸ Account
 ▸ Data & Downloads      ⚡ 4.2 GB saved
 ▸ Accessibility
 ▸ About
────────────────────────────────────────────
```

### Lock Screen (`RaddLockPad`, shared)
```
────────────────────────────────────────────
        (gradient icon, 64dp, pulsing)

           ● ● ● ○     (PIN dots)

────────────────────────────────────────────
        1        2        3
        4        5        6
        7        8        9
      biometric   0     ⌫
────────────────────────────────────────────
```

### Onboarding (taste capture → starter watchlist → signup)

Three steps, reciprocity-first: real free content is already visible before this flow starts (Volume I), and progress never starts at 0% — step 1 ("opened the app") is pre-credited so the bar opens at ~25%, not empty (goal gradient effect).

```
Step 1 — Genre taste capture
────────────────────────────────────────────
 What do you like to watch?         (headline)
────────────────────────────────────────────
 [Action][Drama][Comedy][Romance][Thriller]
 [Anime][Urdu Dubbed][Kids][Sports][Horror]
────────────────────────────────────────────
 ▓▓▓▓░░░░░░░░░░░  25%          (never 0%)
           [ Continue → ]
────────────────────────────────────────────

Step 2 — Build your starter watchlist
────────────────────────────────────────────
 Pick a few to start with            (headline)
 (grid of RaddCard, tap to add — filled by
  genre picks from Step 1, incl. Free ⚡ titles)
 [Card+][Card+][Card+][Card+][Card+][Card+]
────────────────────────────────────────────
 ▓▓▓▓▓▓▓▓▓░░░░░░  60%
           [ Continue → ]
────────────────────────────────────────────

Step 3 — Save your list (signup)
────────────────────────────────────────────
 Your watchlist is ready              (headline)
 [thumb][thumb][thumb] +2 more
 "Save this list so it's here next time"
────────────────────────────────────────────
 ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ 100%
        [ Save & Continue → ]
        (not "Sign Up" — the list is
         already theirs; this button
         keeps it, per the endowment effect)
────────────────────────────────────────────
```

## Responsive Layout Rules

| Breakpoint | Range | Home hero | Card grid | Nav |
|---|---|---|---|---|
| Small phone | <360dp width | Hero 58% viewport height, cards 96×144dp, 2-col grid in Search | Bottom nav, labels shown |
| Large phone | 360–599dp | Hero 62% viewport height, cards 120×180dp, 3-col grid | Bottom nav, labels shown |
| Tablet (portrait) | 600–839dp | Hero capped at 480dp height, cards 140×210dp, 4-col grid | Bottom nav widens, max content width 720dp centered |
| Tablet (landscape) / small desktop | 840–1239dp | Hero fixed 16:9 banner, 5-col grid | Side nav rail (80dp, icons + tooltip) instead of bottom nav |
| Desktop/web | ≥1240dp | Hero 16:9 banner, max content width 1440dp centered, 6+ col grid | Side nav rail expands to 240dp with labels; hover states on cards (scale 1.03 + border glow) |

General rule: below 600dp, single-column linear flow; at/above 600dp, cap line length and increase grid density rather than stretching components edge-to-edge.

Forward-looking targets (not immediate build): Foldable (dual-pane at hinge), TV/10-foot (large focus rings, D-pad navigation order).
