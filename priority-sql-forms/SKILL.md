---
name: priority-sql-forms
description: >
  Priority ERP form development — all form trigger types (CHECK-FIELD,
  POST-FIELD, CHOOSE-FIELD, SEARCH-FIELD, PRE-INSERT, POST-INSERT,
  PRE-UPDATE, POST-UPDATE, PRE-DELETE, POST-DELETE, PRE-FORM, POST-FORM),
  trigger execution order, trigger naming conventions, CHOOSE-FIELD variants
  (AND STOP, NO SORT, MCHOOSE, union), CHOOSE-FIELD column creation workflow
  (CREATE TABLE, FOR TABLE INSERT, form setup, buffer trigger for expansion
  tables), and inspecting form/column structure via the Priority REST API
  (EFORM endpoint, FCLMN_SUBFORM, FLINK_SUBFORM). Use when creating or
  modifying form triggers, designing CHOOSE-FIELD picklists, or exploring
  form column and subform metadata.
---

# Priority ERP — Form Development

---

## 1. CHOOSE-FIELD column — full creation workflow

A CHOOSE-FIELD column presents the user with a picklist of predefined values.
Creating one is a multi-step process involving a values table, a form, a
foreign-key column, and (optionally) a buffer trigger for expansion tables.

For cursor and temp-table patterns used in trigger code, see the `priority-sql` skill.

The example below builds a **Financial Classification** field for the PART
table, using the customer prefix `PRIV`.

---

### Step 1 — Create the values table

```
CREATE TABLE PRIV_FNCCLASS 'סיווגי_כספים_לפריט' 0
FNCCLASS     (INT,13,'סיווג כספים (ID)')
FNCCLASSCODE (CHAR,3,'קוד סיווג כספים')
FNCCLASSDES  (RCHAR,32,'תאור סיווג כספים')
SORT         (INT,3,'מיון')
INACTIVE     (CHAR,1,'לא פעיל?')
UNIQUE (FNCCLASS)
UNIQUE (FNCCLASSCODE)
;
```

#### Naming rules

- **Table name**: `PREFIX_ENTITYNAME` — must not exceed 20 characters total
  (including prefix and underscore). Use underscores in place of spaces in
  both the table name and title to avoid upgrade collisions.
- **Column names** must not exceed 20 characters.
- **Auto-unique key** (`INT, 13`) carries the entity's ID and is the primary
  `UNIQUE` key.
- **CODE column** (`CHAR, 3`) is optional but common. When present it becomes
  the second `UNIQUE` key. When absent, the DES column is the `UNIQUE` key.
- **DES column** (`RCHAR`, typically 32) holds the display description.
- **SORT** (`INT, 3`) controls picklist order.
- **INACTIVE** (`CHAR, 1`) — boolean flag; `'Y'` = inactive. Inactive records
  are excluded from the CHOOSE-FIELD SELECT.

---

### Step 2 — Add the foreign-key column to the target table

Use `FOR TABLE ... INSERT` DBI syntax to add the FK column to the destination
table (or an expansion table — see notes).

```
FOR TABLE LOGPART
INSERT PRIV_FNCCLASS (INT,13,'סיווג_כספים_(ID)')
;
```

- The column name matches the values table name (`PRIV_FNCCLASS`).
- Use underscores in the column title.
- Width `13` matches the auto-unique key of the values table.
- If adding to a **private** table (name already has the prefix), the
  column itself does not need the prefix — the table isolation is sufficient.

