---
name: JS String.replace dollar-pattern trap
description: When using JS String.replace(old, new), `$'` and `$\`` in the replacement string are special patterns that insert surrounding content — causes silent file corruption when patching Dart code containing `$`.
---

## The Trap

JavaScript `String.prototype.replace(searchStr, replStr)` treats several `$`-prefixed patterns as special in `replStr`:

- `$$` → literal `$`
- `$&` → matched substring
- `$'` → portion of string **after** the match (suffix)
- `` $` `` → portion of string **before** the match (prefix)
- `$n` → nth capture group

Dart raw strings such as `r'^\[|\]$'` end with `$'` (dollar + apostrophe).  
When this appears in a JS replacement string, `$'` inserts the entire file suffix — **doubling the output** silently.

**Why:** The bug caused `search_screen.dart` to grow from 1348 → 2424 lines (duplicate classes, orphaned blocks) and failed CI with Dart parse errors. Root-cause was `bracketNew` containing `r'^\[|\]$'` as the replacement, with `$'` triggering the JS suffix-insert pattern.

## How to Apply

Whenever writing a JS `String.replace(old, new)` patch where `new` contains Dart code:

1. Scan `new` for any `$` character.
2. If `$` appears before `'`, `` ` ``, `&`, or a digit → escape it as `$$` in the JS string.
3. `$$` in the replacement → literal `$` in the output (correct Dart code).

**Example fix:**
```javascript
// WRONG — $' inserts file suffix:
const NEW = "final re = RegExp(r'^\\[|\\]$');";

// CORRECT — $$ → literal $:
const NEW = "final re = RegExp(r'^\\[|\\]$$');";
// Output in file: `final re = RegExp(r'^\[|\]$');`  ✓
```

## Safer Alternative

Use a function as the replacement to bypass all `$` special patterns entirely:

```javascript
src = src.replace(OLD, () => NEW);
// Arrow function return value is used verbatim — no `$` interpretation.
```

This is the safest approach whenever the replacement string contains Dart code with `$`.
