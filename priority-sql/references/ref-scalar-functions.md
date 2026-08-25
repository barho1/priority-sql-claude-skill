## 3. Scalar functions (Scalar Expressions)

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
| `ITOA` | `ITOA(m)` or `ITOA(m, n)` | CHAR | INT to string; n = minimum width (zero-padded). A value needing more digits than `n` is returned in full — `ITOA(1234567, 6)` gives `'1234567'`, never truncated |
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
in GENERALLOAD) or passed to `STRCAT`. See also the supported SQL syntax reference.

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

### Date arithmetic

Priority stores dates as integers (minutes since 01/01/88). Use the
`HH:MM` time-literal notation for offsets — it reads as intent rather
than a raw number.

| Expression | Meaning |
|------------|---------|
| `:DATE + 24:00` | Add one day |
| `:DATE - 24:00` | Subtract one day |
| `:DATE + 7 * 24:00` | Add seven days |
| `:DATE + 1:00` | Add one hour |

```sql
:TOMORROW  = :TODAY + 24:00;
:NEXT_WEEK = :TODAY + 7 * 24:00;
:YESTERDAY = :TODAY - 24:00;
```

**Day difference between two dates:**
```sql
:DATE1 = SQL.DATE;
:DATE2 = 23/08/26 15:00;
SELECT 0+(:DATE1 - :DATE2) / 24:00
FROM DUMMY FORMAT;
```

**Stripping the time component:**
```sql
:DATEONLY = :DATE - :DATE MOD 24:00;
```

`:DATE MOD 24:00` yields the time component, so subtracting it leaves the date
at midnight. **Do not use `ROUND` for this** — dates are integers (minutes
since 01/01/88), so rounding one to the nearest integer does nothing.

Use `SQL.DATE8` instead of `SQL.DATE` when you need today's date without a
time component in the first place.

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

See the supported SQL syntax reference for DTOA in variable initialization, and the ENTMESSAGE reference for DTOA with ENTMESSAGE parameters.

---

### File and message utilities

| Function | Syntax | Returns | Notes |
|----------|--------|---------|-------|
| `ENTMESSAGE` | `ENTMESSAGE(entity, type, num)` | CHAR | Returns numbered message text with `<P1>`–`<P3>` placeholders expanded. See the ENTMESSAGE reference for full details |
| `SYSPATH` | `SYSPATH(folder, output_type)` | CHAR | Path to a system folder. `folder`: `BIN`, `PREP`, `LOAD`, `MAIL`, `SYS`, `TMP`, `SYNC`, `IMAGE`. `output_type`: `1` = relative, `0` = absolute |
| `NEWATTACH` | `NEWATTACH(filename, extension)` | CHAR | Creates a unique path in the system mail folder. Extension optional but recommended (include the dot, e.g. `'.zip'`). Handles naming conflicts automatically |

```sql
SELECT SYSPATH('MAIL', 1)           FROM DUMMY; /* ../../system/mail */
SELECT SYSPATH('TMP',  0)           FROM DUMMY; /* absolute path     */
SELECT NEWATTACH('LOGFILE', '.zip') FROM DUMMY;
/* ../../system/mail/202202/1t2tymq0/logfile.zip */
```

---

