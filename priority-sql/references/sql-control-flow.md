## 4. Control flow — GOTO, GOSUB, LOOP, LABEL

### LABEL / GOTO / LOOP
All three accept an optional `WHERE` clause — execution only jumps if the condition is true.
```sql
GOTO 100 WHERE :RETVAL < 1;     /* jump to LABEL 100 if condition is met */
LOOP 200 WHERE :MORE = 'Y';     /* jump back to LABEL 200 if condition is met */
```

### GOTO / ERRMSG / WRNMSG with FROM — shorthand for EXISTS
`GOTO`, `ERRMSG`, and `WRNMSG` all support a `FROM table WHERE condition`
form directly on the command — not just a plain `WHERE condition`. This is
shorthand for `WHERE EXISTS (SELECT 'X' FROM table WHERE condition)`, and
appears extensively in Priority's own shipped code (not just documented in
the public SDK's Flow Control page, which only shows the plain WHERE form).
```sql
/* Shorthand */
GOTO 1 FROM CONSTANTS WHERE NAME = 'DELETERPART' AND VALUE = 0;
ERRMSG 3 FROM ACTALT WHERE ACT = :$.ALT;
/* Equivalent verbose form */
GOTO 1 WHERE EXISTS
(SELECT 'X' FROM CONSTANTS WHERE NAME = 'DELETERPART' AND VALUE = 0);
ERRMSG 3 WHERE EXISTS
(SELECT 'X' FROM ACTALT WHERE ACT = :$.ALT);
```
The `FROM` clause isn't limited to a single table — it works exactly like
the `FROM` of a `SELECT`, so multiple tables and joins (via standard
`WHERE` join syntax) are supported:
```sql
GOTO 1 FROM ACTALT A, ACTUSERS U
WHERE A.ACT = U.ACT AND U.USER = SQL.USER;
```
Prefer the `FROM` shorthand when checking existence against one or more
tables — it's shorter and matches the style used throughout Priority's
core forms (e.g. ACTALT/BUF1, ACTALT/BUF2). Fall back to the verbose
`WHERE EXISTS (SELECT ...)` form only when the condition needs to combine
an EXISTS check with other boolean logic that doesn't cleanly fit a single
`FROM ... WHERE`.

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

`ERRMSG` and `WRNMSG` also accept the `FROM table WHERE condition` shorthand
for an EXISTS check — see "GOTO / ERRMSG / WRNMSG with FROM — shorthand for
EXISTS" in section 4.

Use `ERRMSG` for form/procedure-specific messages. Use `GENMSG` for reusable system-wide messages (e.g. in shared interfaces). Use `WRNMSG` when the user should be able to override the warning and proceed.

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
| `LINK` | 2 if a new file was created; 1 if linked to an existing file; 0 on failure | –1 if the table is already linked once (duplicate link attempt); insufficient permissions |

**Key patterns derived from this table:**

`RETVAL = 0` after `SELECT INTO` means no row was found — the target
variable is left at its pre-SELECT value (see the ISNULL rule in the hard-rules table).

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

`LINK` return values also distinguish creation from reuse: `2` means a new
temp file was created, `1` means it linked to a temp file that already
existed (e.g. re-linking without `REMOVE`) — useful if code needs to branch
on whether the file already has data. `–1` means the same table was already
linked once (a duplicate link attempt), distinct from an outright failure
(`0`); both still satisfy the `:RETVAL < 1` guard pattern used below.

Ref: [Return Values and Statement Failure](https://prioritysoftware.github.io/sdk/RETVAL-Values#table-of-return-values-and-statement-failure)

---

