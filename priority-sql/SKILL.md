---
name: priority-sql
description: >
  Write, review, and debug Priority ERP procedural SQL — unsupported syntax
  (ISNULL, ||, subquery in SET, UPDATE...FROM), cursor loops, temp tables
  (STACK/STACK4/GENERALLOAD), EXECUTE INTERFACE, control flow
  (GOTO/GOSUB/LABEL/LOOP), message commands (ERRMSG/WRNMSG/GENMSG),
  return values (:RETVAL), variable scoping (:$., :$$., :$1., :GLOBAL.),
  and code style. Use when writing or fixing Priority SQL trigger or
  procedure code, designing cursor patterns, or asking why Priority SQL is
  failing. Context cues: ERRMSG, GOSUB, LINK/UNLINK, SQL.TMPFILE, :$.FIELD,
  STACK table names. For complex multi-level GENERALLOAD or pre-computation
  INSERT patterns, see the `priority-sql-advanced` skill. For procedure step
  types and structure, see the `priority-sql-procedures` skill.
---

# Priority ERP Development

Priority uses a proprietary procedural SQL dialect. It resembles T-SQL
superficially but differs significantly — code that looks "standard" may
silently fail or produce wrong results if standard SQL assumptions carry over.

**The grain of the language: pre-compute, then act. Flow via labels, not
nesting. Defer form-specific logic to the caller.** Missing features (no
COALESCE, no subquery in SET, no `UPDATE...FROM`) are compensated by
pre-computing into a variable, then acting on it. Every non-trivial expression
resolves to a `SELECT ... FROM DUMMY` assignment; every per-row operation
becomes a cursor loop; every shared logic becomes a buffer with `#INCLUDE`.
Fighting that grain usually produces code that fails silently or is hard to
debug.

---

## Hard rules — never violate these

These apply to all Priority SQL. Never emit code that breaks them, and never
wait to load a reference file to check.

| Never | Instead |
|-------|---------|
| `DECLARE :var TYPE(width)` for a plain variable | Nothing — Priority variables need no declaration at all. Just assign: `:VAR = value;`. (`DECLARE` exists only for `DECLARE CURSOR`, an unrelated statement) |
| `ISNULL` / `COALESCE` | Initialize the variable to its default *before* the SELECT; a no-row `SELECT INTO` leaves it unchanged |
| `\|\|` for concatenation | `STRCAT(a, b, c, …)` |
| Subquery inside `UPDATE … SET` | `SELECT … INTO :var` first, then `UPDATE … SET COL = :var` |
| `UPDATE … FROM` (multi-table) | Not supported at all — pre-compute a scalar, or use a cursor loop for per-row values |
| Correlated subquery in the SELECT list of `INSERT … SELECT` | Cursor loop with a separate `SELECT INTO` per row |
| Inline conditional assignment (`:v = X WHERE …`) | Set the default unconditionally, then `SELECT X INTO :v FROM DUMMY WHERE <cond>` |
| Blank lines between statements | Priority rejects them on save — never insert them |

**There is no NULL in Priority.** Every column holds a value; "empty" is a
type-specific sentinel, which is why `ISNULL`/`COALESCE` have nothing to
operate on and why the initialize-then-SELECT idiom is complete rather than a
partial workaround.

| Type | Empty value |
|------|-------------|
| Single character | `'\0'` |
| String | `''` |
| Integer | `0` |
| Real | `0.0` |

For a cursor loop, see the `priority-sql-cursor` skill. For form triggers,
CHOOSE-FIELD, or EFORM, see the `priority-sql-forms` skill. For creating or
modifying a table, see the `priority-sql-dbi` skill. For calling an external
web service, see the `priority-sql-integrations` skill (WSCLIENT) — direction
matters: that's Priority calling *out*, unrelated to the `priority-rest-api`
skill's traffic *into* Priority. For scalar/system functions and variables,
see the `priority-sql-ref` skill.

---

## Reference files

Load the relevant file with the Read tool when the request needs that detail —
don't load them speculatively. These files and their names are internal
navigation aids for you, not something to mention to the user — answer with
the content itself, never by citing a reference file's path or name.

| File | Load when the request involves… |
|------|----------------------------------|
| `references/sql-syntax.md` | Ternary expressions, `SELECT … FROM DUMMY`, `LIKE` patterns, joins, supported operators, date handling |
| `references/sql-scoping.md` | `:$.`, `:$$.`, `:$1.`, `:GLOBAL.`, form-field variables, which scope a trigger sees |
| `references/sql-control-flow.md` | `GOTO`, `GOSUB`, `LABEL`, `LOOP`, `ERRMSG`, `WRNMSG`, `GENMSG`, `:RETVAL`, statement failure |
| `references/sql-temp-tables.md` | `STACK`, `STACK4`, `GENERALLOAD`, `LINK`/`UNLINK`, `SQL.TMPFILE`, `EXECUTE INTERFACE`, finding which interface to use |
| `references/sql-style.md` | Formatting, naming, commenting conventions, reviewing existing code for style |
