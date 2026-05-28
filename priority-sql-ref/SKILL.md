---
name: priority-sql-ref
description: >
  Priority ERP SQL reference — CREATE TABLE and FOR TABLE INSERT DBI syntax,
  SDK reference index, scalar functions (STRCAT, ITOA, ATOI, ATOR, RTOA,
  DTOA, ATOD, STRLEN, SUBSTR, STRPIECE, STRINDEX, TOUPPER, TOLOWER, ROUND,
  MOD, MINOP, MAXOP, ABS, SQRT, POW, date functions YEAR/MONTH/MDAY/WEEK/
  QUARTER/BEGINOFMONTH/ENDOFMONTH/BEGINOFYEAR/ENDOFYEAR, SYSPATH, NEWATTACH,
  ENTMESSAGE), system functions (SQL.USER, SQL.DATE, SQL.DATE8, SQL.TMPFILE,
  SQL.GUID, SQL.ORACLE, SQL.HOSTING, SQL.ENV), and system variables
  (:SCRLINE, :PAR1-3, :KEYSTROKES, :FORM_INTERFACE, :_CHANGECOUNT,
  :PREFORMQUERY, :ACTIVATE_POST_FORM, :NETDEFS_*), and ENTMESSAGE (syntax,
  parameter expansion, message numbering conventions). Use when looking up a
  specific function, variable, column type, or table creation syntax.
---

# Priority ERP SQL — Reference

---

## 1. CREATE TABLE syntax

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

## 2. SDK reference

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

## 3. SQL system functions and variables

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
| `:RETVAL` | INT | Every SQL statement | Return value of the previous query (see §7 in the `priority-sql` skill) |
| `:SCRLINE` | INT | Engine | Current form line number — available in triggers only |
| `:PAR1`, `:PAR2`, `:PAR3` | CHAR(64) | Your code | Parameter slots for `ERRMSG`/`WRNMSG` message placeholders `<P1>`–`<P3>` (see §5 in the `priority-sql` skill and §2 in the `priority-sql-forms` skill) |
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

## 4. Scalar functions (Scalar Expressions)

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
in GENERALLOAD) or passed to `STRCAT`. See also §2 in the `priority-sql` skill.

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

See §2 in the `priority-sql` skill for DTOA in variable initialization, and §5 in this skill for DTOA with ENTMESSAGE parameters.

---

### File and message utilities

| Function | Syntax | Returns | Notes |
|----------|--------|---------|-------|
| `ENTMESSAGE` | `ENTMESSAGE(entity, type, num)` | CHAR | Returns numbered message text with `<P1>`–`<P3>` placeholders expanded. See §5 in this skill for full reference |
| `SYSPATH` | `SYSPATH(folder, output_type)` | CHAR | Path to a system folder. `folder`: `BIN`, `PREP`, `LOAD`, `MAIL`, `SYS`, `TMP`, `SYNC`, `IMAGE`. `output_type`: `1` = relative, `0` = absolute |
| `NEWATTACH` | `NEWATTACH(filename, extension)` | CHAR | Creates a unique path in the system mail folder. Extension optional but recommended (include the dot, e.g. `'.zip'`). Handles naming conflicts automatically |

```sql
SELECT SYSPATH('MAIL', 1)           FROM DUMMY; /* ../../system/mail */
SELECT SYSPATH('TMP',  0)           FROM DUMMY; /* absolute path     */
SELECT NEWATTACH('LOGFILE', '.zip') FROM DUMMY;
/* ../../system/mail/202202/1t2tymq0/logfile.zip */
```

---

## 5. ENTMESSAGE

`ENTMESSAGE` retrieves the text of a numbered message defined on a form
or procedure, and expands any parameter placeholders in that text using
the current values of `:PAR1`, `:PAR2`, `:PAR3`.

For ENTMESSAGE usage conventions in code style, see the `priority-sql` skill §10.

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
