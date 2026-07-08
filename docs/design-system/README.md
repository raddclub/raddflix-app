# RaddFlix Design System v1.0

This is the complete design system specification for the next-generation RaddFlix experience, built on the "Open Frequency" brand concept. It was produced through a four-stage process: codebase audit → UX analysis & modernization strategy → brand identity & redesign blueprint → construction-level specification.

**Status:** Documentation frozen at v1.0. No app code has been changed to implement any of this yet — see `ROADMAP.md` for the implementation plan.

## Volumes

1. [Brand Identity](01-brand-identity.md) — the "Open Frequency" concept, protected colors, RaddFlix Principles (the design constitution)
2. [Visual Language](02-visual-language.md) — color tokens, typography scale, spacing, radius, elevation, icon system
3. [Motion](03-motion.md) — Pulse & Tune, the named motion language, easing curves and durations
4. [Components](04-components.md) — the full component catalog: RaddButton, RaddCard, RaddBanner, RaddSheet, RaddLockPad, SettingsRow and all their variants
5. [Layouts](05-layouts.md) — text wireframes for every major screen, responsive rules across phone/tablet/desktop
6. [Accessibility](06-accessibility.md) — contrast, text scaling, screen readers, motion reduction, touch targets
7. [Developer Guidelines](07-developer-guidelines.md) — build order, token usage rules, the Engineering Playbook (folder structure & conventions), Component Status Dashboard
8. [Component API Contracts](08-component-api-contracts.md) — Flutter-level properties/behavior/accessibility/animation/tokens/examples per component
9. [Migration Guide](09-migration-guide.md) — existing widget → redesigned counterpart mapping
10. [Interaction Principles](10-interaction-principles.md) — navigation, loading, error, animation, typography, color, and player rules
11. [Performance Standards](11-performance-standards.md) — paint/frame/memory budgets per screen
12. [Quality Checklist](12-quality-checklist.md) — the per-screen release gate

See also [ROADMAP.md](ROADMAP.md) for implementation phases, [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for the token/component-to-codebase mapping, [CHANGELOG.md](CHANGELOG.md) for revision history, and [AI_RULES.md](AI_RULES.md) for the fast-context rules any AI assistant should read before touching UI code.

## Folder structure

```
docs/design-system/
├── assets/           wireframes, mockups, diagrams, icons, logos (as they're produced)
├── README.md         this file
├── 01-brand-identity.md … 12-quality-checklist.md
├── AI_RULES.md
├── ROADMAP.md
└── CHANGELOG.md
```

## How to use this

- Building a new screen or component? Read Volume IV (Components) and Volume VIII (API Contracts) first, then check Volume XII (Quality Checklist) before calling it done.
- Migrating an existing screen? Start with Volume IX (Migration Guide) to find its mapping, then Volume V (Layouts) for the target wireframe.
- Making a product decision that isn't covered anywhere? Fall back to the ten RaddFlix Principles in Volume I — they're the tiebreaker.
- Do not create new one-off audit/handoff/status files for this work — update these canonical docs instead, per this repo's `AGENT_PROMPT.md` doc-sprawl rule.
