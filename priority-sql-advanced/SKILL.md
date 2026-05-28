---
name: priority-sql-advanced
description: >
  Advanced Priority ERP SQL patterns — GENERALLOAD row accumulation for
  multi-level document loading (header + subform lines, RECORDTYPE hierarchy),
  and pre-computation pattern for complex INSERTs (STACK-based pre-computation
  followed by a clean join-based INSERT). Use when building complex document
  loading interfaces or INSERT logic that requires correlated lookup values
  pre-computed via cursor or temp tables.
---

# Priority ERP SQL — Advanced Patterns

---

## 1. GENERALLOAD row accumulation — header + subform lines

For the basic EXECUTE INTERFACE pattern, see the `priority-sql` skill §9.
For cursor loops used to build the row set, see the `priority-sql` skill §6.

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

## 2. Pre-computation pattern for complex INSERTs

For cursor loop pattern, see the `priority-sql` skill §6.
For STACK/STACK4 temp table usage, see the `priority-sql` skill §8.

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

## 3. Abstract SUB pattern — deferred calculation via `#INCLUDE`

Requires familiarity with `#INCLUDE` and buffers — see the `priority-sql-forms` skill §4.

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
