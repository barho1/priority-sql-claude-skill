---
name: priority-sql-dbi
description: >
  Priority ERP DBI (database interface) — DDL operations for creating and
  modifying the Priority database schema. Covers CREATE TABLE syntax (column
  types INT/REAL/CHAR/RCHAR/DATE, width conventions, UNIQUE and NONUNIQUE
  indexes, single-company vs multi-company flags), and FOR TABLE INSERT syntax
  for adding columns to existing tables (FK columns, plain columns, expansion
  tables). Use when creating a new custom table, adding a column to an existing
  table, or designing the schema for a new entity. Not for SQLI (triggers,
  procedures, cursors) — see the `priority-sql` skill for those.
---

# Priority ERP — DBI (Database Interface)

DBI commands define and modify the database schema. They are distinct from
SQLI (procedural SQL) — DBI is DDL, SQLI is DML/flow.

Ref: [DBI syntax](https://prioritysoftware.github.io/sdk/DBI-Syntax)

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

### Naming rules for custom tables

- **Table name**: `PREFIX_ENTITYNAME` — must not exceed 20 characters total
  (including prefix and underscore). Use underscores in place of spaces in
  both the table name and title to avoid upgrade collisions.
- **Column names** must not exceed 20 characters.
- The **auto-unique key** column (`INT, 13`) is always the first `UNIQUE` key.
- If there is a CODE column (`CHAR, 3`), it becomes the second `UNIQUE` key.
  When absent, the DES column is the unique key instead.

---

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
required to save it — see the `priority-sql-forms` skill §1 Step 5.
