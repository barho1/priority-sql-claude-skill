---
name: priority-sql
description: >
  Write, review, and debug Priority ERP procedural SQL — unsupported syntax
  (ISNULL, ||, subquery in SET, UPDATE...FROM), cursor loops, temp tables
  (STACK/STACK4/GENERALLOAD), EXECUTE INTERFACE, control flow
  (GOTO/GOSUB/LABEL/LOOP), message commands (ERRMSG/WRNMSG/GENMSG),
  return values (:RETVAL), variable scoping (:$., :$$., :$1., :GLOBAL.),
  code style, and procedures (step types, INPUT vs INPUTF, processed report
  pattern, FILE parameters). Use when writing or fixing Priority SQL trigger
  or procedure code, designing cursor patterns, or asking why Priority SQL is
  failing. Context cues: ERRMSG, GOSUB, LINK/UNLINK, SQL.TMPFILE, :$.FIELD,
  STACK table names. For complex multi-level GENERALLOAD or pre-computation
  INSERT patterns, see the `priority-sql-advanced` skill.
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
:GOTO = (:TYPE = 'A' ? 10 :  
/**/    (:TYPE = 'B' ? 20 :
/**/    (:TYPE = 'C' ? 30 :
/**/     99)));

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

For cursor patterns inside pre-computation, see the `priority-sql-advanced` skill §2.

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

For multi-level GENERALLOAD with header + subform lines, see the `priority-sql-advanced` skill §1.

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

For building the GENERALLOAD hierarchy (header + subform rows), see the `priority-sql-advanced` skill §1.

---

## 10. Code style conventions

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

For sharing logic across forms with `#INCLUDE` and buffers, see the `priority-sql-forms` skill §4.

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
  built entirely from variables belong inline. See the `priority-sql-ref` skill §5 for the full ENTMESSAGE reference.

---

## 11. Procedures

A procedure is a sequence of named steps executed in order. The most
common pattern in custom development is a **processed report**: user
input → data manipulation (SQLI) → report output.

For trigger code used in procedure SQLI steps, see §1–§9 above. For
form trigger context, see the `priority-sql-forms` skill §3.

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
