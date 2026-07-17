---
name: Cross-mixin abstract declaration pattern
description: Pattern for sharing methods/getters across the player's mixin cluster. Missing declarations silently break the release build.
---

## Rule
Every method or getter that is *defined* in one mixin but *called* in another must have an abstract declaration in the consuming mixin's header section.

## Why
Dart mixins cannot see each other's members directly. The `_PlayerScreenState` class combines all mixins, so all members exist at runtime — but the Dart compiler rejects a mixin that references an undefined name, even if it will be present at runtime.

## How to apply
- `_ps_ui_mixin.dart` header (~lines 17–98): abstract decls for everything UI calls from Playback or AudioLab.
- `_ps_playback_mixin.dart` header (~lines 16–56): abstract decls for everything Playback calls from UI or the screen state.
- Pattern used twice in Z1 work: `_shuffleEnabled`/`_toggleShuffle` (missing in UI mixin) and `_scheduleSavePrefs` (missing in Playback mixin).
- Each time CI fails with "X isn't defined for mixin Y", add the abstract decl to that mixin's header.
