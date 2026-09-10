---
name: priority-sql-dbi
description: >
  Priority ERP DBI (database interface) — DDL operations for creating and
  modifying the Priority database schema. Covers CREATE TABLE syntax (column
  types INT/REAL/CHAR/RCHAR/DATE, width conventions, UNIQUE and NONUNIQUE
  indexes, single-company vs multi-company flags), FOR TABLE INSERT syntax for
  adding columns to existing tables (FK columns, plain columns, expansion
  tables), and every other DBI modification — DELETE TABLE, rename/retitle a
  table, column changes (delete, rename, width, title, decimal, number type),
  and key changes (add/delete key, key priority, key-column priority,
  autounique→unique, unique→nonunique) plus the unique-key danger zones. Use
  when creating a new custom table, adding or altering a column, changing a key,
  or designing the schema for a new entity. Not for SQLI (triggers, procedures,
  cursors) — see the `priority-sql` skill for those.
---

# Priority ERP — DBI (Database Interface)

DBI commands define and modify the database schema. They are distinct from
SQLI (procedural SQL) — DBI is DDL, SQLI is DML/flow.

Ref: [DBI syntax](https://prioritysoftware.github.io/sdk/DBI-Syntax)

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

### Naming rules for custom tables

- **Table name**: `PREFIX_ENTITYNAME` — must not exceed 20 characters total
  (including prefix and underscore). Use underscores in place of spaces in
  both the table name and title to avoid upgrade collisions.
- **Column names** must not exceed 20 characters.
- The **auto-unique key** column (`INT, 13`) is always the first `UNIQUE` key.
- If there is a CODE column (`CHAR, 3`), it becomes the second `UNIQUE` key.
  When absent, the DES column is the unique key instead.

## 2. FOR TABLE INSERT — adding a column to an existing table

`FOR TABLE ... INSERT` adds one or more columns to an existing Priority table.
This is Priority's equivalent of `ALTER TABLE ... ADD COLUMN`.

### Syntax

```
FOR TABLE TABLENAME
INSERT COLNAME (TYPE, width[, decimals], 'Title')
[INSERT COLNAME2 (TYPE, width, 'Title')]
;
```

### Adding a plain column

```
FOR TABLE ORDERS
INSERT PRIV_NOTES (RCHAR,64,'הערות_מיוחדות')
;
```

- Use underscores in the column title (spaces cause upgrade collisions).
- The column name must not exceed 20 characters.
- Choose the type and width to match the data being stored (see §1 column types).

### Adding a foreign-key column

When adding an FK that links to a values table (e.g. for a CHOOSE-FIELD),
the column name conventionally matches the values table name and the width
must be `13` (matching the auto-unique key of the referenced table):

```
FOR TABLE LOGPART
INSERT PRIV_FNCCLASS (INT,13,'סיווג_כספים_(ID)')
;
```

- If adding to a **private** table (whose name already has the prefix),
  the column itself does not need the prefix — table isolation is sufficient.
- Width `13` is mandatory for FK columns — it matches the auto-unique key
  width of the referenced table.

### Expansion tables

For large tables near the Priority column-count limit, add the column to
an expansion table (`PARTPARAM`, or a private `PRIV_PART`) instead of the
base table. Expansion tables share the same autounique/unique key as the
base table. When an FK lives in an expansion table, a buffer trigger is
required to save it — see the `priority-sql-forms` skill.

## 3. Modifying a table

Priority DBI has **no `ALTER TABLE`**. Every modification is a `CREATE TABLE`,
`DELETE TABLE`, or `FOR TABLE …` statement terminated with `;`.

### Syntax

```
DELETE TABLE table_name;

FOR TABLE table_name
CHANGE NAME TO new_name;

FOR TABLE table_name CHANGE TITLE TO 'new_title';
```

### Examples

```
DELETE TABLE XXXX_CUSTOMERS;

FOR TABLE XXXX_CUSTOMERS
CHANGE NAME TO XXXX_CLIENTS;

FOR TABLE XXXX_CLIENTS CHANGE TITLE TO 'Client_Registry';
```

### Caveats

- `DELETE TABLE` fails if **any** column of the table appears in a form, report
  or procedure.
- Renaming a table does **not** touch forms or reports (they reference the
  table's internal number). Every SQL statement that names the table — form
  triggers, procedures, compiled programs — must be updated by hand.
- Table title: ≤ 20 characters, single-quoted, underscores in place of spaces
  (spaces cause upgrade collisions).

## 4. Modifying a column

### Syntax

```
FOR TABLE table_name DELETE column_name;

FOR TABLE table_name COLUMN column_name
CHANGE NAME TO new_name;

FOR TABLE table_name COLUMN column_name CHANGE WIDTH TO integer;

FOR TABLE table_name COLUMN column_name CHANGE TITLE TO 'title';

FOR TABLE table_name COLUMN column_name
CHANGE DECIMAL TO decimal_precision;

FOR TABLE table_name COLUMN column_name CHANGE NUMBER TYPE;
FOR TABLE table_name COLUMN column_name CHANGE NUMBER TYPE TO REAL;
FOR TABLE table_name COLUMN column_name CHANGE NUMBER TYPE TO INT;
```

Keyword asymmetry: deleting a column is `FOR TABLE t DELETE col` with **no
`COLUMN` keyword**; every `CHANGE …` needs `COLUMN col`.

`CHANGE NUMBER TYPE` (no `TO`) toggles INT ↔ REAL. `… TO REAL` / `… TO INT`
force a direction and leave the column untouched if it is already that type.

### Examples

```
FOR TABLE XXXX_CUSTOMERS DELETE XXXX_OLDNOTES;

FOR TABLE XXXX_CUSTOMERS COLUMN XXXX_NOTES
CHANGE NAME TO XXXX_REMARKS;

FOR TABLE XXXX_CUSTOMERS COLUMN XXXX_REMARKS CHANGE WIDTH TO 80;

FOR TABLE XXXX_CUSTOMERS COLUMN XXXX_REMARKS CHANGE TITLE TO 'Client_Remarks';

FOR TABLE XXXX_CUSTOMERS COLUMN XXXX_BALANCE
CHANGE DECIMAL TO 2;

FOR TABLE XXXX_CUSTOMERS COLUMN XXXX_QUANT CHANGE NUMBER TYPE TO REAL;
```

### Caveats

- `CHANGE DECIMAL` is **singular** (not `DECIMALS`).
- Cannot delete a column that appears in a form, report or procedure.
- `CHANGE NAME` on a column: forms and reports are unaffected (identified by
  internal number), but SQL statements referencing the column must be revised.
- `CHANGE WIDTH` **downward loses data** wider than the new width. If the column
  is in a unique key, rows can be **silently deleted** — see §7.
- `CHANGE DECIMAL TO` is valid only for: any `REAL` column; a regular `INT`
  (current precision 0) changed to the `DECIMAL` system constant; a shifted
  `INT` changed to 0 (back to a regular integer). A shifted integer's precision
  must equal the `DECIMAL` constant, or be 0.
- `CHANGE NUMBER TYPE` (INT ↔ REAL) is the **only** column-type change DBI
  supports, and only during the development phase — it "may fail" once a
  customization has been installed. `REAL → INT` rounds to the nearest integer
  and sets precision 0; `INT → REAL` adds precision 2. For any other type
  change: add a new column, copy the data across, delete the old column.
- Keep `CHAR` columns ≤ 80 wide; use a sub-level text form for anything larger.

## 5. Modifying a key

### Syntax

```
FOR TABLE table_name
INSERT { AUTOUNIQUE | UNIQUE | NONUNIQUE } (column_name, ...)
[ WITH PRIORITY key_priority ];

FOR TABLE table_name
DELETE KEY { key_priority | (column_name, ...) };

FOR TABLE table_name
KEY { key_priority | (column_name, ...) }
CHANGE PRIORITY TO new_key_priority;

FOR TABLE table_name
CHANGE AUTOUNIQUE TO UNIQUE;

FOR TABLE table_name
KEY { key_priority | (column_name, ...) }
CHANGE UNIQUE TO NONUNIQUE;
```

A key is identified either by its numeric priority (`KEY 2`) or by its full
column list in parentheses (`KEY (COL_A, COL_B)`).

### Examples

```
FOR TABLE XXXX_CUSTOMERS
INSERT NONUNIQUE (XXXX_CITY, XXXX_CLOSED)
WITH PRIORITY 3;

FOR TABLE XXXX_CUSTOMERS
DELETE KEY (XXXX_CITY, XXXX_CLOSED);

FOR TABLE XXXX_CUSTOMERS
KEY 3
CHANGE PRIORITY TO 2;

FOR TABLE XXXX_CUSTOMERS
CHANGE AUTOUNIQUE TO UNIQUE;

FOR TABLE XXXX_CUSTOMERS
KEY (XXXX_CITY)
CHANGE UNIQUE TO NONUNIQUE;
```

### Caveats

- `CHANGE AUTOUNIQUE TO UNIQUE` is **table-level** — no `KEY` selector (there is
  only ever one autounique key).
- Only two type conversions exist: `AUTOUNIQUE → UNIQUE` and
  `UNIQUE → NONUNIQUE`. There is **no reverse** (`NONUNIQUE → UNIQUE`,
  `UNIQUE → AUTOUNIQUE`) in DBI.
- You **cannot** change the type of the **first** unique key —
  `CHANGE UNIQUE TO NONUNIQUE` on key priority 1 fails.
- If an autounique key exists it must be key priority 1 and a unique key must be
  priority 2. Every table needs at least one unique key.
- The autounique key must be a single `INT` column that appears in no other key.
- **Adding a unique key is a danger zone** — see §7.

## 6. Modifying the columns inside a key

### Syntax

```
FOR TABLE table_name
KEY { key_priority | (column_name, ...) }
INSERT column_name [ WITH PRIORITY column_priority ];

FOR TABLE table_name
KEY { key_priority | (column_name, ...) }
DELETE column_name;

FOR TABLE table_name
KEY { key_priority | (column_name, ...) }
COLUMN column_name
CHANGE PRIORITY TO new_column_priority;
```

### Examples

```
FOR TABLE XXXX_CUSTOMERS
KEY 2
INSERT XXXX_BRANCH WITH PRIORITY 2;

FOR TABLE XXXX_CUSTOMERS
KEY 2
DELETE XXXX_BRANCH;

FOR TABLE XXXX_CUSTOMERS
KEY (XXXX_LASTNAME, XXXX_FIRSTNAME)
COLUMN XXXX_FIRSTNAME
CHANGE PRIORITY TO 1;
```

### Caveats

- Adding a key column **without** `WITH PRIORITY` gives it the last (lowest)
  available priority automatically.
- Giving a new column a priority already in use pushes that column and every
  lower-priority one down one slot.
- Deleting a key column: all lower-priority columns move up one slot.
- Changing one column's priority reshuffles the others in the key.
- **Deleting a column from a unique key is a danger zone** — see §7.

## 7. Rules and danger zones

### Preconditions

- Every statement ends with `;`.
- Requires the superuser (`tabula`) privilege group and `PRIVUSERS = 1`, run
  from the SQL Development program.
- **Only one Table Generator / DBI operation may run at a time** — across all
  users. Concurrent runs overwrite shared temporary tables.
- Each modification is its own `FOR TABLE …;` statement. The **one exception**
  is adding columns: multiple `INSERT column_name (...)` clauses may follow a
  single `FOR TABLE` (as in §2).

### Cannot be done via DBI

- Delete a table or column that appears in any form, report or procedure.
- Change a column's type other than `INT ↔ REAL` (and that only during
  development).
- Reverse a key-type conversion (`NONUNIQUE → UNIQUE`, `UNIQUE → AUTOUNIQUE`).
- Change the type of the first unique key.
- Create or modify system tables (type `2` / `3`). New tables are type `0`;
  type `2` is a shared multi-company system table, and the SDK states you
  "cannot create new system tables" — treat type `2` as an edge case, not a
  default.

### Three unique-key danger zones — each can silently delete rows

1. **Adding a unique key** while its columns are not yet populated with
   distinct values — all but one row is erased (they collide on identical
   key values).
2. **Deleting a column from a unique key** — if the shorter key makes rows
   collide, all but one is erased.
3. **Reducing the width of a column in a unique key** — truncation can make
   rows collide, and duplicates are erased.

Before any of these, verify the key columns hold distinct, fully-populated
values.

### Column titles

≤ 20 characters including spaces, single-quoted. Use underscores in place of
spaces to avoid upgrade collisions.
