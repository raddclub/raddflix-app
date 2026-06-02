# RaddFlix Agent Memory Index
> Last Updated: 2026-06-02

- [DB Migration Rules](raddflix-db-rules.md) — oldV param, sqflite pin 3.1.0+1, Android 8 compat, current DB v16
- [Full Audit Bugs](raddflix-audit-bugs.md) — BUG-A01..A34 from 2026-05-30 audit; all code-level bugs fixed
- [GitHub Commit Pattern](raddflix-db-rules.md) — blob->tree->commit->PATCH ref; use Node.js https not curl for large base64
- [Flask strict_slashes rule](raddflix-db-rules.md) — all empty-string blueprint routes need strict_slashes=False
- [SSH Key Reformat](raddflix-db-rules.md) — use node -e to reformat ORACLE_SSH_KEY (spaces to newlines)
- [JazzDrive share_url](raddflix-db-rules.md) — share_urls are PUBLIC links, no server JazzDrive session needed to access them
- [XOR encoding both-sides rule](raddflix-db-rules.md) — never change XOR on one side only; encode_response accepts status= kwarg
