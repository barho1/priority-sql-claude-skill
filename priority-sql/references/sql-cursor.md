# Cursor loop pattern

Use when you need to iterate over a result set and perform per-row logic (e.g. UPDATE with a computed value per row).

## Canonical template

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

## Rules — never violate these

**Always follow the canonical template exactly — do not invent variations.**
Every cursor must use the structure: `DECLARE` → `OPEN` → `GOTO <empty-label>` → variable initialization → `LABEL <loop>` → `FETCH` → `GOTO <end-label>` → cursor body → `LOOP <loop>` → `LABEL <end>` → `CLOSE` → `LABEL <empty>`. Never reorder, merge, or omit any part of this skeleton. Label numbers change; the structure does not.

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

## Tracking previous-iteration values

A cursor overwrites its variables on every `FETCH`. If you need to reference a value from the previous iteration (typically key fields to detect a group boundary or compare against the prior record), save them into tracking variables at the **end** of the iteration body, just before `LOOP`.

Rules:
- **Initialize tracking variables explicitly** after `OPEN` succeeds and before `LABEL 1000`. Never assume they start at zero or empty.
- **Handle the null/uninitialized case** at the top of the cursor body — on the first iteration the tracking variable will hold its initialized default, which must be a value that cannot appear as a real key (e.g. `0` for integers, `''` or `'\0'` for strings).
- **Group initializations by type** on a single line for readability (see variable initialization conventions in `priority-sql` §10).

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
