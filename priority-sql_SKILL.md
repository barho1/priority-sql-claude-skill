---
name: priority-sql
description: >
  Write, review, and debug Priority ERP procedural SQL — including form triggers,
  business rules, procedures, and EXECUTE INTERFACE patterns. Use this skill
  whenever the user asks to write or fix Priority SQL code, implement a form trigger
  or business rule in Priority, work with GENERALLOAD / EXECUTE INTERFACE, design
  a cursor loop or temp-table pattern, or asks why their Priority SQL is failing.
  Also use when the user pastes Priority code and asks for a review, refactor, or
  extension — even if they don't say "Priority" explicitly, context cues like
  ERRMSG, GOSUB, LINK/UNLINK, SQL.TMPFILE, :$.FIELD, or STACK table names
  are strong signals to apply this skill.
---

# Priority ERP SQL

Priority uses a proprietary procedural SQL dialect. It resembles T-SQL superficially but has significant differences. Always apply these rules — Priority code that looks "standard" may silently fail or produce wrong results if standard SQL assumptions are carried over.

## Language philosophy

Priority's SQL is intentionally imperative. Where standard SQL lets you describe *what* you want in a single set-based statement, Priority requires you to describe *how* — one scalar at a time. Most patterns in this skill exist because of that constraint: missing language features (no COALESCE, no subquery in SET, no UPDATE...FROM) are compensated by pre-computing into a variable, then acting on it. Once you internalize this, the code becomes predictable: every non-trivial expression resolves to a `SELECT ... FROM DUMMY` assignment; every per-row operation becomes a cursor loop; every shared logic becomes a buffer with `#INCLUDE`.

The grain of the language is: **pre-compute, then act. Flow via labels, not nesting. Defer form-specific logic to the caller.**

Working with that grain produces verbose but readable code — every step is explicit and traceable. Fighting it (trying to compress logic into a single statement) usually produces something that fails silently or is difficult to debug.

---

## 1. Unsupported syntax (never use these)

### `ISNULL` / `COALESCE`
Not valid. Do not use.

**Pattern to replace it:**
Initialize the variable to its default *before* the SELECT. If the SELECT finds no row, the variable is left unchanged.
```sql
:MY_VAR = 0;   /* default */
SELECT SOMEVALUE INTO :MY_VAR FROM SOMETABLE WHERE KEY = :KEY;
/* :MY_VAR is now either the found value or still 0 */
```
This is a guaranteed behavior in Priority: a SELECT INTO that finds no rows does not alter the target variable.

---

