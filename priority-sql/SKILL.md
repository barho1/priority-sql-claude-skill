---
name: priority-sql
description: >
  Priority ERP development — procedural SQL (SQLI), form triggers, procedures,
  DBI schema, and outbound integrations. Covers unsupported SQL syntax
  (ISNULL, ||, subquery in SET, UPDATE...FROM), cursor loops
  (DECLARE/OPEN/FETCH/LOOP/CLOSE, skip-iteration, prev-row tracking), temp
  tables (STACK/STACK4/GENERALLOAD), EXECUTE INTERFACE and multi-level
  document loading, control flow (GOTO/GOSUB/LABEL), message commands
  (ERRMSG/WRNMSG/GENMSG/ENTMESSAGE), return values (:RETVAL), variable
  scoping (:$., :$$., :$1., :GLOBAL.), code style; form triggers of every
  type (CHECK-FIELD, POST-FIELD, CHOOSE-FIELD, SEARCH-FIELD,
  PRE/POST-INSERT, PRE/POST-UPDATE, PRE/POST-DELETE, PRE/POST-FORM), trigger
  execution order, CHOOSE-FIELD picklists, #INCLUDE and buffers, EFORM form
  creation and metadata; procedure step types (B/C/R/F/P/I/L), parameter
  types and processed reports; DBI DDL (CREATE TABLE, FOR TABLE INSERT,
  column types, UNIQUE/NONUNIQUE indexes, expansion tables); scalar and
  system functions (STRCAT, ITOA, ATOI, SUBSTR, STRPIECE, date functions,
  SQL.TMPFILE, SQL.USER, SQL.DATE, SQL.GUID) and system variables
  (:SCRLINE, :PAR1-3, :FORM_INTERFACE, :PREFORMQUERY); and WSCLIENT for
  calling external web services out of Priority. Use for any Priority ERP
  development task — writing or debugging SQL, designing triggers or
  procedures, creating tables or forms, or looking up a function or
  variable. Context cues: ERRMSG, GOSUB, LINK/UNLINK, SQL.TMPFILE,
  :$.FIELD, STACK, CURSOR, CHOOSE-FIELD, EFORM, CREATE TABLE, WSCLIENT.
  For the REST/OData API *into* Priority, see the `priority-rest-api` skill.
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

**Direction matters for integrations.** Traffic *out* of Priority — calling
someone else's web service — is `WSCLIENT`, covered here. Traffic *into*
Priority over HTTP is the REST/OData API, a separate skill
(`priority-rest-api`). They are unrelated mechanisms.

---

## Reference files

Load the relevant file with the Read tool when the request needs that detail —
don't load them speculatively. These files and their names are internal
navigation aids for you, not something to mention to the user — answer with
the content itself, never by citing a reference file's path or name.

Rows compose: a question that spans two areas needs both files. "Charge a card
when an order is saved" is a trigger question *and* an outbound-HTTP question;
"load documents from a staging table" is a temp-table question *and* a cursor
question. Load what the question actually spans, not just the first row that
matches.

### Procedural SQL (SQLI)

| File | Load when the request involves… |
|------|----------------------------------|
| `references/sql-syntax.md` | Ternary expressions, `SELECT … FROM DUMMY`, `LIKE` patterns, joins, supported operators, date handling |
| `references/sql-scoping.md` | `:$.`, `:$$.`, `:$1.`, `:GLOBAL.`, form-field variables, which scope a trigger sees |
| `references/sql-cursor.md` | `DECLARE CURSOR`, `OPEN`, `FETCH`, `LOOP`, `CLOSE`, skipping an iteration, tracking previous-row values, group boundaries |
| `references/sql-control-flow.md` | `GOTO`, `GOSUB`, `LABEL`, `LOOP`, `ERRMSG`, `WRNMSG`, `GENMSG`, `:RETVAL`, statement failure |
| `references/sql-temp-tables.md` | `STACK`, `STACK4`, `GENERALLOAD`, `LINK`/`UNLINK`, `SQL.TMPFILE`, `EXECUTE INTERFACE` |
| `references/sql-advanced.md` | Multi-level document loading (header + lines, `RECORDTYPE`), pre-computation before a complex `INSERT`, the abstract SUB pattern |
| `references/sql-style.md` | Formatting, naming, commenting conventions, reviewing existing code for style |

### Forms

| File | Load when the request involves… |
|------|----------------------------------|
| `references/forms-triggers.md` | Any trigger type (`CHECK-FIELD`, `POST-FIELD`, `PRE-INSERT`, `POST-UPDATE`, `PRE-FORM`…), trigger execution order, trigger naming, and the `CHOOSE-FIELD` variants (`MCHOOSE-FIELD`, `AND STOP`, `NO SORT`, union) |
| `references/forms-choose-field.md` | Creating a picklist end to end — the values table, the FK column, the form, and the buffer trigger for expansion tables |
| `references/forms-metadata.md` | `EFORM` queries, `FCLMN_SUBFORM`, `FLINK_SUBFORM`, which columns are hidden/read-only/calculated, exploring form structure |
| `references/forms-eform-create.md` | Creating a form programmatically by loading into `EFORM` |
| `references/forms-include-buffers.md` | `#INCLUDE`, buffer triggers, sharing logic between triggers |

### Schema, procedures, functions

| File | Load when the request involves… |
|------|----------------------------------|
| `references/dbi.md` | `CREATE TABLE`, `FOR TABLE INSERT`, column types/widths, `UNIQUE`/`NONUNIQUE` indexes, expansion tables, adding a column |
| `references/procedures.md` | Procedure step types (B/C/R/F/P/I/L), parameter types, `INPUT` vs `INPUTF`, processed reports, `FILE` parameters |
| `references/ref-scalar-functions.md` | Looking up a scalar function — `STRCAT`, `ITOA`, `ATOI`, `SUBSTR`, `STRPIECE`, `ROUND`, date functions, date arithmetic |
| `references/ref-system-functions.md` | `SQL.USER`, `SQL.DATE`, `SQL.TMPFILE`, `SQL.GUID`, `SQL.ORACLE`, system variables (`:SCRLINE`, `:PAR1-3`, `:FORM_INTERFACE`) |
| `references/ref-entmessage.md` | `ENTMESSAGE`, message numbering, parameter expansion in messages |
| `references/ref-sdk-links.md` | Pointing at official SDK documentation pages |

### Integrations

| File | Load when the request involves… |
|------|----------------------------------|
| `references/wsclient.md` | Calling an external service *from* Priority SQL — `WSCLIENT`, writing the request body to a file (`ASCII` / `ASCII ADDTO`), `-head2`, `-authname`, OAuth2, `ERRMSGS` error checking, and parsing the response with `XMLPARSE` (XML or JSON) |
