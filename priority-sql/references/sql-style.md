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

For sharing logic across forms with `#INCLUDE` and buffers, see the include/buffers reference.

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

### General
- Align `INTO`, `FROM`, `WHERE`, `AND` vertically where it aids readability.
- Use `/* ... */` comments, not `--` (Priority line comments are less portable).
