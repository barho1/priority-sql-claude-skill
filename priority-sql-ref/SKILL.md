---
name: priority-sql-ref
description: >
  Priority ERP SQL reference — SDK reference index, scalar functions (STRCAT,
  ITOA, ATOI, ATOR, RTOA, DTOA, ATOD, STRLEN, SUBSTR, STRPIECE, STRINDEX,
  TOUPPER, TOLOWER, ROUND, MOD, MINOP, MAXOP, ABS, SQRT, POW, date functions
  YEAR/MONTH/MDAY/WEEK/QUARTER/BEGINOFMONTH/ENDOFMONTH/BEGINOFYEAR/ENDOFYEAR,
  date arithmetic, SYSPATH, NEWATTACH, ENTMESSAGE), system functions
  (SQL.USER, SQL.DATE, SQL.DATE8, SQL.TMPFILE, SQL.GUID, SQL.ORACLE,
  SQL.HOSTING, SQL.ENV), and system variables (:SCRLINE, :PAR1-3,
  :KEYSTROKES, :FORM_INTERFACE, :_CHANGECOUNT, :PREFORMQUERY,
  :ACTIVATE_POST_FORM, :NETDEFS_*), and ENTMESSAGE (syntax, parameter
  expansion, message numbering conventions). For DBI (CREATE TABLE, FOR TABLE
  INSERT), see the `priority-sql-dbi` skill. Use when looking up a specific
  function or variable.
---

# Priority ERP SQL Reference

Load the relevant file with the Read tool when the request needs that detail —
don't load them speculatively. These files and their names are internal
navigation aids for you, not something to mention to the user — answer with
the content itself, never by citing a reference file's path or name.

| File | Load when the request involves… |
|------|----------------------------------|
| `references/sdk-links.md` | Pointing at official SDK documentation pages |
| `references/system-functions.md` | `SQL.USER`, `SQL.DATE`, `SQL.TMPFILE`, `SQL.GUID`, `SQL.ORACLE`, system variables (`:SCRLINE`, `:PAR1-3`, `:KEYSTROKES`, `:FORM_INTERFACE`, `:PREFORMQUERY`) |
| `references/scalar-functions.md` | Looking up a scalar function — `STRCAT`, `ITOA`, `ATOI`, `SUBSTR`, `STRPIECE`, `ROUND`, date functions, date arithmetic |
| `references/entmessage.md` | `ENTMESSAGE`, message numbering, parameter expansion in messages |
