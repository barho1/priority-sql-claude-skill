## 1. CHOOSE-FIELD column — full creation workflow

A CHOOSE-FIELD column presents the user with a picklist of predefined values.
Creating one is a multi-step process involving a values table, a form, a
foreign-key column, and (optionally) a buffer trigger for expansion tables.

For cursor and temp-table patterns used in trigger code, see the cursor loop and temp-table references.

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

For FOR TABLE INSERT as a standalone reference, see the DBI reference.

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

**PRE-FORM trigger** — retrieves all records when the user enters the form
directly (standard convenience pattern). `*` is a wildcard query and `{Exit}`
executes it:

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
- The `INSERT` is safe to run even when the row already exists — but not
  because Priority skips it. The `INSERT` **fails** on the duplicate key and
  sets `:RETVAL = 0`; a failed statement does not halt the trigger, so
  execution carries on to the `UPDATE`. It works by tolerated failure, not by
  upsert semantics. Do not add a `:RETVAL` check after this `INSERT` — it
  would fire on every row that already exists, which is the normal case.
- The `UPDATE` must reference every expansion field being managed.

For ENTMESSAGE used in trigger messages, see the ENTMESSAGE reference.

---

