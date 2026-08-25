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
SELECT ENTMESSAGE('$', 'P', 10) INTO :MSG FROM DUMMY;
/* equivalent explicit form: */
SELECT ENTMESSAGE('$', 'P', 10) INTO :MSG FROM DUMMY;
```

Always use `DUMMY` (rather than a real table) when the query result
depends only on variables or scalar functions — it is both semantically
clearer and faster.

Ref: [SQL Variables — The DUMMY Table](https://prioritysoftware.github.io/sdk/SQL-Variables#the-dummy-table)

### `LIKE` — extended patterns, the single-line rule, and no variables

Priority extends standard `LIKE` wildcards and adds constraints not
present in standard SQL.

**Hard rule — the pattern must be a constant string; it cannot embed
a variable.**
```sql
/* WRONG — variable interpolated inside the LIKE pattern */
SELECT FLD_A FROM TBL WHERE FLD_B LIKE '%:varname%';
```
A colon-prefixed name inside single quotes is not substituted — quotes
suppress variable expansion — so this either fails outright or silently
matches the literal text `:varname` instead of the variable's value.
There is no way to parameterize a `LIKE` pattern with a runtime value.
**Pattern to replace it:** for a "contains" check against a runtime
value, use `STRIND(:FIELD, :SUBSTR, 1) > 0` (or `SUBSTR`/`STRLEN`
comparisons for prefix/suffix checks) instead of `LIKE`.
```sql
/* CORRECT — runtime substring check without LIKE */
SELECT FLD_A FROM TBL WHERE STRIND(FLD_B, :SUBSTR, 1) > 0;
```

**Wildcards:**
- `_` — matches a single character
- `%` — matches any number of characters (including zero)

**Character brackets `|...|`** — enclose a set or range of characters
to match any one of them:
```sql
WHERE PARTNAME LIKE '|A-D|%'   /* starts with A, B, C, or D */
```

**Negation `\^`** inside brackets — match any character *other than*
those listed:
```sql
WHERE PARTNAME LIKE '|\^A-D|%'  /* does NOT start with A-D */
```

**Escaping a wildcard/bracket character** — prefix it with `\` to
match it literally:
```sql
WHERE PARTNAME LIKE 'A\%'   /* matches the literal string "A%" */
```

**Hard rule — a `LIKE` expression must stay on a single line.**
Unlike other WHERE clauses, which are normally broken across lines for
the 68-character limit (see the code style reference), a `LIKE '...'` clause itself must never
be split — don't let a line break fall between the column, `LIKE`, and
its pattern string.
```sql
/* WRONG — LIKE split across lines */
WHERE (PARTNAME LIKE '%' OR PART.PARTDES
LIKE '%' OR EPARTDES LIKE '%')
/* CORRECT — each LIKE clause stays on one line; break elsewhere */
WHERE (PARTNAME LIKE '%' OR PART.PARTDES LIKE '%'
OR EPARTDES LIKE '%')
```

Ref: [SDK Additions to Standard SQL Commands](https://prioritysoftware.github.io/sdk/Additions-to-SQL-Commands)

---

