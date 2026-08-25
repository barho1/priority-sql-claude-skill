## 8. Linked temp tables (STACK, STACK4, GENERALLOAD, etc.)

Always pair every `LINK` with an `UNLINK`. Use `SQL.TMPFILE` as the file handle.

Every `LINK` must be guarded — with `ERRMSG` or a `GOTO` past the section
that uses the linked table. This isn't just a style habit: if a `LINK` fails
and isn't guarded, the statements that follow execute against the real table
instead of the intended temp copy, silently and with no error.

```sql
SELECT SQL.TMPFILE INTO :MY_TMP FROM DUMMY;
LINK STACK4 MYDATA TO :MY_TMP;
ERRMSG 1 WHERE :RETVAL < 1;
/* ... use MYDATA ... */
UNLINK AND REMOVE STACK4 MYDATA;
```

`UNLINK AND REMOVE` frees both the link and the temp file. Use plain `UNLINK` if you want to keep the file for re-linking later.

`LINK ALL <table>` is shorthand for `LINK <table>` plus
`INSERT INTO <table> SELECT * FROM <table> ORIG` — it copies *every* row of
the source table into the temp copy. Fine for small tables, but it is almost
never what you want: prefer a scoped `INSERT ... SELECT ... WHERE` after a
plain `LINK` so only the records actually needed get copied.

### Linking with an alias

`LINK <table> <alias>` links the table under a different name:

```sql
LINK STACK LEAFPARTS TO :TMP;
INSERT INTO LEAFPARTS (ELEMENT) VALUES (:PART);
```

**Once you link under an alias you must address the linked copy by that
alias.** A bare `INSERT INTO STACK` in the same code writes to the *real*
`STACK` table, not to your temp copy — silently, with no error. This is the
main reason to use an alias deliberately or not at all.

Ref: [Link/Unlink](https://prioritysoftware.github.io/sdk/Link-Unlink)

For multi-level GENERALLOAD with header + subform lines, see the advanced patterns reference.

---

## 9. EXECUTE INTERFACE — standard pattern

```sql
/* 1. Create a linked GENERALLOAD */
SELECT SQL.TMPFILE INTO :GEN_TMP FROM DUMMY;
LINK GENERALLOAD TO :GEN_TMP;
GENMSG 1 WHERE :RETVAL <= 0;
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
Add the `-stackerr` switch and link `STACK_ERR` to a tmpfile before executing.
Ref: [SDK Execute-FormLoads – Errors](https://prioritysoftware.github.io/sdk/Execute-FormLoads#dealing-with-errors-and-reloading) | [SDK STACKERR](https://prioritysoftware.github.io/sdk/STACKERR)

**Anti-pattern** — do NOT use `LOADED <> 'Y'` as the primary error check:
```sql
/* WRONG — not the standard pattern */
ERRMSG 1 WHERE EXISTS (SELECT 1 FROM GENERALLOAD WHERE LOADED <> 'Y');
```

For building the GENERALLOAD hierarchy (header + subform rows), see the advanced patterns reference.

---

### Finding which interface to use

`EXECUTE INTERFACE` takes the name of a **form-load interface** defined in the
system — not the name of a form or table. You cannot guess it, and the
`RECORDTYPE` values and generic-column mapping (`TEXT1`, `REAL1`, `DATE1`, …)
are defined in that interface record, so the load code is unreadable without
it open alongside. Ways to find what exists:

| Where | What it gives you |
|-------|-------------------|
| **FORMINTERFACES** form (sub-level of *Form Generator*) | Every interface a given form participates in — the usual starting point |
| **FCLMNINTER** form (sub-level of *Form Columns*, under *Form Generator*) | Interfaces associated with a specific form column |
| *Procedure Steps* report (**PROGREP**), under *System Management → Generators → Procedures → Procedure Reports* | Filter for step type `I` to list form loads, or filter for procedures containing the `INTERFACE` step |
| *SQL Development* (**WINDBI**), under *System Management → Generators → Procedures* | Queries menu → "Find String" → search `'EXECUTE INTERFACE'` to find existing load procedures to copy from |
| Form / procedure / menu generators | Filter on `LOAD*` to surface interim-table forms and their load procedures |

Ref: [Existing Interfaces](https://prioritysoftware.github.io/sdk/Existing-Interfaces)

---