### `||` string concatenation
Not valid. Use `STRCAT(a, b, c, ...)` instead.
```sql
/* WRONG */
:RESULT = :PREFIX || :SUFFIX;

/* CORRECT */
:RESULT = STRCAT(:PREFIX, :SUFFIX);
```
Ref: [SDK Scalar Expressions – String manipulation](https://prioritysoftware.github.io/sdk/Scalar-Expressions#string-manipulation)

---

### Subquery in `UPDATE ... SET`
Not valid. Priority rejects subqueries inside SET.
```sql
/* WRONG */
UPDATE MYTABLE SET COST = (SELECT SUM(X) FROM OTHERTABLE WHERE ...);

/* CORRECT — compute first, then update */
:COMPUTED_COST = 0.0;
SELECT SUM(X) INTO :COMPUTED_COST FROM OTHERTABLE WHERE ...;
UPDATE MYTABLE SET COST = :COMPUTED_COST WHERE ...;
```
For multi-row updates where the value differs per row, use a cursor loop (see §6).

---

### `UPDATE ... FROM` join syntax
Not valid. Priority does not support multi-table UPDATE. The SET value must always be a pre-computed scalar variable.

---

### Correlated subquery in `SELECT` list of `INSERT ... SELECT`
Not valid.
```sql
/* WRONG */
INSERT INTO STACK4 T (KEY, INTDATA)
SELECT A.SONACT,
       (SELECT MAX(B.SONACT) FROM PARTARC B WHERE B.SON = A.SON AND ...)
FROM PARTARC A WHERE ...;
```
**Pattern to replace it:** Use a cursor loop — iterate over the outer set and do a separate SELECT INTO per row.

---

### Conditional variable assignment — `:var = <value> WHERE ...`

Not valid. Priority does not support inline conditional assignment.

```sql
/* WRONG */
:arno_use_mrb = 1 WHERE :$.ARNY_MRBDECNAME <> '' ;

/* CORRECT */
:arno_use_mrb = 0 ;                                            /* default */
SELECT 1 INTO :arno_use_mrb FROM DUMMY WHERE :$.ARNY_MRBDECNAME <> '' ;
```

Always set the default unconditionally first, then override it with `SELECT <value> INTO :var FROM DUMMY WHERE <condition>`. If the condition is false, the SELECT finds no row and the variable retains its default — consistent with Priority's no-row SELECT behavior (see `ISNULL / COALESCE` above).

---

## 2. Supported syntax worth knowing

### Ternary expression
```sql
(condition ? value_if_true : value_if_false)
```
This is Priority's equivalent of `CASE WHEN ... THEN ... ELSE ... END` or `IIF(...)`.
- Conditions use `=`, `<>`, `AND`, `OR` keywords.
- Can be nested: `(A = 'Y' ? 'X' : (B = 'Y' ? 'Y' : 'Z'))`
- Works in SELECT lists, WHERE clauses, and variable assignments.
- Does **not** use `||` or `&&` for boolean operators — use `AND` / `OR`.

### `STRCAT(arg1, arg2, ...)` — string concatenation
```sql
:DOCNO = STRCAT(:PREFIX, ITOA(:NUM, :WIDTH));
```

### `ITOA(int)` / `ITOA(int, width)` — integer to string
```sql
KEY1 = ITOA(:PART_ID)           /* no padding */
KEY1 = ITOA(:NUM, 6)            /* zero-padded to width 6 */
```
Required when storing an integer value into a string column (e.g. KEY1/KEY2 in GENERALLOAD).

### `DTOA(date, format)` — date to string
```sql
:YEAR = DTOA(0 + :DATE, 'YY');
```

### `STRLEN(str)`, `SUBSTR(str, start, len)`, `STRIND(str, sub, start)`
Standard string functions available in Priority.

### The `DUMMY` table

`DUMMY` is a special single-record, single-column table used whenever a
`SELECT` is needed to evaluate an expression or assign a variable
without reading from a real table. Unlike querying even a small real
table, `SELECT ... FROM DUMMY` does not access the table at all — the
engine short-circuits it entirely, making it the fastest possible source
for expression evaluation.

```sql
/* Assign a computed value to a variable */
SELECT SQL.TMPFILE INTO :TMP FROM DUMMY;
SELECT STRCAT(:PREFIX, '_', :SUFFIX) INTO :FULLNAME FROM DUMMY;

/* ENTMESSAGE must always run against DUMMY */
:MSG = ENTMESSAGE('$', 'P', 10);
/* equivalent explicit form: */
SELECT ENTMESSAGE('$', 'P', 10) INTO :MSG FROM DUMMY;
```

Always use `DUMMY` (rather than a real table) when the query result
depends only on variables or scalar functions — it is both semantically
clearer and faster.

Ref: [SQL Variables — The DUMMY Table](https://prioritysoftware.github.io/sdk/SQL-Variables#the-dummy-table)

---

## 3. Variable scoping

Three types of variables — no block-level isolation within a form context:

| Type | Syntax | Scope |
|------|--------|-------|
| Form field | `:$.COLNAME` or `:FORMNAME.COLNAME` | Current form row. Subforms use `:$$.COL`, `:$$$.COL` etc. |
| Local variable | `:varname` | Visible across all triggers in the form and all subforms. Internally namespaced as `:_company.varname`. |
| Global variable | `:GLOBAL.varname` | Spans all companies in multi-company contexts. |

**`:FIELDNAME` (colon-prefix on a form field) in an UPDATE trigger** returns the value *before* the current change. Use this in PRE-UPDATE checks to inspect the old value.
```sql
/* Block editing a row that already had a price, OR a row that now has a price */
ERRMSG 1 WHERE :QPRICE > 0 OR QPRICE > 0;
/*              ^^^^^^^^^^       ^^^^^^^^  */
/*              old value        new value */
```

**`:$1.FIELDNAME`** — the pre-change value of a form field, used in
buffer triggers and POST-UPDATE triggers to compare the new value
(`:$.FIELDNAME`) against the previous one. This is the standard pattern
for detecting whether a specific field actually changed:

```sql
/* Skip if the FK column wasn't modified */
GOTO 9999 WHERE :$.PRIV_FNCCLASS = :$1.PRIV_FNCCLASS;
```

When multiple fields are tracked by the same buffer trigger, chain the
conditions with `AND` — only skip if *all* tracked fields are unchanged.

---

## 4. Control flow — GOTO, GOSUB, LOOP, LABEL

### LABEL / GOTO / LOOP
All three accept an optional `WHERE` clause — execution only jumps if the condition is true.
```sql
GOTO 100 WHERE :RETVAL < 1;     /* jump to LABEL 100 if condition is met */
LOOP 200 WHERE :MORE = 'Y';     /* jump back to LABEL 200 if condition is met */
```

### GOSUB / SUB / RETURN
`GOSUB N` calls the subroutine declared with `SUB N;`. Every `SUB` block **must** contain a `RETURN` statement.
```sql
GOSUB 500 WHERE :PRICE > 100;   /* call SUB 500 only if condition is met */

SUB 500;
/* ... subroutine body ... */
RETURN;
```

### GOSUB N vs `:GOSUB = N` (and GOTO N vs `:GOTO = N`)
Both forms are equivalent — `GOSUB N` is syntactic sugar for `:GOSUB = N`, and `GOTO N` for `:GOTO = N`.

Prefer the keyword form (`GOSUB N`, `GOTO N`) — it reads as a flow instruction, not a variable assignment.

Use the variable form (`:GOTO = N`) when a single decision point needs to branch to many possible labels and writing repeated `GOTO N WHERE ...` lines would be noisy:
```sql
/* Variable form — cleaner for multi-way dispatch */
:GOTO = (  :TYPE = 'A' ? 10
         : :TYPE = 'B' ? 20
         : :TYPE = 'C' ? 30
         : 99);

/* vs. the verbose keyword alternative */
GOTO 10 WHERE :TYPE = 'A';
GOTO 20 WHERE :TYPE = 'B';
GOTO 30 WHERE :TYPE = 'C';
GOTO 99;
```

---

## 5. Message commands — ERRMSG, GENMSG, WRNMSG

| Command | Message source | Behavior |
|---------|---------------|----------|
| `ERRMSG N` | Form or procedure message table (scoped to the form/procedure) | Displays error, aborts the current operation |
| `GENMSG N` | System-wide `GENMSG` table (shared across all forms/procedures) | Displays error, aborts the current operation |
| `WRNMSG N` | Same as ERRMSG source | Displays warning with OK / Cancel buttons; execution continues if user confirms |

All three accept a `WHERE` clause:
```sql
ERRMSG 1 WHERE :RETVAL < 1;
WRNMSG 5 WHERE :QTY > :STOCK;
```

Use `ERRMSG` for form/procedure-specific messages. Use `GENMSG` for reusable system-wide messages (e.g. in shared interfaces). Use `WRNMSG` when the user should be able to override the warning and proceed.

---

## 6. Cursor loop pattern

Use when you need to iterate over a result set and perform per-row logic (e.g. UPDATE with a computed value per row).

### Canonical template

```sql
/* Labels are guidelines and should be prefixed */
DECLARE Cursor_Name CURSOR FOR
SELECT DAYNUM, DAYNAME FROM DAYS;
OPEN Cursor_Name;
GOTO 1999 WHERE :RETVAL <= 0; /* Empty cursor */
/* Initialize cursor variables here */
LABEL 1000; /* Cursor loop */
FETCH Cursor_Name INTO :DAY, :DAYNAME;
GOTO 1998 WHERE :RETVAL <= 0; /* No more results */
/* Cursor logic goes here */
LOOP 1000; /* Loop cursor */
LABEL 1998; /* Close cursor */
CLOSE Cursor_Name;
LABEL 1999; /* Handle empty cursor */
```

### Rules — never violate these

**Never error on an empty cursor — always exit gracefully.**
Use `GOTO` to skip past the cursor body. An error message may be appropriate *after* cleanup if the business logic requires it, but never as a direct response to an empty cursor.

**Never close an unopened cursor.**
This is why the template has two distinct fallback labels:
- `LABEL 1998` — cursor was opened, but `FETCH` found no more rows. Close here.
- `LABEL 1999` — cursor never opened (`OPEN` returned `RETVAL <= 0`). Skip directly here; do NOT close.

**Each cursor has exactly one `LOOP` and one `CLOSE`.**
Never `LOOP` from the middle of the cursor body. If an iteration has nothing left to do, jump to a skip label placed just above the `LOOP`:
```sql
LABEL 1000;
FETCH Cursor_Name INTO :KEY, :VAL;
GOTO 1998 WHERE :RETVAL <= 0;

GOTO 1997 WHERE :VAL = 0; /* skip this iteration */

/* main logic */
UPDATE SOMETABLE SET X = :VAL WHERE KEY = :KEY;

LABEL 1997; /* skip-to point — above LOOP */
LOOP 1000;
LABEL 1998;
CLOSE Cursor_Name;
LABEL 1999;
```

This rule applies to nested cursors too — each cursor has exactly one `LOOP` and one `CLOSE`, regardless of how many exit paths exist inside the body.

### Tracking previous-iteration values

A cursor overwrites its variables on every `FETCH`. If you need to reference a value from the previous iteration (typically key fields to detect a group boundary or compare against the prior record), save them into `:prev_` prefixed variables at the **end** of the iteration body, just before `LOOP`.

Rules:
- **Initialize `:prev_` variables explicitly** after `OPEN` succeeds and before `LABEL 1000`. Never assume they start at zero or empty.
- **Handle the null/uninitialized case** at the top of the cursor body — on the first iteration the `:prev_` variable will hold its initialized default, which must be a value that cannot appear as a real key (e.g. `0` for integers, `''` or `'\0'` for strings).
- **Group initializations by type** on a single line for readability (see variable initialization conventions below).

```sql
DECLARE Cur CURSOR FOR
SELECT PARTNAME, QTY FROM ORDERITEMS WHERE ...;
OPEN Cur;
GOTO 1999 WHERE :RETVAL <= 0;

/* Initialize cursor variables and prev sentinels */
:PARTNAME      = '';
:QTY           = 0;
:prev_PARTNAME = '';
:QTY_TOTAL     = 0;

LABEL 1000;
FETCH Cur INTO :PARTNAME, :QTY;
GOTO 1998 WHERE :RETVAL <= 0;

/* First iteration or new group */
GOTO 1005 WHERE :prev_PARTNAME = '';
GOTO 1005 WHERE :prev_PARTNAME <> :PARTNAME;

/* Same group — accumulate */
:QTY_TOTAL = :QTY_TOTAL + :QTY;
GOTO 1997;

LABEL 1005; /* Group boundary */
/* ... process completed group for :prev_PARTNAME ... */
:QTY_TOTAL = :QTY; /* Reset for new group */

LABEL 1997;
:prev_PARTNAME = :PARTNAME; /* Save for next iteration */
LOOP 1000;

LABEL 1998;
/* Process final group */
/* ... */
CLOSE Cur;
LABEL 1999;
```

### Variable initialization conventions

Group variables of the same type onto a single assignment line for readability:

```sql
/* Strings */
:PARTNAME = :CUSTNAME = :WARHSNAME = '';

/* Integers */
:PART = :CUST = :WARHS = 0;

/* Real / decimal */
:PRICE = 0.0;

/* Dates — initialize as dd/mm/yy, not as 0 */
:CURDATE = :OPENDATE = 01/01/88;

/* Single-character flags */
:INVFLAG = :TYPE = '\0';
```

**Date fields** are internally stored as integers (minutes since 01/01/88), so `0` is technically valid. However, always initialize them as `dd/mm/yy` literals — the engine then formats them as dates in messages and displays, rather than as a raw minute count, which makes debugging far easier.

**Single-character fields** (`'\0'`) are distinct from empty strings (`''`). Use `'\0'` for CHAR(1) columns and flag fields.

### Label numbering convention for nested cursors

Always use distinct label ranges per nesting level. Reusing the same numbers across outer and inner cursors may work but makes code hard to follow and risks subtle bugs.

| Level | Range | Typical labels |
|-------|-------|----------------|
| Outer cursor | 1xxx | 1000 loop, 1997 skip, 1998 close, 1999 empty |
| Inner cursor | 2xxx | 2000 loop, 2997 skip, 2998 close, 2999 empty |
| Inner-inner | 3xxx | 3000 loop, 3997 skip, 3998 close, 3999 empty |

Use intermediate numbers (1002, 1005, etc.) freely for branching within a cursor body. The nesting depth is immediately readable from the label number alone.

---

## 7. Return values — `:RETVAL`

Every SQL statement sets `:RETVAL` immediately after execution. The
skill uses `:RETVAL` throughout (cursor OPEN, LINK, INSERT checks) —
this section documents all values in one place.

| Statement | Return value | Failure / edge cases |
|-----------|-------------|----------------------|
| `DECLARE` | 1 (always) | Never fails |
| `OPEN` | Number of records; 0 on failure | Too many open cursors (>100); no selected records |
| `CLOSE` | 1 on success; 0 on failure | Cursor not open |
| `FETCH` | 1 if fetched; 0 at end of cursor | Cursor not open; no more records |
| `SELECT` | Number of selected records; 0 on failure | No record met WHERE condition |
| `SELECT … INTO` | 1 on success; 0 on failure | No record met WHERE condition |
| `INSERT … SELECT` | Number of inserted records; –1 if no record meets WHERE | Selected records existed but none inserted (unique key violation or insufficient privileges) |
| `INSERT … VALUES` | 1 on success; 0 on failure | Failed to insert |
| `UPDATE … WHERE CURRENT OF` | 1 on success; 0 on failure | Cursor not open; no more records; record not updated |
| `UPDATE` | Number of updated records; 0 if none updated; –1 if no record meets WHERE | Selected records existed but none updated (unique key violation or insufficient privileges) |
| `DELETE … WHERE CURRENT OF` | 1 on success; 0 on failure | Cursor not open; no more records |
| `DELETE` | Number of deleted records; –1 if no record meets WHERE | — |
| `LINK` | 1 on success; 0 on failure | File already linked; insufficient permissions |

**Key patterns derived from this table:**

`RETVAL = 0` after `SELECT INTO` means no row was found — the target
variable is left at its pre-SELECT value (see §1 ISNULL pattern).

For `INSERT … SELECT` and `UPDATE`, the return value has three distinct
meanings that are easy to confuse:

| Value | Meaning |
|-------|---------|
| `> 0` | N rows were successfully modified |
| `0` | WHERE matched rows, but none were written (unique key violation or insufficient privileges) — a real error |
| `–1` | WHERE matched no rows at all — often acceptable, not necessarily an error |

```sql
INSERT INTO SOMETABLE (KEY, VAL)
SELECT :KEY, :VAL FROM DUMMY;
ERRMSG 1 WHERE :RETVAL = 0;  /* rows matched but all rejected — error */
/* RETVAL = -1 means no row matched WHERE — usually fine */
/* RETVAL > 0 means N rows inserted — success */
```

Ref: [Return Values and Statement Failure](https://prioritysoftware.github.io/sdk/RETVAL-Values#table-of-return-values-and-statement-failure)

---

## 8. Linked temp tables (STACK, STACK4, GENERALLOAD, etc.)

Always pair every `LINK` with an `UNLINK`. Use `SQL.TMPFILE` as the file handle.

```sql
SELECT SQL.TMPFILE INTO :MY_TMP FROM DUMMY;
LINK STACK4 MYDATA TO :MY_TMP;
ERRMSG 1 WHERE :RETVAL < 1;

/* ... use MYDATA ... */

UNLINK AND REMOVE STACK4 MYDATA;
```

`UNLINK AND REMOVE` frees both the link and the temp file. Use plain `UNLINK` if you want to keep the file for re-linking later.

---

## 9. EXECUTE INTERFACE — standard pattern

```sql
/* 1. Create a linked GENERALLOAD */
SELECT SQL.TMPFILE INTO :GEN_TMP FROM DUMMY;
LINK GENERALLOAD TO :GEN_TMP;
GENMSG 1 WHERE :RETVAL <= 0;
/* GENMSG (not ERRMSG) because this failure is infrastructure-level,
   not specific to this form's business logic */

/* 2. Populate GENERALLOAD */
INSERT INTO GENERALLOAD (LINE, RECORDTYPE, TEXT1, TEXT2, ...)
SELECT 1, '10', :VAL1, :VAL2, ...
FROM DUMMY;
GENMSG 1 WHERE :RETVAL <= 0;

/* 3. Execute */
EXECUTE INTERFACE 'INTERFACE_NAME', SQL.TMPFILE, '-L', :GEN_TMP;

/* 4. Check for errors (standard pattern) */
ERRMSG 1 WHERE EXISTS (
    SELECT 1 FROM ERRMSGS
    WHERE USER = SQL.USER AND TYPE = 'i'
);

/* 5. Clean up */
UNLINK GENERALLOAD;
```

### Error handling variants

**Standard** — check `ERRMSGS` after execution:
```sql
ERRMSG 1 WHERE EXISTS (
    SELECT 1 FROM ERRMSGS WHERE USER = SQL.USER AND TYPE = 'i'
);
```

**Advanced** — structured per-line error capture via `STACK_ERR`:
Only use when you need to programmatically read, store, or display individual error messages per line. Add the `-stackerr` switch and link `STACK_ERR` to a tmpfile before executing.
Ref: [SDK Execute-FormLoads – Errors](https://prioritysoftware.github.io/sdk/Execute-FormLoads#dealing-with-errors-and-reloading) | [SDK STACKERR](https://prioritysoftware.github.io/sdk/STACKERR)

**Anti-pattern** — do NOT use `LOADED <> 'Y'` as the primary error check:
```sql
/* WRONG — not the standard pattern */
ERRMSG 1 WHERE EXISTS (SELECT 1 FROM GENERALLOAD WHERE LOADED <> 'Y');
```

---

## 10. GENERALLOAD row accumulation — header + subform lines

When loading a document with subform lines via GENERALLOAD, both the
header and line rows go into the same temp table in a single pass,
distinguished by RECORDTYPE and LINE order. This is non-obvious: the
table looks flat but encodes a hierarchy through insertion order.

RECORDTYPE is 3 characters. The traditional convention is numeric
strings — `'1'` for the header record, `'2'` for subform lines, and so
on for deeper levels. Alphanumeric codes (`'ORD'`, `'ITM'`) are valid
and can hint at meaning, but 3 characters is rarely enough to be
self-documenting — a comment per INSERT is usually more useful than
relying on the value itself.

```sql
SELECT SQL.TMPFILE INTO :GEN_TMP FROM DUMMY;
LINK GENERALLOAD TO :GEN_TMP;
GENMSG 1 WHERE :RETVAL <= 0;

:LINE = 0;

/* Record type '1' — order header */
:LINE = :LINE + 1;
INSERT INTO GENERALLOAD (LINE, RECORDTYPE, TEXT1, TEXT2)
VALUES (:LINE, '1', :ORDNAME, :CUSTNAME);

LABEL 2000;
FETCH Items_Cursor INTO :PARTNAME, :QTY;
GOTO 2998 WHERE :RETVAL <= 0;

/* Record type '2' — order line item */
:LINE = :LINE + 1;
INSERT INTO GENERALLOAD (LINE, RECORDTYPE, TEXT1, REAL1)
VALUES (:LINE, '2', :PARTNAME, :QTY);
LOOP 2000;

LABEL 2998;
EXECUTE INTERFACE 'ORDERS', SQL.TMPFILE, '-L', :GEN_TMP;

ERRMSG 1 WHERE EXISTS (
    SELECT 1 FROM ERRMSGS WHERE USER = SQL.USER AND TYPE = 'i'
);

UNLINK GENERALLOAD;
```

Key rules:
- LINE must be strictly incrementing across all record types — it
  determines processing order, not just row uniqueness.
- The header row must precede its child rows.
- RECORDTYPE values and their column mappings are defined in the
  interface definition, not in the code. The code is opaque without
  the interface open alongside it — comment each INSERT accordingly.

---

## 11. Pre-computation pattern for complex INSERTs

When an `INSERT ... SELECT` requires conditional flags or lookup values that would need correlated subqueries or complex inline logic, pre-compute into STACK tables first, then do a clean JOIN-based INSERT.

```sql
/* Step A: pre-compute which parts are leaves */
LINK STACK LEAFPARTS;
ERRMSG 1 WHERE :RETVAL < 1;
INSERT INTO STACK LEAFPARTS
SELECT DISTINCT SON FROM PARTARC PA, PART P
WHERE PA.PART = :ROOT AND PA.SON = P.PART AND (P.TYPE = 'R' OR P.TURNKEY = 'Y');

/* Step B: pre-compute lookup values via cursor (if correlated logic needed) */
/* ... cursor loop, SELECT INTO per row ... */

/* Step C: clean INSERT joining the pre-computed tables */
INSERT INTO STACK4 RESULT (KEY, INTDATA, CHARDATA)
SELECT PA.SONACT,
       PM.INTDATA,
       (LP.ELEMENT <> 0 ? 'Y' : 'N')
FROM PARTARC PA, STACK4 PARENTMAP PM, STACK LEAFPARTS LP
WHERE PA.PART  = :ROOT
AND   PM.KEY   = PA.SONACT
AND   LP.ELEMENT = PA.SON;

UNLINK AND REMOVE STACK LEAFPARTS;
```

---

## 12. Code style conventions

### Line length — 68 characters
Priority text lines are 68 characters long. Break long lines to stay within this limit. Never break in the middle of a name or a keyword.

```sql
/* WRONG — line too long */
INSERT INTO GENERALLOAD (LINE, RECORDTYPE, TEXT1, TEXT2, TEXT3, TEXT4, TEXT5)

/* CORRECT — break after the opening paren, before a column name */
INSERT INTO GENERALLOAD (LINE, RECORDTYPE,
                         TEXT1, TEXT2, TEXT3,
                         TEXT4, TEXT5)
```

For long WHERE clauses, break before `AND` / `OR`:
```sql
SELECT PROJ INTO :ARNT_PROJ
FROM   PROJLINK, STATUSTYPES
WHERE  PROJLINK.IV        =  :NSCUST
AND    STATUSTYPES.TYPE   =  :STATUSTYPE
AND    PROJLINK.TYPE      =  STATUSTYPES.EXTTYPE
AND    PROJLINK.KLINE     =
       (:STATUSTYPE = 'S' ? -1 : :KLINE);
```

### No leading whitespace

Priority trims leading whitespace when saving trigger code, so
continuation lines must never start with a space or tab.

Use `/**/` at the start of a continuation line in a code block,
or any character at the start of a comment continuation line.

```sql
/* WRONG — leading spaces will be trimmed on save */
GOTO 14922 WHERE :$.ARNO_QREPDECNAME = :$1.ARNO_QREPDECNAME
             AND :$.ARNY_MRBDECNAME = :$1.ARNY_MRBDECNAME ;

/* CORRECT — /**/ anchors the continuation line */
GOTO 14922 WHERE :$.ARNO_QREPDECNAME = :$1.ARNO_QREPDECNAME
/**/ AND :$.ARNY_MRBDECNAME = :$1.ARNY_MRBDECNAME ;
```

### Subroutine organization

Offload repeated logic to `SUB` blocks (or `#INCLUDE` triggers for
cross-form reuse). This keeps the main flow readable and avoids
duplicated code.

Separate the subroutine section from the main body with a divider comment:

```sql
/* main procedure body */
GOSUB 500 WHERE :NEEDS_LOOKUP = 'Y';
...
LABEL 9999;
END;

/*===============================================================*/
/*                        SUBROUTINES                            */
/*===============================================================*/

SUB 500;
/* ... */
RETURN;

SUB 510;
/* ... */
RETURN;
```

#### `#INCLUDE` — sharing triggers across forms

`#INCLUDE` pulls the entire contents of another trigger into the current
one at compile time. Use it when the same logic must run in multiple
forms or columns without being duplicated:

```sql
/* CHECK-FIELD for TYPE in LOGPART — reuse the PART form's trigger */
#INCLUDE PART/TYPE/CHECK-FIELD
```

Syntax:
- `#INCLUDE form_name/trigger_name` — for row/form triggers
- `#INCLUDE form_name/column_name/trigger_name` — for column triggers

The including trigger inherits all SQL statements *and* error/warning
messages from the included trigger. Additional statements can be written
before or after the `#INCLUDE` line. Any changes to the included trigger
automatically affect all including triggers — check the *Use of Trigger*
sub-level before modifying a shared trigger.

**Buffers** are triggers that exist only to be included — they hold
shared logic that no form activates directly. Numbered buffers (`BUF1`
through `BUF19`) are predefined; named buffers follow the same naming
rules as custom triggers. The conventional home for shared buffers is
the `TRANSTRIG` form, a system form that exists purely to hold reusable
trigger code.

`#INCLUDE` can be nested — an included trigger may itself include
another.

**`SUB` vs `#INCLUDE`:** Use `SUB` for reuse *within* a single
trigger (extract a repeated block into a subroutine). Use `#INCLUDE`
for reuse *across* different forms or trigger positions (share logic
between LOGPART and PART, or between multiple PRE-INSERT triggers).

Ref: [Including One Trigger in Another](https://prioritysoftware.github.io/sdk/Include-Triggers)

#### Abstract SUB pattern — deferred calculation via `#INCLUDE`

When shared trigger logic needs a value that is computed differently per
form, and passing a pre-computed variable would be too complex, the
calculation can be deferred to the including form via an **unimplemented
SUB**. The shared trigger calls the SUB; each including form provides its
own implementation after the `#INCLUDE` line.

This is the Priority equivalent of an abstract method in OOP: the buffer
defines the algorithm, and each caller supplies the missing piece.

**Design rules:**
- The shared trigger (`GOSUB N`) calls a SUB that it does **not** implement.
- The buffer is defined in one form (e.g. `ORDERS`) and referenced via `#INCLUDE`.
- Each including trigger appends its own `SUB N; ... RETURN;` block after the `#INCLUDE`.
- The SUB number must not collide with any SUB already defined in the including trigger.

**Example — display count of open documents on form open:**

Buffer trigger `ORDERS/BUF1_PRIV` (the shared core):
```sql
GOSUB 1457;                                    /* get count — implemented by caller */
SELECT ITOA(:OPEN_DOCS) INTO :PAR1 FROM DUMMY;
WRNMSG 1458;
```

`ORDERS/PRE-FORM` (includes buffer, supplies ORDERS-specific count):
```sql
#INCLUDE ORDERS/BUF1_PRIV
SUB 1457;
SELECT COUNT(*) INTO :OPEN_DOCS
FROM   ORDERS
WHERE  CURDATE = SQL.DATE8
AND    CLOSED <> 'C';
RETURN;
```

`DOCUMENTS_T/PRE-FORM` (includes same buffer, supplies its own count):
```sql
#INCLUDE ORDERS/BUF1_PRIV
SUB 1457;
SELECT COUNT(*) INTO :OPEN_DOCS
FROM   DOCUMENTS
WHERE  TYPE    = 'T'
AND    CURDATE = SQL.DATE8
AND    FINAL   <> 'Y';
RETURN;
```

**When to use this pattern:**
- The shared logic is non-trivial and must not be duplicated.
- The per-form input requires a query or multi-step calculation — not a
  simple scalar that could be passed as a variable before the `#INCLUDE`.
- If the input *can* be pre-computed trivially, set a variable before the
  `#INCLUDE` instead; that is simpler and does not require an open SUB.

### Indentation
Priority text forms reject lines that begin with whitespace (spaces or tabs). To indent continuation lines, start with a blank comment `/**/` followed by spaces:

```sql
INSERT INTO GENERALLOAD (LINE, RECORDTYPE,
/**/                     TEXT1, TEXT2, TEXT3);

SELECT PROJ INTO :ARNT_PROJ
FROM   PROJLINK, STATUSTYPES
WHERE  PROJLINK.IV      = :NSCUST
AND    PROJLINK.KLINE   =
/**/   (:STATUSTYPE = 'S' ? -1 : :KLINE);
```

This applies anywhere a logical continuation line would otherwise start with whitespace.

### General
- Align `INTO`, `FROM`, `WHERE`, `AND` vertically where it aids readability.
- Use `/* ... */` comments, not `--` (Priority line comments are less portable).
- Name SUB numbers to suggest their role — e.g. 500-series for lookups, 900-series for input steps — so the call site is self-documenting.
- **Use `ENTMESSAGE` instead of string literals** for any user-visible text and for
  non-trivial strings embedded in output (section headers, labels, SQL templates
  with variable holes). This keeps Hebrew and other non-ASCII text out of trigger
  code, makes strings translatable, and eliminates duplicate literals via DRY.
  Only single-character flags (`'Y'`, `'\0'`), pure SQL punctuation, and strings
  built entirely from variables belong inline. See §15 for the full reference.

---

## 13. Procedures

A procedure is a sequence of named steps executed in order. The most
common pattern in custom development is a **processed report**: user
input → data manipulation (SQLI) → report output.

### Step types

| Type | Code | Description |
|------|------|-------------|
| Basic command | B | `INPUT`/`INPUTF`, `END`, `GOTO`, `MESSAGE`, etc. |
| SQLI program | C | Executes a block of Priority SQL |
| Report | R | Runs a report step and displays output |
| Form | F | Opens a form for user interaction |
| Sub-procedure | P | Calls another procedure |
| Form load interface | I | Runs a form load |
| Table load | L | Imports external data |

**Priority Web constraint:** Never use `EXECUTE WINFORM` or
`EXECUTE WINACTIV` inside an SQLI step to open forms or run procedures
that display UI — they run on the server, not the client. Add a
separate step of type F or P instead.

### Parameter types

| Type | Usage |
|------|-------|
| `CHAR`, `INT`, `REAL`, `DATE` | Scalar value passed between steps |
| `ASCII` | Text file (e.g. error message file for `PRINTERR`) |
| `FILE` | Linked table of records — bidirectional between steps |
| `LINE` | Single record from the database |
| `NFILE` | Like FILE, but link table stays empty if user enters `*` |

**Parameter name limit:** 3 characters maximum (e.g. `PRF`, `OUT`).

### INPUT vs INPUTF

`INPUT` — shows the parameter input screen only when run directly by
the user. Suppressed when the procedure is called as an Action from a
form.

`INPUTF` — shows the input screen in both contexts. Prefer `INPUTF`
for developer tools and any procedure where input is always required.

### Processed report pattern

The standard three-step structure for a procedure that generates a
report from computed data:

```
Step 10  INPUTF     B   — collect user inputs
Step 20  PROC_NAME  C   — validate, compute, populate linked table
Step 30  RPT_NAME   R   — render the report
```

The procedure must have `R` in the *Rep/Wizard/Dashboard* column so
it behaves like a report from the user's perspective (print/export
options, standard report viewer).

### Passing a linked table between SQLI and report steps

Declare a `FILE` parameter (e.g. `OUT`, table = `STACK4`) on **both**
the SQLI step and the report step, using the same parameter name. The
system links the table to a temp file before the SQLI step runs; the
SQLI step writes into it directly; the report step reads from the same
linked file automatically.

```
Step 20 parameters:
  OUT   FILE   STACK4   (populated by SQLI)

Step 30 parameters:
  OUT   FILE   STACK4   (consumed by report)
```

No `LINK`/`UNLINK` is needed in the SQLI code — the system manages the
link lifecycle across steps. Position is not required for report-step
parameters.

Ref: [Procedures](https://prioritysoftware.github.io/sdk/Procedures)
| [Procedure Steps](https://prioritysoftware.github.io/sdk/Procedure-Steps)
| [Procedure Parameters](https://prioritysoftware.github.io/sdk/Procedure-Parameters)
| [Processed Reports](https://prioritysoftware.github.io/sdk/Processed-Report)
| [Priority Web](https://prioritysoftware.github.io/sdk/Priority-Web)

---

## 14. CREATE TABLE syntax

Priority's `CREATE TABLE` syntax is not standard SQL. The format is:

```
CREATE TABLE TABLENAME 'Title' flags
COLNAME (TYPE, width[, decimals], 'Title')
...
UNIQUE (col1[, col2, ...])
NONUNIQUE (col1[, col2, ...])
;
```

Example (from the built-in STACK4 table):
```
CREATE TABLE STACK4 'STACK4' 0
KEY        (INT,13,'Key')
INTDATA    (INT,17,'INTDATA')
REALDATA   (REAL,16,3,'REALDATA')
DATADATE   (DATE,8,'DATADATE')
DOCNO      (CHAR,16,'Document')
DETAILS    (RCHAR,64,'Details')
CHARDATA   (CHAR,1,'CHARDATA')
UNIQUE (KEY)
NONUNIQUE (INTDATA,CHARDATA)
;
```

### Flags (after the title)

| Value | Meaning |
|-------|---------|
| `0` | Single-company table (most tables) |
| `2` | Multi-company table — data is shared across companies (e.g. unified balance sheet in a multi-company environment) |

### Column types

| Type | Usage |
|------|-------|
| `INT` | Integer |
| `REAL` | Floating point / decimal |
| `CHAR` | Fixed-length left-to-right string (e.g. English) |
| `RCHAR` | Fixed-length right-to-left string (e.g. Hebrew) |
| `DATE` | Date (stored internally as integer — minutes since 01/01/88) |
| `TIME` | Time |

### Column width conventions for `INT`

| Width | Purpose |
|-------|---------|
| `13` | Key fields — auto-unique keys, foreign keys (e.g. `KLINE`, `PART`) |
| `3` | Sort / display-order fields |
| `17` | Numeric data — prices, quantities, amounts |

Width for `REAL` columns follows the destination table's precision requirements. The stored value will be truncated to whatever precision the destination column uses on INSERT.

`CHAR(1)` is commonly used as a boolean flag — `'Y'` for true, `'N'` or `'\0'` for false. Initialize with `'\0'` (not `''`).

### Indexes

- `UNIQUE (col1[, col2])` — unique index across one or more columns.
- `NONUNIQUE (col1[, col2])` — non-unique index for query performance.
- A table can have multiple `UNIQUE` and `NONUNIQUE` index declarations.
- Index naming follows the `TABLENAME_N` convention (e.g. `ARNT_MYTABLE_1`) when naming is required externally, but index names are not specified inside the `CREATE TABLE` statement itself.

### Notes
- No commas between column definitions — each column is on its own line.
- The statement is terminated with a bare `;` on its own line.
- Column titles (the quoted string) are display labels; they can be in any language.

---

## 15. SDK reference

Always prefer the live web SDK over any PDF version — the web version is current.

- [SDK home](https://prioritysoftware.github.io/sdk/)
- [Scalar expressions (STRCAT, DTOA, ITOA, etc.)](https://prioritysoftware.github.io/sdk/Scalar-Expressions)
- [SQL Variables (form variables, DUMMY table, variable scoping)](https://prioritysoftware.github.io/sdk/SQL-Variables)
- [SQL Functions and Variables (system functions, system variables)](https://prioritysoftware.github.io/sdk/SQL-Functions-Variables)
- [Return values and statement failure](https://prioritysoftware.github.io/sdk/RETVAL-Values)
- [Form triggers](https://prioritysoftware.github.io/sdk/Form-Triggers)
- [Including one trigger in another (#INCLUDE, buffers)](https://prioritysoftware.github.io/sdk/Include-Triggers)
- [Execute FormLoads / EXECUTE INTERFACE](https://prioritysoftware.github.io/sdk/Execute-FormLoads)
- [STACKERR](https://prioritysoftware.github.io/sdk/STACKERR)
- [DBI syntax (CREATE TABLE, FOR TABLE INSERT)](https://prioritysoftware.github.io/sdk/DBI-Syntax)
- [Accessing related forms / dynamic zoom](https://prioritysoftware.github.io/sdk/Accessing-Related-Form)
- [REST API – modifying related entities](https://prioritysoftware.github.io/restapi/modify/#Inserting_a_Related_Entity)

---

## 16. ENTMESSAGE

`ENTMESSAGE` retrieves the text of a numbered message defined on a form
or procedure, and expands any parameter placeholders in that text using
the current values of `:PAR1`, `:PAR2`, `:PAR3`.

### Syntax

```sql
ENTMESSAGE(entity_name, entity_type, message_number)
```

| Argument        | Values                                        |
|-----------------|-----------------------------------------------|
| `entity_name`   | Full form/procedure name. In procedures only, |
|                 | `'$'` may be used as an alias for the current |
|                 | procedure. **`'$'` does not work in forms —** |
|                 | always specify the full form name there.      |
| `entity_type`   | `'F'` for form, `'P'` for procedure           |
| `message_number`| Integer matching the number in the entity's   |
|                 | *Error & Warning Messages* sub-form           |

Must be run against `DUMMY`. If needed inside a query on a real table,
assign to a variable first.

### Parameter expansion

Messages may contain up to three placeholders — `<P1>`, `<P2>`,
`<P3>` — filled at call time from `:PAR1`, `:PAR2`, `:PAR3` (all
`CHAR` type). This is the same mechanism `ERRMSG`/`WRNMSG` use, so
`ENTMESSAGE` returns the same fully-expanded string those commands
would display.

Each placeholder may appear **any number of times** in the message
text. The limit of three is on distinct slots, not occurrences — so
`GOTO 9999 WHERE :$.<P1> = :$1.<P1>;` is valid with a single
`:PAR1` assignment.

Non-CHAR values must be converted before assignment:
```sql
:PAR1 = ITOA(:$.PART, 0);             /* INT  → CHAR */
:PAR1 = DTOA(:$.CURDATE, 'DD/MM/YY'); /* DATE → CHAR */
```

```sql
/* Message 50: "Part <P1> is not sold by vendor <P2>" */
:PAR1 = :$.PARTNAME;
:PAR2 = :$.SUPNAME;
:MSG  = ENTMESSAGE('PORDERITEMS', 'F', 50);
/* :MSG → "Part BOLT-M6 is not sold by vendor ACME" */
```

### Bypassing the 3-parameter limit

Build the tail of the message into `:PAR3` first, then fetch the head:

```sql
/* MSG 60: "Order <P1> dated <P2> cannot be closed: <P3>" */
/* MSG 61: "balance <P1> exceeds the approved limit <P2>" */

:PAR1 = ITOA(:$.BALANCE, 0);
:PAR2 = ITOA(:$.LIMIT, 0);
:PAR3 = ENTMESSAGE('ORDERS', 'F', 61);  /* tail → :PAR3 */
:PAR1 = :$.ORDNAME;
:PAR2 = DTOA(:$.CURDATE, 'DD/MM/YY');
:MSG  = ENTMESSAGE('ORDERS', 'F', 60);  /* head + tail  */
```

### Common patterns

```sql
/* Procedure — '$' alias */
:HEADER = ENTMESSAGE('$', 'P', 10);

/* Form trigger — full name required */
:LABEL = ENTMESSAGE('LOGPART', 'F', 5);

/* Parameterised */
:PAR1 = :$.PARTNAME;
:MSG  = ENTMESSAGE('ORDERS', 'F', 140);

/* As a STRCAT argument — fetch first */
:PREFIX = ENTMESSAGE('$', 'P', 30);
:TXT = STRCAT(:PREFIX, ': ', :SOMEVALUE);
```

### Message numbering convention

| Range | Purpose                                    |
|-------|--------------------------------------------|
| 1–9   | Error/validation messages (used by ERRMSG) |
| 10–49 | Section headers / titles                   |
| 50–99 | Body text / checklist labels               |
| 100+  | Code template lines                        |

Ref: [ENTMESSAGE — Scalar Expressions](https://prioritysoftware.github.io/sdk/Scalar-Expressions#files-and-messages)
| [Message Parameters](https://prioritysoftware.github.io/sdk/Errors-and-Warnings#message-parameters)

---

## 17. CHOOSE-FIELD column — full creation workflow

A CHOOSE-FIELD column presents the user with a picklist of predefined values.
Creating one is a multi-step process involving a values table, a form, a
foreign-key column, and (optionally) a buffer trigger for expansion tables.

The example below builds a **Financial Classification** field for the PART
table, using the customer prefix `PRIV`.

---

### Step 1 — Create the values table

```
CREATE TABLE PRIV_FNCCLASS 'סיווגי_כספים_לפריט' 0
FNCCLASS     (INT,13,'סיווג כספים (ID)')
FNCCLASSCODE (CHAR,3,'קוד סיווג כספים')
FNCCLASSDES  (RCHAR,32,'תאור סיווג כספים')
SORT         (INT,3,'מיון')
INACTIVE     (CHAR,1,'לא פעיל?')
UNIQUE (FNCCLASS)
UNIQUE (FNCCLASSCODE)
;
```

#### Naming rules

- **Table name**: `PREFIX_ENTITYNAME` — must not exceed 20 characters total
  (including prefix and underscore). Use underscores in place of spaces in
  both the table name and title to avoid upgrade collisions.
- **Column names** must not exceed 20 characters.
- **Auto-unique key** (`INT, 13`) carries the entity's ID and is the primary
  `UNIQUE` key.
- **CODE column** (`CHAR, 3`) is optional but common. When present it becomes
  the second `UNIQUE` key. When absent, the DES column is the `UNIQUE` key.
- **DES column** (`RCHAR`, typically 32) holds the display description.
- **SORT** (`INT, 3`) controls picklist order.
- **INACTIVE** (`CHAR, 1`) — boolean flag; `'Y'` = inactive. Inactive records
  are excluded from the CHOOSE-FIELD SELECT.

---

### Step 2 — Add the foreign-key column to the target table

Use `FOR TABLE ... INSERT` DBI syntax to add the FK column to the destination
table (or an expansion table — see notes).

```
FOR TABLE LOGPART
INSERT PRIV_FNCCLASS (INT,13,'סיווג_כספים_(ID)')
;
```

- The column name matches the values table name (`PRIV_FNCCLASS`).
- Use underscores in the column title.
- Width `13` matches the auto-unique key of the values table.
- If adding to a **private** table (name already has the prefix), the
  column itself does not need the prefix — the table isolation is sufficient.

DBI syntax reference:
[https://prioritysoftware.github.io/sdk/DBI-Syntax](https://prioritysoftware.github.io/sdk/DBI-Syntax)

#### Expansion-table notes

- For large tables (near the Priority column-count limit), create the FK in
  an expansion table (`PARTPARAM`, or a private `PRIV_PART`) instead.
- Expansion tables share the same autounique/unique key as the base table.
- When the FK lives in an expansion table, a buffer trigger is required
  (see Step 5).

---

### Step 3 — Create the values-entry form

| Property | Value |
|----------|-------|
| **Form Name** | Same as table — `PRIV_FNCCLASS` |
| **Form Title** | Same as table but with spaces — `סיווגי כספים לפריט` |
| **Base Table** | `PRIV_FNCCLASS` (auto-filled when name matches) |
| **Application** | 4-character prefix (`PRIV`) |
| **Module** | `פיתוח פרטי` / *Internal Development* |

#### Form Columns sub-form adjustments

1. **Hide** the auto-unique key column (`FNCCLASS`).
2. **Mark DES as mandatory** — set `M` in the Read-only/Mandatory column.
   (If DES is the UNIQUE key, the system enforces this automatically; if CODE
   is the unique key, set DES to `R` read-only instead.)
3. **Mark INACTIVE as boolean** in the column properties.
4. **Sort order**: `INACTIVE` ascending (inactive last), then `SORT`,
   then `FNCCLASSCODE` or `FNCCLASSDES` (whichever is the unique key).

#### Triggers

**CHOOSE-FIELD trigger** — defined at the *form* level so every FK column
that zooms to this form automatically shows the picklist, without having to
repeat the trigger on each referencing form:

```sql
SELECT FNCCLASSDES, FNCCLASSCODE, ITOA(SORT, 3)
FROM   PRIV_FNCCLASS
WHERE  INACTIVE <> 'Y'
ORDER BY 3, 1
```

Ref: [CHOOSE-FIELD for form](https://prioritysoftware.github.io/sdk/Creating-your-Triggers.html#CHOOSE-FIELD-(for-form))

**PRE-FORM trigger** — auto-populates the picklist when the user enters
the form directly (standard convenience pattern):

```sql
:KEYSTROKES = '*{Exit}';
```

Ref: [CHOOSE-FIELD notes](https://prioritysoftware.github.io/sdk/Creating-your-Triggers.html#choose-field)

---

### Step 4 — Add the FK column to the referencing form (e.g. LOGPART)

In the **Form Columns** (FORMCLMNS) sub-form of the referencing form:

1. **Add hidden FK column**
   - Form column name: add the customer prefix if the form is not private
     (e.g. `PRIV_FNCCLASS`).
   - Table column: `PRIV_FNCCLASS`; Table: `LOGPART` (or the expansion table).
   - Flag as **hidden**; position `599` (or another high hidden-slot number).
   - **Join**: Join Table = `PRIV_FNCCLASS`, Join Column = `FNCCLASS`,
     Join ID = `5` or higher (required for special joins — see SDK note on
     [Special Joins](https://prioritysoftware.github.io/sdk/Form-Columns#special-joins)).

2. **Add CODE column** (if the values table has one)
   - Column ID = same as the Join ID above.
   - Position: last visible columns, spaced ≥ 10 apart.

3. **Add DES column**
   - Column ID = same as the Join ID above.
   - If CODE is the unique key: set DES to `R` (read-only).
   - Position: after CODE, also spaced ≥ 10.

---

### Step 5 — Buffer trigger for expansion-table FK (when applicable)

When the FK column lives in an expansion table (not the form's base table),
the system will not auto-save it. A buffer trigger is required.

Look for an existing *private* buffer trigger first before creating a new one.

Ref: [Using Buffers](https://prioritysoftware.github.io/sdk/Include-Triggers.html#using-buffers)

#### Pattern

```sql
/* Skip if no tracked fields changed */
GOTO 9999 WHERE :$.PRIV_FNCCLASS = :$1.PRIV_FNCCLASS;

/* Ensure expansion-table row exists */
INSERT INTO PRIV_PART (PART)
VALUES (:$.PART);

/* Write all changed expansion fields */
UPDATE PRIV_PART
SET    PRIV_FNCCLASS = :$.PRIV_FNCCLASS
WHERE  PART = :$.PART;

LABEL 9999;
```

Rules:
- `:$1.FIELD` is the **old** (pre-change) value; `:$.FIELD` is the new value.
- The `GOTO 9999` guard must list every field managed by this trigger — add
  `AND :$.FIELD2 = :$1.FIELD2 ...` for each additional expansion column.
- The `INSERT` is safe to run even when the row already exists — Priority
  silently ignores duplicate-key inserts in this context.
- The `UPDATE` must reference every expansion field being managed.

---

## 18. Inspecting form structure via the Priority REST API

When writing triggers or business rules it is often necessary to know:
- what columns a form has (names, types, join info)
- what subforms hang off it

Use the **EFORM** endpoint with `$expand` to retrieve this in one call.

### Connection details (demo environment)

```
Base URL : https://t.eu.priority-connect.online/odata/Priority/tabbtd38.ini/usdemo
User     : apidemo
Password : 123
Auth     : HTTP Basic
```

For a customer's own environment, substitute their service root URL and credentials.

---

### Fetch a form with its columns and subforms

```
GET {baseURL}/EFORM(ENAME='{FORMNAME}',TYPE='F')?$expand=FCLMN_SUBFORM,FLINK_SUBFORM
```

`TYPE='F'` is always required and always `'F'` — EFORM only deals with forms.

**Example — TRANSORDER_P (Received Items):**
```
GET {baseURL}/EFORM(ENAME='TRANSORDER_P',TYPE='F')?$expand=FCLMN_SUBFORM,FLINK_SUBFORM
Authorization: Basic <base64(apidemo:123)>
```

#### Response shape

Top-level form fields:

| Field | Meaning |
|-------|---------|
| `ENAME` | Form name |
| `TITLE` | Hebrew/display title |
| `TNAME` | Underlying base table name |
| `MODULENAME` | Module the form belongs to |

#### FCLMN_SUBFORM fields (columns)

Each entry is one column visible (or hidden) in the form.

| Field | Meaning |
|-------|---------|
| `NAME` | **Form column name** — use this in SQL: `:$.NAME` |
| `CNAME` | Underlying table column name (may differ from `NAME`). `null` for calculated/expression columns |
| `TNAME` | Table the column comes from. `null` for expression columns |
| `TYPE` | Data type: `CHAR`, `INT`, `REAL`, `DATE`, `RCHAR`. `null` for expression columns |
| `WIDTH` | Display/storage width |
| `DEC` | Decimal places (for `INT`/`REAL`). `null` = none |
| `POS` | Display position. Visible columns have unique POS; many hidden columns share POS 99 |
| `HIDEBOOL` | `'Y'` = hidden column (not shown to user but available in SQL) |
| `READONLY` | `'R'` = read-only, `'M'` = mandatory |
| `BOOLEAN` | `'Y'` = boolean checkbox column |
| `EXPRESSION` | `'Y'` = calculated/virtual column (no direct table column) |
| `COVERBOOL` | `'Y'` = this is the "cover" column (primary display field) |
| `TRIGGERS` | `'Y'` = column has triggers attached |
| `JCNAME` | Join column name in the joined table (for FK join columns) |
| `JTNAME` | Join table name (for FK join columns) |
| `IDCOLUMNE` | Join instance index — `'0'` = first join, `'1'` = second join to same table |
| `COLTITLE` | Short column label (Hebrew) |
| `TITLE` | Longer column title override (Hebrew), or `null` to use `COLTITLE` |
| `INTERNATIONAL` | `'I'` = foreign-currency column |

**Key distinctions:**
- A column where `EXPRESSION = 'Y'` and `CNAME = null` is a virtual/calculated field — you can read it in the form but cannot UPDATE it directly on the table.
- `NAME` is what you use in trigger code (`:$.PARTNAME`, `:$.TQUANT`). `CNAME`/`TNAME` tell you the underlying table column for direct SQL.
- `JCNAME`/`JTNAME` non-null means this column is a join — it reads from a related table. The hidden integer ID column for the same join will have `JCNAME` = join column and `JTNAME` = join table.

#### FLINK_SUBFORM fields (subforms)

| Field | Meaning |
|-------|---------|
| `FNAME` | **Subform name** — use this to query the subform with EFORM |
| `TITLE` | Display title of the subform tab (Hebrew) |
| `APOS` | Tab position / display order |
| `AUTOSHOW` | `'A'` = opens automatically, `'N'` = manual, `null` = default |
| `MODULENAME` | Module the subform belongs to |
| `SONFORM` | Internal numeric form ID |

---

### Inspect a subform the same way

Once you have a subform name from `FLINK_SUBFORM` (field `FNAME`), query it identically:

```
GET {baseURL}/EFORM(ENAME='{FNAME}',TYPE='F')?$expand=FCLMN_SUBFORM,FLINK_SUBFORM
```

For example, to inspect `SERNTRANS` found in the TRANSORDER_P subform list:
```
GET {baseURL}/EFORM(ENAME='SERNTRANS',TYPE='F')?$expand=FCLMN_SUBFORM,FLINK_SUBFORM
```

---

### Fetch full service metadata (all forms)

Returns an XML document listing every EntityType (form) and its Properties (columns) and NavigationProperties (subforms):

```
GET {baseURL}/$metadata
Accept: application/xml
```

This is large — prefer the targeted EFORM query above when you know the form name.

---

### When to use this

- Before writing a trigger, confirm the exact column name, type, and whether it is read-only or mandatory.
- Verify a join column's target form (`JOINTO`) before writing buffer-trigger logic.
- Discover all subforms of a form when planning which sub-level triggers to add.
- Check that a form name exists and is of type `'F'` (form) vs `'P'` (procedure) before referencing it in code.

---

## 19. SQL system functions and variables

### System functions

These are read-only scalars available in any SQL context. Use them like
column expressions — they do not require FROM DUMMY unless they appear
in a SELECT statement.

| Function | Returns | Purpose |
|----------|---------|---------|
| `SQL.ENV` | CHAR | Current Priority company code |
| `SQL.USER` | INT | Internal number of the current user |
| `SQL.GROUP` | INT | Internal user number of the current user's group representative (privilege inheritance) |
| `SQL.DATE` | DATE | Current date **and** time |
| `SQL.DATEUTC` | DATE | Current date and time in UTC |
| `SQL.DATE8` | DATE | Current date **without** time |
| `SQL.TIME` | TIME | Current time |
| `SQL.DAY` | DAY | Current weekday |
| `SQL.LINE` | INT | Row counter during a result-set retrieval — rows numbered consecutively |
| `SQL.TMPFILE` | CHAR | Full path to a new temporary file; use as the handle for `LINK` |
| `SQL.LANGUAGE` | CHAR | Language code of the current user |
| `SQL.ENVLANG` | CHAR | Language code set for the company (Companies form) |
| `SQL.GUID` | CHAR(32) | Random 32-character UUID string from the OS |
| `SQL.PRETTY` | CHAR | External Access ID in Priority Connect for the current company (lowercase); uppercase for other companies |
| `SQL.CLOUDURL` | CHAR | Address of the cloud environment (cloud-hosted systems only) |
| `SQL.REGNAME` | CHAR | System registration name (matches the *About Priority* dialog) |
| `SQL.HOSTING` | INT | `1` if cloud-hosted, `0` otherwise |
| `SQL.ORACLE` | INT | `1` for Oracle database, `2` for SQL Server |

```sql
/* Common patterns */
SELECT SQL.TMPFILE INTO :MY_TMP FROM DUMMY;   /* get a temp file handle */
SELECT SQL.USER    INTO :CUR_USER FROM DUMMY; /* current user's internal ID */
SELECT SQL.DATE8   INTO :TODAY FROM DUMMY;    /* today without time component */
SELECT SQL.GUID    INTO :GUID FROM DUMMY;     /* random UUID */
```

Ref: [SQL Functions and Variables](https://prioritysoftware.github.io/sdk/SQL-Functions-Variables)

---

### System variables

These are pre-declared variables set by the engine. Do not declare them
yourself — they are always available.

#### Core runtime variables

| Variable | Type | Set by | Purpose |
|----------|------|--------|---------|
| `:RETVAL` | INT | Every SQL statement | Return value of the previous query (see §7) |
| `:SCRLINE` | INT | Engine | Current form line number — available in triggers only |
| `:PAR1`, `:PAR2`, `:PAR3` | CHAR(64) | Your code | Parameter slots for `ERRMSG`/`WRNMSG` message placeholders `<P1>`–`<P3>` (see §5, §15) |
| `:PAR4` | CHAR | Your code | First argument value in `CHOOSE-` triggers (not supported in the web interface) |
| `:_CHANGECOUNT` | INT | Engine | Number of fields modified in the current form record — available in PRE/POST-UPDATE triggers |
| `:FIRSTLINESFILL` | INT | Engine | `1` when entering a sub-level (useful for automated queries), `0` after the query runs |

#### Form interface detection

| Variable | Type | Purpose |
|----------|------|---------|
| `:FORM_INTERFACE` | INT | `1` when the current form record was populated by an interface load |
| `:FORM_INTERFACE_NAME` | CHAR | Name of the interface that loaded the record (only meaningful when `:FORM_INTERFACE = 1`) |

#### PRE-FORM automation

| Variable | Type | Purpose |
|----------|------|---------|
| `:PREFORMQUERY` | INT | Assign `1` in a PRE-FORM trigger to re-run the trigger after each query |
| `:ACTIVATE_POST_FORM` | CHAR(1) | Assign `'Y'` in a PRE-FORM trigger to fire the form's POST-FORM trigger on exit |
| `:KEYSTROKES` | CHAR | Simulate keyboard actions in form triggers (see below) |

#### Print / document variables

| Variable | Type | Purpose |
|----------|------|---------|
| `:PRINTFORMAT` | INT | Print format chosen by the user when printing a document (saved in EXTMSG) |
| `:SENDOPTION` | CHAR | User's selection in the Print/Send Options dialog |
| `:ISSENDPDF` | INT | `1` = create a PDF instead of HTML |
| `:WANTSEDOCUMENT` | INT | User's selection for digitally signed Outlook e-mails |
| `:EDOCUMENT` | INT | `1` = synchronize sent e-documents (recorded as a customer task) |
| `:GROUPPAGEBREAK` | INT | `1` = insert a page break at the first *Group by* set in a processed report |

#### Web / interface context

| Variable | Type | Purpose |
|----------|------|---------|
| `:SQL.NET` | INT | `0` = Windows client, `1` = web interface |
| `:ACTIVATEREFRESH` | INT | Assign `1` to refresh records after a Direct Activation |
| `:HEBREWFILTER` | INT | `0` = Hebrew text displays backwards, `1` = correct order |
| `:NOHTMLDESIGN` | INT | Assign `1` to force non-HTML output in a processed report or Priority Lite |
| `:HTMLMAXROWS` | INT | Limit the number of results shown per page in a processed report or Priority Lite |
| `:_IPHONE` | INT | `1` = mobile device, `0` = desktop or iPad |
| `:FROMTTS` | INT | `1` = procedure triggered via the Task Scheduler, `0` = otherwise |
| `:EXTERNAL.VARNAME` | CHAR | Read variables passed in via `WINACTIV` (always CHAR, regardless of the value's content) |

#### Application server settings (procedures only)

These are populated automatically in procedure SQLI steps and expose
`tabula.ini` / server configuration values:

| Variable | Content |
|----------|---------|
| `:NETDEFS_WCFURL` | WCF service URL |
| `:NETDEFS_SERVERURL` | Application server URL |
| `:NETDEFS_SESSIONDIRECTORY` | Session directory path |
| `:NETDEFS_SYSTEMIMAGES` | System images directory |
| `:NETDEFS_SYSTEMMAIL` | System mail address |
| `:NETDEFS_TMPDIRECTORY` | Temp directory path |
| `:NETDEFS_TMPURL` | Temp directory URL |
| `:NETDEFS_NETTABINI` | Path to the `tabula.ini` file for the current environment |

---

### `:KEYSTROKES` — simulating keyboard input

Assign a string of reserved words to `:KEYSTROKES` to automate user
actions in form triggers.

| Keyword | Action |
|---------|--------|
| `{Exit}` | Execute the current query (retrieve all records) |
| `_{Activate}N_` | Run the form's Nth Action |
| `_{Sub-level}N_` | Open the form's Nth sub-level form |
| `{Key Right}`, `{Key Left}`, `{Key Up}`, `{Key Down}` | Arrow-key navigation |
| `{Page Up}`, `{Page Down}` | Page navigation |
| `{Table/Line View}` | Toggle between multi-record and full-record display |

```sql
/* Retrieve all records automatically when the form opens */
:KEYSTROKES = '{Exit}';

/* Filter by date, then execute */
:KEYSTROKES = '{Key Right} 01/01/06 {Exit}';
```

Ref: [SQL Functions and Variables](https://prioritysoftware.github.io/sdk/SQL-Functions-Variables)

---

## 20. Scalar functions (Scalar Expressions)

All functions below are available as scalar expressions in SELECT lists,
WHERE clauses, and variable assignments.

Ref: [Scalar Expressions](https://prioritysoftware.github.io/sdk/Scalar-Expressions)

---

### Mathematical

| Function | Syntax | Returns | Notes |
|----------|--------|---------|-------|
| `ROUND` | `ROUND(m)` | INT | Rounds REAL to nearest integer, typed as INT |
| `ROUNDR` | `ROUNDR(m)` | REAL | Rounds REAL to nearest integer, typed as REAL |
| `ABS` | `ABS(m)` | INT | Absolute value of an INT |
| `ABSR` | `ABSR(m)` | REAL | Absolute value of a REAL |
| `EXP` | `EXP(m, n)` | INT | m to the power of n (both INT) |
| `POW` | `POW(m, n)` | REAL | m to the power of n (both REAL) |
| `SQRT` | `SQRT(m)` | INT | Square root of INT, rounded to nearest integer |
| `SQRTR` | `SQRTR(m)` | REAL | Square root of REAL |
| `MOD` | `n MOD m` | INT | Modular arithmetic; also extracts time component from DATE14 values |
| `MINOP` | `MINOP(m, n)` | numeric | Minimum of two numbers |
| `MAXOP` | `MAXOP(m, n)` | numeric | Maximum of two numbers |

```sql
SELECT ROUND(1.45)    FROM DUMMY; /* 1         */
SELECT EXP(3, 2)      FROM DUMMY; /* 9         */
SELECT 10 MOD 4       FROM DUMMY; /* 2         */
SELECT MINOP(1.5, 2)  FROM DUMMY; /* 1.500000  */
SELECT MAXOP(1.5, 2)  FROM DUMMY; /* 2.000000  */
```

---

### Numeric conversions

| Function | Syntax | Returns | Notes |
|----------|--------|---------|-------|
| `REALQUANT` | `REALQUANT(m)` | REAL | Shifted INT → REAL; decimal point moved by the DECIMAL system constant |
| `INTQUANT` | `INTQUANT(m)` | INT | REAL → shifted INT (inverse of REALQUANT) |
| `ITOH` | `ITOH(m)` | CHAR | INT to hexadecimal string |
| `HTOI` | `HTOI('M')` | INT | Hexadecimal string to INT |

```sql
SELECT REALQUANT(1000) FROM DUMMY; /* 1.000000 (assuming DECIMAL=3) */
SELECT INTQUANT(1.0)   FROM DUMMY; /* 1000     (assuming DECIMAL=3) */
SELECT ITOH(10)        FROM DUMMY; /* 'a'  */
SELECT HTOI('2f4')     FROM DUMMY; /* 756  */
```

---

### String ↔ number conversions

| Function | Syntax | Returns | Notes |
|----------|--------|---------|-------|
| `ITOA` | `ITOA(m)` or `ITOA(m, n)` | CHAR | INT to string; n = minimum width (zero-padded) |
| `ATOI` | `ATOI(string)` | INT | String to INT (max 10 characters) |
| `ATOR` | `ATOR(string)` | REAL | String to REAL (max 14 characters) |
| `RTOA` | `RTOA(m, n)` or `RTOA(m, n, USECOMMA)` | CHAR | REAL to string with n decimal places; `USECOMMA` adds thousands separator |

```sql
SELECT ITOA(35, 4)              FROM DUMMY; /* '0035'        */
SELECT ATOI('35')               FROM DUMMY; /* 35            */
SELECT ATOR('109012.99')        FROM DUMMY; /* 109012.990000 */
SELECT RTOA(150654.665, 2, USECOMMA) FROM DUMMY; /* '150.654,67' */
```

Use `ITOA` whenever an INT must be stored in a CHAR column (e.g. KEY1/KEY2
in GENERALLOAD) or passed to `STRCAT`. See also §2.

---

### String information

| Function | Syntax | Returns | Notes |
|----------|--------|---------|-------|
| `STRLEN` | `STRLEN(string)` | INT | Length of the string |
| `ISALPHA` | `ISALPHA(string)` | INT (0/1) | 1 if string starts with a letter and contains only letters, digits, `_` |
| `ISNUMERIC` | `ISNUMERIC(string)` | INT (0/1) | 1 if string contains only digits |
| `ISFLOAT` | `ISFLOAT(string)` | INT (0/1) | 1 if string is a valid real number |
| `ISPREFIX` | `ISPREFIX(s1, s2)` | INT (0/1) | 1 if s1 is a prefix of s2 |
| `STRINDEX` | `STRINDEX(full, search, index)` | INT | Position of `search` in `full` starting from `index`; 0 if not found; `-1` = reverse search |

```sql
SELECT STRLEN('Priority')               FROM DUMMY; /* 8 */
SELECT ISALPHA('Priority_21')           FROM DUMMY; /* 1 */
SELECT ISNUMERIC('07666')               FROM DUMMY; /* 1 */
SELECT ISFLOAT('14.5')                  FROM DUMMY; /* 1 */
SELECT ISPREFIX('HEEE', 'HEEE_ORDERS')  FROM DUMMY; /* 1 */
SELECT STRINDEX('hello world', 'o', 1)  FROM DUMMY; /* 5 */
```

---

### String manipulation

**`STRIND` vs `SUBSTR`:** `STRIND` and `RSTRIND` behave unexpectedly in a
SELECT from a real table. Prefer `SUBSTR` / `RSUBSTR` in all contexts —
they are identical but safe everywhere.

| Function | Syntax | Returns | Notes |
|----------|--------|---------|-------|
| `STRCAT` | `STRCAT(s1, s2, ...)` | CHAR | Concatenates strings (result max 127 chars) — `\|\|` is not valid in Priority |
| `SUBSTR` | `SUBSTR(string, m, n)` | CHAR | n characters starting at position m (1-based) |
| `STRIND` | `STRIND(string, m, n)` | CHAR | Same as SUBSTR — avoid in SELECT from a real table |
| `RSUBSTR` | `RSUBSTR(string, m, n)` | CHAR | Same as SUBSTR but reads right-to-left |
| `RSTRIND` | `RSTRIND(string, m, n)` | CHAR | Same as STRIND but reads right-to-left — avoid in SELECT from a real table |
| `STRPREFIX` | `STRPREFIX(string, n)` | CHAR | First n characters of string (n must be a fixed value, not a variable) |
| `STRPIECE` | `STRPIECE(string, delim, m, n)` | CHAR | Splits string by single-char delimiter; returns n pieces starting at piece m |
| `TOUPPER` | `TOUPPER(string)` | CHAR | Converts to uppercase |
| `TOLOWER` | `TOLOWER(string)` | CHAR | Converts to lowercase |

```sql
SELECT STRCAT('abc', 'ba')             FROM DUMMY; /* 'abcba'    */
SELECT SUBSTR('Priority', 3, 2)        FROM DUMMY; /* 'io'       */
SELECT RSUBSTR('Priority', 3, 2)       FROM DUMMY; /* 'ri'       */
SELECT STRPREFIX('Priority', 2)        FROM DUMMY; /* 'Pr'       */
SELECT STRPIECE('a/b.c.d', '.', 2, 1)  FROM DUMMY; /* 'c'       */
SELECT TOUPPER('marianne')             FROM DUMMY; /* 'MARIANNE' */
SELECT TOLOWER('MARIANNE')             FROM DUMMY; /* 'marianne' */
```

---

### Date parsing

| Function | Syntax | Returns | Notes |
|----------|--------|---------|-------|
| `DAY` | `DAY(date)` | INT | Weekday number (Sun=1, Mon=2, … Sat=7) |
| `MDAY` | `MDAY(date)` | INT | Day of the month (1–31) |
| `MONTH` | `MONTH(date)` | INT | Month number (1–12) |
| `YEAR` | `YEAR(date)` | INT | Four-digit year |
| `WEEK` | `WEEK(date)` | INT | YYWW format, e.g. `0612` = week 12 of 2006 |
| `WEEK6` | `WEEK6(date)` | INT | YYYYWW format, e.g. `200612` |
| `MWEEK` | `MWEEK(week)` | INT | Month number for a given WEEK value |
| `QUARTER` | `QUARTER(date)` | CHAR | Quarter string, e.g. `'3Q-2006'` |
| `TIMELOCAL` | `TIMELOCAL(date)` | INT | Unix timestamp (seconds since 1970-01-01) |
| `CTIME` | `CTIME(int)` | CHAR | Date string from Unix timestamp, e.g. `'Thu May 04 01:00:00 2006'` |

```sql
SELECT DAY(03/22/06)     FROM DUMMY; /* 4 (Wednesday) */
SELECT MDAY(03/22/06)    FROM DUMMY; /* 22            */
SELECT MONTH(03/22/06)   FROM DUMMY; /* 3             */
SELECT YEAR(03/22/06)    FROM DUMMY; /* 2006          */
SELECT WEEK6(03/22/06)   FROM DUMMY; /* 200612        */
SELECT QUARTER(09/22/06) FROM DUMMY; /* '3Q-2006'     */
```

---

### Date arithmetic — period boundaries

| Function | Syntax | Returns |
|----------|--------|---------|
| `BEGINOFWEEK` | `BEGINOFWEEK(yyww)` | First day of the week (input in WEEK format, e.g. `2220`) |
| `BEGINOFMONTH` | `BEGINOFMONTH(date)` | First day of the month |
| `BEGINOFQUARTER` | `BEGINOFQUARTER(date)` | First day of the quarter |
| `BEGINOFHALF` | `BEGINOFHALF(date)` | First day of the half-year |
| `BEGINOFYEAR` | `BEGINOFYEAR(date)` | First day of the year |
| `ENDOFMONTH` | `ENDOFMONTH(date)` | Last day of the month |
| `ENDOFQUARTER` | `ENDOFQUARTER(date)` | Last day of the quarter |
| `ENDOFHALF` | `ENDOFHALF(date)` | Last day of the half-year |
| `ENDOFYEAR` | `ENDOFYEAR(date)` | Last day of the year |

```sql
SELECT BEGINOFMONTH(05/04/06)   FROM DUMMY; /* 05/01/06 */
SELECT ENDOFMONTH(04/22/06)     FROM DUMMY; /* 04/30/06 */
SELECT BEGINOFQUARTER(05/04/06) FROM DUMMY; /* 04/01/06 */
SELECT BEGINOFYEAR(10/22/06)    FROM DUMMY; /* 01/01/06 */
```

---

### Date ↔ string conversions

| Function | Syntax | Returns | Notes |
|----------|--------|---------|-------|
| `DTOA` | `DTOA(date, pattern)` | CHAR | Date/time to formatted string. Common patterns: `'DD/MM/YY'`, `'DD/MM/YYYY'`, `'YY'`, `'MM'`, `'HH24:MI'` |
| `ATOD` | `ATOD(string, pattern)` | INT | External date string → Priority internal date integer. Mainly used when importing external data |

```sql
:YEAR    = DTOA(:$.CURDATE, 'YY');
:DISPLAY = DTOA(SQL.DATE, 'DD/MM/YYYY HH24:MI');
```

See §2 for DTOA in variable initialization, and §15 for DTOA with ENTMESSAGE parameters.

---

### File and message utilities

| Function | Syntax | Returns | Notes |
|----------|--------|---------|-------|
| `ENTMESSAGE` | `ENTMESSAGE(entity, type, num)` | CHAR | Returns numbered message text with `<P1>`–`<P3>` placeholders expanded. See §15 for full reference |
| `SYSPATH` | `SYSPATH(folder, output_type)` | CHAR | Path to a system folder. `folder`: `BIN`, `PREP`, `LOAD`, `MAIL`, `SYS`, `TMP`, `SYNC`, `IMAGE`. `output_type`: `1` = relative, `0` = absolute |
| `NEWATTACH` | `NEWATTACH(filename, extension)` | CHAR | Creates a unique path in the system mail folder. Extension optional but recommended (include the dot, e.g. `'.zip'`). Handles naming conflicts automatically |

```sql
SELECT SYSPATH('MAIL', 1)           FROM DUMMY; /* ../../system/mail */
SELECT SYSPATH('TMP',  0)           FROM DUMMY; /* absolute path     */
SELECT NEWATTACH('LOGFILE', '.zip') FROM DUMMY;
/* ../../system/mail/202202/1t2tymq0/logfile.zip */
```

---

## 21. Form triggers

Ref: [Form Triggers](https://prioritysoftware.github.io/sdk/Form-Triggers)
| [Creating Your Own Triggers](https://prioritysoftware.github.io/sdk/Creating-your-Triggers)

---

### Trigger types

| Category | Trigger | When it fires | Purpose |
|----------|---------|---------------|---------|
| **Column** | `CHECK-FIELD` | On exit from a column | Validate the entered value; block if invalid |
| **Column** | `POST-FIELD` | After a column passes CHECK-FIELD | Fill in derived values based on the column's value |
| **Column** | `CHOOSE-FIELD` | When the user opens the pick list | Define the list of selectable values |
| **Column** | `SEARCH-FIELD` | When the choose list is empty or too large | Provide a searchable fallback to the choose list |
| **Column** | `SEARCH-ALL-FIELD` | Alongside SEARCH-FIELD | Enable simultaneous multi-criteria search |
| **Row** | `PRE-INSERT` | Before a new record is saved | Validate or set defaults before insert |
| **Row** | `POST-INSERT` | After a new record is saved | Perform follow-up actions after insert |
| **Row** | `PRE-UPDATE` | Before a changed record is saved | Validate before update; `:FIELD` gives old value |
| **Row** | `POST-UPDATE` | After a changed record is saved | Perform follow-up actions after update |
| **Row** | `PRE-DELETE` | Before a record is deleted | Block or clean up before deletion |
| **Row** | `POST-DELETE` | After a record is deleted | Perform follow-up actions after deletion |
| **Form** | `PRE-FORM` | Before the form opens | Initialize variables, auto-retrieve records, set privileges |
| **Form** | `POST-FORM` | On form exit (see note) | Update parent form values based on sub-level changes |

---

### Execution order

1. `CHECK-FIELD` fires before `POST-FIELD` for the same column.
2. Built-in `CHECK-FIELD` triggers fire before user-designed ones.
3. Built-in `POST-FIELD` triggers fire before user-designed ones.
4. `PRE-` triggers fire before their corresponding `POST-` trigger.
5. Among triggers of the same type, execution order is alphabetical — name
   custom triggers accordingly (see naming conventions below).

**If a `CHECK-FIELD` is discontinued** (via `ERRMSG` or `END`), all
corresponding `POST-FIELD` triggers — both built-in and custom — are skipped.

---

### Activation rule

Triggers do not fire unless the user has made a change in the relevant
column, row, or form. The sole exception is `PRE-FORM`, which fires
automatically whenever the form opens.

---

### Naming custom triggers

- Must include the 4-letter customer identifier as a prefix or postfix.
- Must contain the key string for the trigger type (e.g. `CHECK-`, `POST-`,
  `-FIELD`, `-INSERT`, `-UPDATE`).
- Only alphanumeric characters, underscores, and hyphens; must start with a letter.

**Execution order and naming strategy:**

The SDK states that custom triggers sort alphabetically relative to standard
triggers. In practice this is unreliable — a custom trigger with an
alphabetically early name has been observed firing before standard triggers
regardless. Follow this convention:

| Intent | Convention | Example |
|--------|-----------|---------|
| Fire after standard triggers (default) | Postfix the customer identifier | `CHECK-FIELD_PRIV` |
| Fire before standard triggers | Prefix the customer identifier | `PRIV_CHECK-FIELD` |
| Fire absolutely last | Add `_ZZZZ` suffix | `CHECK-FIELD_PRIV_ZZZZ` |

---

### Customization restrictions

`SEARCH-FIELD` and `SEARCH-ALL-FIELD` cannot be customized — only the
standard system versions exist. All other trigger types support user-designed
versions.

---

### CHECK-FIELD specifics

- Error message numbers in `CHECK-FIELD` triggers must be **> 500**.
- If a `CHECK-FIELD` is discontinued, its `POST-FIELD` triggers are skipped
  (see execution order above).

---

### POST-FIELD cascade behavior

When a `POST-FIELD` trigger changes the value of another form column, that
other column's `POST-FIELD` fires automatically — but its `CHECK-FIELD` does
**not**. This is easy to overlook and can cause unexpected side-effects when
the changed column has its own validation logic.

---

### CHOOSE-FIELD variants

See §16 for the full column creation workflow. The trigger itself supports
several forms:

**Standard SQL query** — first column is the display description (max 64
chars), second is the value inserted into the field, optional third column
controls sort order:
```sql
SELECT FNCCLASSDES, FNCCLASSCODE, ITOA(SORT, 3)
FROM   PRIV_FNCCLASS
WHERE  INACTIVE <> 'Y'
ORDER BY 3, 1
```

**Form-message list** — messages defined on the form, structured as
`Value, Description`:
```sql
/* uses the form's message table instead of a SQL query */
```

**Union CHOOSE** — multiple `SELECT` blocks combined; results auto-sorted
by the first column:
```sql
SELECT DES, CODE FROM TABLE1
UNION
SELECT DES, CODE FROM TABLE2
```

**`/* AND STOP */`** — executes each `SELECT` in sequence and stops at the
first one that returns results:
```sql
SELECT DES, CODE FROM TABLE1 /* AND STOP */
SELECT DES, CODE FROM TABLE2 /* AND STOP */
```

**`/* NO SORT */`** — preserves the query's own order instead of sorting by
the first column:
```sql
SELECT DES, CODE FROM TABLE1 /* NO SORT */
```

**`MCHOOSE-FIELD`** — variant that allows selecting multiple values at once.

**Fallback behavior** — if the choose list is empty or exceeds the
`CHOOSEROWS` system constant, a `SEARCH-FIELD` trigger activates instead
(if one is defined for the column).

---

### Combined triggers

A combined trigger fires on multiple row events, avoiding duplicated logic
across separate triggers. Example: `PRE-INSERT-UPDATE_PRIV` fires before
both insert and update.

Event names are often abbreviated (`INS`, `UPD`, `DEL`) to stay within the
maximum trigger name length — this is especially necessary for combined
triggers, which are already long before adding the customer pre/postfix.

**Combined triggers cannot contain cursors — directly or via `#INCLUDE`.**
This restriction applies only to combined triggers; single-event `INSERT`
or `UPDATE` triggers are not affected.

---

### PRE-FORM and POST-FORM

**PRE-FORM** fires before the form opens. Common uses:
- Variable initialization
- Conditional warnings or errors before entry
- Auto-retrieving records (`:KEYSTROKES = '{Exit}';`)
- Deactivating data privileges

**POST-FORM** fires on exit, but only when the user has made at least one
change. Common use: updating values in a parent form based on sub-level
changes.

To make `POST-FORM` fire unconditionally on exit regardless of changes,
assign `:ACTIVATE_POST_FORM = 'Y'` in a `PRE-FORM` trigger.

Cross-ref §18 — *PRE-FORM automation* for the full list of related system
variables (`:KEYSTROKES`, `:PREFORMQUERY`, `:ACTIVATE_POST_FORM`, etc.).
