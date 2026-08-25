## 2. SQL system functions and variables

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

#### Lightweight pseudo-random from `SQL.GUID`

The official random-number mechanism is `PRANDOM`, which costs a temp file, a
`LINK STACK4` and a read back out of `DETAILS`. When the value is not
cryptographic and that boilerplate is not worth it, derive one inline instead —
`SQL.GUID` is 32 hex characters, so `HTOI` of any two of them gives 0..255:

```sql
SELECT SQL.GUID INTO :GUID FROM DUMMY;
:N = (HTOI(SUBSTR(:GUID, 1, 2)) MOD :RANGE) + :BASE;
```

Good for stubs, sampling and cheap one-off picks. Reach for `PRANDOM` when the
official mechanism is required, or when a wider or better-distributed value
matters — 256 values with `MOD` is neither uniform nor large.

---

### System variables

These are pre-declared variables set by the engine. Do not declare them
yourself — they are always available.

#### Core runtime variables

| Variable | Type | Set by | Purpose |
|----------|------|--------|---------|
| `:RETVAL` | INT | Every SQL statement | Return value of the previous query (see :RETVAL in the control flow reference) |
| `:SCRLINE` | INT | Engine | Current form line number — available in triggers only |
| `:PAR1`, `:PAR2`, `:PAR3` | CHAR(64) | Your code | Parameter slots for `ERRMSG`/`WRNMSG` message placeholders `<P1>`–`<P3>` (see message commands in the control flow reference, and the form metadata reference) |
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

