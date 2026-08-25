---
name: priority-sql-procedures
description: >
  Priority ERP procedure development — step types (B/C/R/F/P/I/L),
  parameter types (CHAR/INT/REAL/DATE/ASCII/FILE/LINE/NFILE), INPUT vs
  INPUTF, processed report pattern (3-step structure), and FILE parameters
  (passing linked tables between SQLI and report steps). Use when designing
  or implementing a Priority procedure, configuring step types, or
  structuring data flow between steps. For the SQL code inside SQLI steps,
  see the `priority-sql` skill.
---

# Procedures

A procedure is a sequence of numbered steps executed in order by default,
but flow can jump between steps using `GOTO` (Basic command steps).

For trigger code used in procedure SQLI steps, see the `priority-sql` skill.
For form trigger context, see the `priority-sql-forms` skill.

### Step types

| Type | Code | Description |
|------|------|-------------|
| Basic command | B | `INPUT`/`INPUTF`, `END`, `GOTO`, `MESSAGE`, etc. |
| SQLI program | C | Executes a block of Priority SQL |
| Report | R | Runs a report step and displays output |
| Form | F | Opens a form for user interaction |
| Sub-procedure | P | Calls another procedure |
| Form load interface | I | Runs a form load |
| Table load | L | Imports external data |

**Priority Web constraints:**
- Never use `EXECUTE WINFORM` or `EXECUTE WINACTIV` inside an SQLI step to
  open forms or run procedures that display UI — they run on the server, not
  the client. Add a separate step of type F or P instead.
- For document output, use `WINHTML` instead of `WINACTIV`.
- Procedures that load or export data must include an `UPLOAD` or `DOWNLOAD`
  step to transfer files between client and server. (Exception: not needed
  when using a `CHAR` INPUT parameter with a browse button.)

**F-suffix convention:** Many Basic commands have an F-suffix variant
(`CHOOSE`/`CHOOSEF`, `MESSAGE`/`MESSAGEF`, `PRINT`/`PRINTF`,
`CONTINUE`/`CONTINUEF`, etc.). The base command is suppressed when the
procedure runs as a form Action; the F variant fires in both contexts.
`INPUT`/`INPUTF` follows the same rule — see below.

### Parameter types

| Type | Usage |
|------|-------|
| `CHAR`, `INT`, `REAL`, `DATE` | Scalar value passed between steps |
| `ASCII` | Text file (e.g. error message file for `PRINTERR`) |
| `FILE` | Linked table of records — bidirectional between steps |
| `LINE` | Single record from the database |
| `NFILE` | Like FILE, but link table stays empty if user enters `*` or leaves the field empty |

**Parameter name limit:** 3 characters maximum (e.g. `PRF`, `OUT`).

### INPUT vs INPUTF

`INPUT` — shows the parameter input screen only when run directly by
the user. Suppressed when the procedure is called as an Action from a
form.

`INPUTF` — shows the input screen in both contexts. Prefer `INPUTF`
for developer tools and any procedure where input is always required.

### Processed report pattern

The standard three-step structure for a procedure that generates a
report from computed data:

```
Step 10  INPUTF     B   — collect user inputs
Step 20  PROC_NAME  C   — validate, compute, populate linked table
Step 30  RPT_NAME   R   — render the report
```

The procedure must have `R` in the *Rep/Wizard/Dashboard* column so
it behaves like a report from the user's perspective (print/export
options, standard report viewer).

### Passing a linked table between SQLI and report steps

Declare a `FILE` parameter (e.g. `OUT`, table = `STACK4`) on **both**
the SQLI step and the report step, using the same parameter name. The
system links the table to a temp file before the SQLI step runs; the
SQLI step writes into it directly; the report step reads from the same
linked file automatically.

```
Step 20 parameters:
  OUT   FILE   STACK4   (populated by SQLI)

Step 30 parameters:
  OUT   FILE   STACK4   (consumed by report)
```

No `LINK`/`UNLINK` is needed in the SQLI code — the system manages the
link lifecycle across steps. Position is not required for report-step
parameters.

### Dynamic report filtering (REPCONDITION)

To apply runtime filter conditions to a report step, declare a local
`REPCONDITION` variable (type `FILE`) in the preceding SQLI step:

```sql
SELECT SQL.TMPFILE INTO :REPCONDITION FROM DUMMY;
```

Populate it with filter conditions in ASCII format. The report step picks up
these conditions automatically — no parameter declaration needed on the
report step.

See `WWWDB_PORDERS_A` step 40 in the standard demo company for a working
example.

Ref: [Procedures](https://prioritysoftware.github.io/sdk/Procedures)
| [Procedure Steps](https://prioritysoftware.github.io/sdk/Procedure-Steps)
| [Procedure Parameters](https://prioritysoftware.github.io/sdk/Procedure-Parameters)
| [Processed Reports](https://prioritysoftware.github.io/sdk/Processed-Report)
| [Priority Web](https://prioritysoftware.github.io/sdk/Priority-Web)
