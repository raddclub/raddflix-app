# Volume X — Interaction Principles

Something many commercial apps never document, yet it makes the product feel coherent.

## Navigation Rules
- Never open more than one modal/sheet at a time — opening a new one dismisses the current.
- Never stack bottom sheets.
- Always preserve scroll position when returning to a screen (rails, grids, episode lists).
- System/hardware back always returns to the previous content state, never force-exits to Home.
- The Player never closes accidentally — back gesture from the Player always shows a lightweight confirm-or-minimize affordance rather than an instant exit, except when explicitly ended via a dedicated close control.

## Loading Rules
- <250ms: show nothing — a spinner here reads as broken, not fast.
- 250–1000ms: skeleton (geometry-matched shimmer).
- >1000ms: skeleton + loading message (`caption`, e.g. "Finding something great…").
- >5000ms: offer retry, do not spin indefinitely.

## Error Rules
Every error surface must state, in order: what happened → why (if known) → what the user can do → a retry action. Never display a raw exception, stack trace, or backend error code to the user.

## Animation Rules
- Never animate more than three elements simultaneously in one transition.
- Infinite/looping animation is reserved for exactly three cases: `Pulse` (live/data-free indicators), download progress rings, and live-session indicators (Watch Party). No other element loops indefinitely.
- Reduced-motion setting disables `Pulse` scale and `Tune` overshoot app-wide, falling back to instant or opacity-only transitions.

## Typography Rules
- Maximum three distinct type sizes visible within a single screen section.
- Do not bold more than one element per row/card.
- Never set body text in uppercase (reserved for `label` scale only: chips, tags, badges).

## Color Rules
- One primary (`Signal`) action per screen.
- One accent hue in play at a time — crimson (`signal.primary`) is the only interactive hue.
- `accent.dataFree` (signal-green) means exactly one thing: this content or session is free. Never repurposed for generic success/online/available/downloaded states.
- Warnings use `accent.warning` (amber), not red — red (`accent.error`) is reserved for actual failure states.

## Loss-Framing Rules (Plan Expired / Quota Full / Renewal)

- State what becomes inaccessible by name and count, not generically: "Your 4 downloaded shows will be removed in 3 days," not "Your plan has expired."
- The dismiss/decline action must acknowledge the cost rather than offer a free escape: prefer "Continue without access" over "Maybe later" or "Not now."
- Never pair a loss-framed screen with a countdown-free, low-stakes tone — the two must be consistent (see Volume V Subscription/Quota screens once specced).
- This applies only to genuine plan/access-lapse states, not general upsells — routine "Upgrade" prompts elsewhere in the app keep a neutral, non-threatening tone per Principle 1 (content comes first, no dark patterns).

**Why:** loss aversion is roughly twice as motivating as equivalent-gain framing (Kahneman). RaddFlix's existing Plan Expired/Quota Full screens are already unusually empathetic — this rule sharpens their copy without changing that tone or introducing manipulative pressure.

## Price-Anchoring Rules (Subscription Screen)

- Never display a single plan's price in isolation. Show a higher-tier or annual price first (visually or in reading order) so the target plan's price is evaluated in contrast, not absolute.
- Where relevant, reuse the `signalNumeral` data-saved figure as a contrast anchor for the zero-rating value prop (e.g., pairing a data-cost estimate with the "free" outcome), consistent with its existing use on Home (Volume V).
- Do not apply this pattern to reframe genuine costs deceptively — anchor with real, truthful comparison numbers only (no invented "original price" style dark patterns).

**Why:** users evaluate price relative to the most recent number they saw, not in absolute terms (the contrast effect) — this is a presentation-order change, not a pricing change.

## Player Rules
- Video always has visual priority — no control, sheet, or overlay may cover more than 40% of the video surface at once.
- Controls auto-hide after 3s of inactivity during playback.
- No modal or sheet blocks playback — audio/video continues under any `RaddSheet` opened from the Player.
- All advanced/power controls live behind "More" — the default HUD never grows past its specified 5-control set (Volume V wireframes).
