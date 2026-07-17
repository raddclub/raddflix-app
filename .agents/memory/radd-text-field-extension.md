---
name: RaddTextField custom params
description: RaddTextField D4 extension — added textInputAction, inputFormatters, onFieldSubmitted so forms can do keyboard chaining without leaving the component.
---

Added in D4 (radd_text_field.dart):
- `TextInputAction? textInputAction` → wired to `TextField.textInputAction`
- `List<TextInputFormatter>? inputFormatters` → wired to `TextField.inputFormatters`
- `ValueChanged<String>? onFieldSubmitted` → wired to `TextField.onSubmitted`

**Why:** Login/register screens needed keyboard-chain (Next → Done) and phone formatter without switching to raw TextField. All three params are nullable so all existing callers are backward-compatible.

**How to apply:** Pass `textInputAction: TextInputAction.next`, `focusNode: _myFocus`, `onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_nextFocus)` on the intermediate field; `textInputAction: TextInputAction.done`, `onFieldSubmitted: (_) => _submit()` on the last field.
