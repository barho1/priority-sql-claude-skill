## 4. ENTMESSAGE

`ENTMESSAGE` retrieves the text of a numbered message defined on a form
or procedure, and expands any parameter placeholders in that text using
the current values of `:PAR1`, `:PAR2`, `:PAR3`.

For ENTMESSAGE usage conventions in code style, see the `priority-sql` skill.

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
