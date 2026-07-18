---
name: Edit tool truncates new_string at dollar sign
description: The Edit tool silently truncates new_string content at a bare $ character, corrupting the file and causing cascading Dart parse errors.
---

**Rule:** Never include a bare `$` in the `new_string` parameter of an Edit call. This includes regex patterns like `r'^03\d{9}$'` — the `$` causes silent truncation of everything after it.

**Why:** The Edit tool appears to treat `$` as a special character in the replacement string, even inside raw Dart string literals. The result is a truncated file that compiles with cascading parse errors (ambiguous imports, "SizedBox isn't a class", etc.) that are hard to trace back to the original cause.

**How to apply:**
- For phone validation regex: use `digits.length != 11 || !digits.startsWith('03')` instead of `RegExp(r'^03\d{9}$')`.
- For any regex with `$` anchors: store in a variable defined on a separate line without `$` in the Edit new_string, or write the file via Node/ShellExec instead.
- General rule: write files with `$` content using `node -e "fs.writeFileSync(...)"` in ShellExec rather than the Edit tool.
- When reconstructing corrupted files: use Node scripts that write complete file sections — avoid the Edit tool for large multi-line replacements containing special characters.