DBI syntax reference:
[https://prioritysoftware.github.io/sdk/DBI-Syntax](https://prioritysoftware.github.io/sdk/DBI-Syntax)

#### Expansion-table notes

- For large tables (near the Priority column-count limit), create the FK in
  an expansion table (`PARTPARAM`, or a private `PRIV_PART`) instead.
- Expansion tables share the same autounique/unique key as the base table.
- When the FK lives in an expansion table, a buffer trigger is required
  (see Step 5).

---

### Step 3 — Create the values-entry form

| Property | Value |
|----------|-------|
| **Form Name** | Same as table — `PRIV_FNCCLASS` |
| **Form Title** | Same as table but with spaces — `סיווגי כספים לפריט` |
| **Base Table** | `PRIV_FNCCLASS` (auto-filled when name matches) |
| **Application** | 4-character prefix (`PRIV`) |
| **Module** | `פיתוח פרטי` / *Internal Development* |

#### Form Columns sub-form adjustments

1. **Hide** the auto-unique key column (`FNCCLASS`).
2. **Mark DES as mandatory** — set `M` in the Read-only/Mandatory column.
   (If DES is the UNIQUE key, the system enforces this automatically; if CODE
   is the unique key, set DES to `R` read-only instead.)
3. **Mark INACTIVE as boolean** in the column properties.
4. **Sort order**: `INACTIVE` ascending (inactive last), then `SORT`,
   then `FNCCLASSCODE` or `FNCCLASSDES` (whichever is the unique key).

#### Triggers

**CHOOSE-FIELD trigger** — defined at the *form* level so every FK column
that zooms to this form automatically shows the picklist, without having to
repeat the trigger on each referencing form:

```sql
SELECT FNCCLASSDES, FNCCLASSCODE, ITOA(SORT, 3)
FROM   PRIV_FNCCLASS
WHERE  INACTIVE <> 'Y'
ORDER BY 3, 1
```

Ref: [CHOOSE-FIELD for form](https://prioritysoftware.github.io/sdk/Creating-your-Triggers.html#CHOOSE-FIELD-(for-form))

**PRE-FORM trigger** — auto-populates the picklist when the user enters
the form directly (standard convenience pattern):

```sql
:KEYSTROKES = '*{Exit}';
```

Ref: [CHOOSE-FIELD notes](https://prioritysoftware.github.io/sdk/Creating-your-Triggers.html#choose-field)

---

### Step 4 — Add the FK column to the referencing form (e.g. LOGPART)

In the **Form Columns** (FORMCLMNS) sub-form of the referencing form:

1. **Add hidden FK column**
   - Form column name: add the customer prefix if the form is not private
     (e.g. `PRIV_FNCCLASS`).
   - Table column: `PRIV_FNCCLASS`; Table: `LOGPART` (or the expansion table).
   - Flag as **hidden**; position `599` (or another high hidden-slot number).
   - **Join**: Join Table = `PRIV_FNCCLASS`, Join Column = `FNCCLASS`,
     Join ID = `5` or higher (required for special joins — see SDK note on
     [Special Joins](https://prioritysoftware.github.io/sdk/Form-Columns#special-joins)).

2. **Add CODE column** (if the values table has one)
   - Column ID = same as the Join ID above.
   - Position: last visible columns, spaced ≥ 10 apart.

3. **Add DES column**
   - Column ID = same as the Join ID above.
   - If CODE is the unique key: set DES to `R` (read-only).
   - Position: after CODE, also spaced ≥ 10.

---

### Step 5 — Buffer trigger for expansion-table FK (when applicable)

When the FK column lives in an expansion table (not the form's base table),
the system will not auto-save it. A buffer trigger is required.

Look for an existing *private* buffer trigger first before creating a new one.

Ref: [Using Buffers](https://prioritysoftware.github.io/sdk/Include-Triggers.html#using-buffers)

#### Pattern

```sql
/* Skip if no tracked fields changed */
GOTO 9999 WHERE :$.PRIV_FNCCLASS = :$1.PRIV_FNCCLASS;

/* Ensure expansion-table row exists */
INSERT INTO PRIV_PART (PART)
VALUES (:$.PART);

/* Write all changed expansion fields */
UPDATE PRIV_PART
SET    PRIV_FNCCLASS = :$.PRIV_FNCCLASS
WHERE  PART = :$.PART;

LABEL 9999;
```

Rules:
- `:$1.FIELD` is the **old** (pre-change) value; `:$.FIELD` is the new value.
- The `GOTO 9999` guard must list every field managed by this trigger — add
  `AND :$.FIELD2 = :$1.FIELD2 ...` for each additional expansion column.
- The `INSERT` is safe to run even when the row already exists — Priority
  silently ignores duplicate-key inserts in this context.
- The `UPDATE` must reference every expansion field being managed.

For ENTMESSAGE used in trigger messages, see the `priority-sql-ref` skill §5.

---

## 2. Inspecting form structure via the Priority REST API

When writing triggers or business rules it is often necessary to know:
- what columns a form has (names, types, join info)
- what subforms hang off it

Use the **EFORM** endpoint with `$expand` to retrieve this in one call.

### Connection details (demo environment)

```
Base URL : https://t.eu.priority-connect.online/odata/Priority/tabbtd38.ini/usdemo
User     : apidemo
Password : 123
Auth     : HTTP Basic
```

For a customer's own environment, substitute their service root URL and credentials.

---

### Fetch a form with its columns and subforms

```
GET {baseURL}/EFORM(ENAME='{FORMNAME}',TYPE='F')?$expand=FCLMN_SUBFORM,FLINK_SUBFORM
```

`TYPE='F'` is always required and always `'F'` — EFORM only deals with forms.

**Example — TRANSORDER_P (Received Items):**
```
GET {baseURL}/EFORM(ENAME='TRANSORDER_P',TYPE='F')?$expand=FCLMN_SUBFORM,FLINK_SUBFORM
Authorization: Basic <base64(apidemo:123)>
```

#### Response shape

Top-level form fields:

| Field | Meaning |
|-------|---------|
| `ENAME` | Form name |
| `TITLE` | Hebrew/display title |
| `TNAME` | Underlying base table name |
| `MODULENAME` | Module the form belongs to |

#### FCLMN_SUBFORM fields (columns)

Each entry is one column visible (or hidden) in the form.

| Field | Meaning |
|-------|---------|
| `NAME` | **Form column name** — use this in SQL: `:$.NAME` |
| `CNAME` | Underlying table column name (may differ from `NAME`). `null` for calculated/expression columns |
| `TNAME` | Table the column comes from. `null` for expression columns |
| `TYPE` | Data type: `CHAR`, `INT`, `REAL`, `DATE`, `RCHAR`. `null` for expression columns |
| `WIDTH` | Display/storage width |
| `DEC` | Decimal places (for `INT`/`REAL`). `null` = none |
| `POS` | Display position. Visible columns have unique POS; many hidden columns share POS 99 |
| `HIDEBOOL` | `'Y'` = hidden column (not shown to user but available in SQL) |
| `READONLY` | `'R'` = read-only, `'M'` = mandatory |
| `BOOLEAN` | `'Y'` = boolean checkbox column |
| `EXPRESSION` | `'Y'` = calculated/virtual column (no direct table column) |
| `COVERBOOL` | `'Y'` = this is the "cover" column (primary display field) |
| `TRIGGERS` | `'Y'` = column has triggers attached |
| `JCNAME` | Join column name in the joined table (for FK join columns) |
| `JTNAME` | Join table name (for FK join columns) |
| `IDCOLUMNE` | Join instance index — `'0'` = first join, `'1'` = second join to same table |
| `COLTITLE` | Short column label (Hebrew) |
| `TITLE` | Longer column title override (Hebrew), or `null` to use `COLTITLE` |
| `INTERNATIONAL` | `'I'` = foreign-currency column |

**Key distinctions:**
- A column where `EXPRESSION = 'Y'` and `CNAME = null` is a virtual/calculated field — you can read it in the form but cannot UPDATE it directly on the table.
- `NAME` is what you use in trigger code (`:$.PARTNAME`, `:$.TQUANT`). `CNAME`/`TNAME` tell you the underlying table column for direct SQL.
- `JCNAME`/`JTNAME` non-null means this column is a join — it reads from a related table. The hidden integer ID column for the same join will have `JCNAME` = join column and `JTNAME` = join table.

#### FLINK_SUBFORM fields (subforms)

| Field | Meaning |
|-------|---------|
| `FNAME` | **Subform name** — use this to query the subform with EFORM |
| `TITLE` | Display title of the subform tab (Hebrew) |
| `APOS` | Tab position / display order |
| `AUTOSHOW` | `'A'` = opens automatically, `'N'` = manual, `null` = default |
| `MODULENAME` | Module the subform belongs to |
| `SONFORM` | Internal numeric form ID |

---

### Inspect a subform the same way

Once you have a subform name from `FLINK_SUBFORM` (field `FNAME`), query it identically:

```
GET {baseURL}/EFORM(ENAME='{FNAME}',TYPE='F')?$expand=FCLMN_SUBFORM,FLINK_SUBFORM
```

For example, to inspect `SERNTRANS` found in the TRANSORDER_P subform list:
```
GET {baseURL}/EFORM(ENAME='SERNTRANS',TYPE='F')?$expand=FCLMN_SUBFORM,FLINK_SUBFORM
```

---

### Fetch full service metadata (all forms)

Returns an XML document listing every EntityType (form) and its Properties (columns) and NavigationProperties (subforms):

```
GET {baseURL}/$metadata
Accept: application/xml
```

This is large — prefer the targeted EFORM query above when you know the form name.

---

### When to use this

- Before writing a trigger, confirm the exact column name, type, and whether it is read-only or mandatory.
- Verify a join column's target form (`JOINTO`) before writing buffer-trigger logic.
- Discover all subforms of a form when planning which sub-level triggers to add.
- Check that a form name exists and is of type `'F'` (form) vs `'P'` (procedure) before referencing it in code.

---

## 3. Form triggers

For cursor loops and temp tables used inside trigger code, see the `priority-sql` skill §6 and §8. For trigger naming conventions and execution order, see the `priority-sql` skill §11.

Ref: [Form Triggers](https://prioritysoftware.github.io/sdk/Form-Triggers)
| [Creating Your Own Triggers](https://prioritysoftware.github.io/sdk/Creating-your-Triggers)

---

### Trigger types

| Category | Trigger | When it fires | Purpose |
|----------|---------|---------------|---------|
| **Column** | `CHECK-FIELD` | On exit from a column | Validate the entered value; block if invalid |
| **Column** | `POST-FIELD` | After a column passes CHECK-FIELD | Fill in derived values based on the column's value |
| **Column** | `CHOOSE-FIELD` | When the user opens the pick list | Define the list of selectable values |
| **Column** | `SEARCH-FIELD` | When the choose list is empty or too large | Provide a searchable fallback to the choose list |
| **Column** | `SEARCH-ALL-FIELD` | Alongside SEARCH-FIELD | Enable simultaneous multi-criteria search |
| **Row** | `PRE-INSERT` | Before a new record is saved | Validate or set defaults before insert |
| **Row** | `POST-INSERT` | After a new record is saved | Perform follow-up actions after insert |
| **Row** | `PRE-UPDATE` | Before a changed record is saved | Validate before update; `:FIELD` gives old value |
| **Row** | `POST-UPDATE` | After a changed record is saved | Perform follow-up actions after update |
| **Row** | `PRE-DELETE` | Before a record is deleted | Block or clean up before deletion |
| **Row** | `POST-DELETE` | After a record is deleted | Perform follow-up actions after deletion |
| **Form** | `PRE-FORM` | Before the form opens | Initialize variables, auto-retrieve records, set privileges |
| **Form** | `POST-FORM` | On form exit (see note) | Update parent form values based on sub-level changes |

---

### Execution order

1. `CHECK-FIELD` fires before `POST-FIELD` for the same column.
2. Built-in `CHECK-FIELD` triggers fire before user-designed ones.
3. Built-in `POST-FIELD` triggers fire before user-designed ones.
4. `PRE-` triggers fire before their corresponding `POST-` trigger.
5. Among triggers of the same type, execution order is alphabetical — name
   custom triggers accordingly (see naming conventions below).

**If a `CHECK-FIELD` is discontinued** (via `ERRMSG` or `END`), all
corresponding `POST-FIELD` triggers — both built-in and custom — are skipped.

---

### Activation rule

Triggers do not fire unless the user has made a change in the relevant
column, row, or form. The sole exception is `PRE-FORM`, which fires
automatically whenever the form opens.

---

### Naming custom triggers

- Must include the 4-letter customer identifier as a prefix or postfix.
- Must contain the key string for the trigger type (e.g. `CHECK-`, `POST-`,
  `-FIELD`, `-INSERT`, `-UPDATE`).
- Only alphanumeric characters, underscores, and hyphens; must start with a letter.

**Execution order and naming strategy:**

The SDK states that custom triggers sort alphabetically relative to standard
triggers. In practice this is unreliable — a custom trigger with an
alphabetically early name has been observed firing before standard triggers
regardless. Follow this convention:

| Intent | Convention | Example |
|--------|-----------|---------|
| Fire after standard triggers (default) | Postfix the customer identifier | `CHECK-FIELD_PRIV` |
| Fire before standard triggers | Prefix the customer identifier | `PRIV_CHECK-FIELD` |
| Fire absolutely last | Add `_ZZZZ` suffix | `CHECK-FIELD_PRIV_ZZZZ` |

---

### Customization restrictions

`SEARCH-FIELD` and `SEARCH-ALL-FIELD` cannot be customized — only the
standard system versions exist. All other trigger types support user-designed
versions.

---

### CHECK-FIELD specifics

- Error message numbers in `CHECK-FIELD` triggers must be **> 500**.
- If a `CHECK-FIELD` is discontinued, its `POST-FIELD` triggers are skipped
  (see execution order above).

---

### POST-FIELD cascade behavior

When a `POST-FIELD` trigger changes the value of another form column, that
other column's `POST-FIELD` fires automatically — but its `CHECK-FIELD` does
**not**. This is easy to overlook and can cause unexpected side-effects when
the changed column has its own validation logic.

---

### CHOOSE-FIELD variants

See §1 for the full column creation workflow. The trigger itself supports
several forms:

**Standard SQL query** — first column is the display description (max 64
chars), second is the value inserted into the field, optional third column
controls sort order:
```sql
SELECT FNCCLASSDES, FNCCLASSCODE, ITOA(SORT, 3)
FROM   PRIV_FNCCLASS
WHERE  INACTIVE <> 'Y'
ORDER BY 3, 1
```

**Form-message list** — messages defined on the form, structured as
`Value, Description`:
```sql
/* uses the form's message table instead of a SQL query */
```

**Union CHOOSE** — multiple `SELECT` blocks combined; results auto-sorted
by the first column:
```sql
SELECT DES, CODE FROM TABLE1
UNION
SELECT DES, CODE FROM TABLE2
```

**`/* AND STOP */`** — executes each `SELECT` in sequence and stops at the
first one that returns results:
```sql
SELECT DES, CODE FROM TABLE1 /* AND STOP */
SELECT DES, CODE FROM TABLE2 /* AND STOP */
```

**`/* NO SORT */`** — preserves the query's own order instead of sorting by
the first column:
```sql
SELECT DES, CODE FROM TABLE1 /* NO SORT */
```

**`MCHOOSE-FIELD`** — variant that allows selecting multiple values at once.

**Fallback behavior** — if the choose list is empty or exceeds the
`CHOOSEROWS` system constant, a `SEARCH-FIELD` trigger activates instead
(if one is defined for the column).

---

### Combined triggers

A combined trigger fires on multiple row events, avoiding duplicated logic
across separate triggers. Example: `PRE-INSERT-UPDATE_PRIV` fires before
both insert and update.

Event names are often abbreviated (`INS`, `UPD`, `DEL`) to stay within the
maximum trigger name length — this is especially necessary for combined
triggers, which are already long before adding the customer pre/postfix.

**Combined triggers cannot contain cursors — directly or via `#INCLUDE`.**
This restriction applies only to combined triggers; single-event `INSERT`
or `UPDATE` triggers are not affected.

---

### PRE-FORM and POST-FORM

**PRE-FORM** fires before the form opens. Common uses:
- Variable initialization
- Conditional warnings or errors before entry
- Auto-retrieving records (`:KEYSTROKES = '{Exit}';`)
- Deactivating data privileges

**POST-FORM** fires on exit, but only when the user has made at least one
change. Common use: updating values in a parent form based on sub-level
changes.

To make `POST-FORM` fire unconditionally on exit regardless of changes,
assign `:ACTIVATE_POST_FORM = 'Y'` in a `PRE-FORM` trigger.

Cross-ref the `priority-sql-ref` skill §3 — *PRE-FORM automation* — for the
full list of related system variables (`:KEYSTROKES`, `:PREFORMQUERY`,
`:ACTIVATE_POST_FORM`, etc.).
