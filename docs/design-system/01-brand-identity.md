# Volume I — Brand Identity

## The Identity Question

Before tokens or screens: what makes RaddFlix look like RaddFlix and nothing else?

RaddFlix's one truly unique fact, invisible in every screenshot so far, is this: **it's the only streaming app where watching costs the user nothing on their data plan.** That's not a footnote — it's the entire reason the product exists. The old UI hid that fact behind generic streaming-app visual language (rails, glass panels, crimson accent) that could belong to any regional OTT app.

## Concept: "Open Frequency"

*Visual metaphor: RaddFlix isn't a library you browse — it's a signal that's always live and always free to receive, like tuning into a frequency that's already broadcasting for you.*

This gives every design decision a reason to exist beyond "looks modern":

- The existing crimson accent (`#E8002D`) stops being just "the accent color" and becomes **the transmission color** — the one thing that's always warm/alive against the otherwise deep, quiet dark canvas, the same way an "ON AIR" light or a signal-strength bar is the one warm thing in a dark control room.
- Motion is built around **waveform and pulse**, not generic slide/fade — content breathing, a live signal, not a static catalog.
- The zero-data promise becomes an ambient, positive presence in the UI (a *signal strength* motif) instead of a hidden backend fact — this is the thing Netflix and Disney+ structurally cannot copy.

Keep the existing dark-first, glass-forward foundation — it's good and already partway there. Deepen it toward "Open Frequency," don't replace it.

## Protected Colors

`signal-green` (`#3DDC97`, token `accent.dataFree`) is a protected, single-purpose color. It means exactly one thing: **this content is free.** It never means success, online, available, active, or downloaded — those use neutral or crimson-adjacent tonal treatments instead. This scarcity is what makes it register as meaningful branding rather than decoration.

## RaddFlix Principles (the constitution)

These are the philosophical rules that guide every future decision — not interaction rules or button sizes, but the tiebreaker when a new feature request is ambiguous or contested.

1. **Content comes first.** UI never competes with the movie.
2. **Free should always be visible.** The zero-data advantage is a product feature, not a hidden implementation detail.
3. **One obvious action.** Every screen has one primary action.
4. **Progress over perfection.** Users always know what the app is doing.
5. **Consistency beats novelty.** Reuse components before inventing new ones.
6. **Motion has purpose.** Every animation communicates state, focus, or continuity — never decoration alone.
7. **Fast feels premium.** Perceived performance matters as much as raw performance.
8. **Accessibility is a feature.** Every interaction should work for as many users as possible.
9. **Reduce cognitive load.** Hide advanced functionality until it's needed.
10. **The app should disappear.** The user's attention belongs on the story, not the interface.

If a new feature request conflicts with one of these, the principle wins by default unless there is an explicit, documented reason to override it — record that reason in `CHANGELOG.md` if it happens.

## Reciprocity — Value Before Ask

RaddFlix's first-run experience must give before it asks. A user should be able to see real, browsable, playable-preview content — including a live "Free to Watch ⚡" rail with actual titles — before any login/signup wall appears. Gating the entire catalog behind auth on first launch is the single biggest violation of Principle 2 ("Free should always be visible") possible: it hides the product's core value exactly when it matters most to prove it.

**Why:** users don't trust an ask until they've received something first (the reciprocity principle) — free samples, previews, and usable-before-paywall products convert dramatically better than "sign up to see anything." RaddFlix's zero-rated-data advantage is real, immediate value it can show for free, unlike apps that have nothing to give away before payment.

**How to apply:** first-run flow is Browse (real free content visible) → Onboarding (taste capture, see Volume V) → Signup, never Signup → Browse. Any future paywall or login gate proposal must be checked against this ordering before being approved.

## Why Not "Be Like Netflix"

The redesign strategy deliberately avoids "how can RaddFlix become like Netflix?" in favor of "how can RaddFlix become recognizable as RaddFlix while remaining world-class?" Netflix, Spotify, Discord, and Plex all follow modern design principles, but each has its own unmistakable visual identity — Open Frequency, the protected signal-green color, and the Pulse/Tune motion language (Volume III) are what make this possible for RaddFlix.
