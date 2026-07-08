# Volume XII — Quality Checklist

The per-screen release gate. Every screen must pass this checklist before shipping under the RaddFlix Design System — same fifteen checks, no per-screen exceptions.

```
[ ] Uses design tokens only (RaddType, RaddSpace, RaddColors) — no hardcoded hex/px
[ ] Uses RaddButton for all actions — no raw ElevatedButton/TextButton
[ ] Uses RaddCard variants for all content tiles — no bespoke card widgets
[ ] Uses RaddSheet for all modals/bottom sheets — no raw AlertDialog/showModalBottomSheet
[ ] Uses SettingsRow for any list-style settings UI
[ ] No hardcoded colors outside the theme extension
[ ] Meets accessibility minimums (contrast, touch targets, semantics labels)
[ ] Responsive across small phone / large phone / tablet / landscape breakpoints
[ ] Hero/shared-element transition present where navigation implies continuity
[ ] Sustains 60fps on mid-tier device profile
[ ] Skeleton loading state implemented (not spinner-only) for >250ms loads
[ ] Empty state implemented via AnimatedEmptyIcons
[ ] Offline state handled via RaddBanner(offline)
[ ] Error state follows Volume X Error Rules (what/why/action/retry)
[ ] Reduced-motion setting respected
[ ] Signal-green used only for data-free indication (if applicable to this screen)
```

Applies identically to Home, Search, Show Detail, Player, Settings, Profile Switcher, Lock Screens, Onboarding, and Downloads.
