## 3. Form triggers

For cursor loops and temp tables used inside trigger code, see the cursor loop and temp-table references.

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

Triggers of the same type fire in alphabetical order by name — standard and
custom triggers alike, no exceptions. Name custom triggers accordingly. SDK
example: to fire a custom trigger after a standard `POST-INSERT` trigger,
name it `POST-INSERT_AXXX` (postfix) or `ZXXX_POST-INSERT` (prefix), where
`XXX` is the customer prefix.

Ref: [Creating Your Own Triggers](https://prioritysoftware.github.io/sdk/Creating-your-Triggers)

---

### Customization restrictions

`SEARCH-FIELD` and `SEARCH-ALL-FIELD` cannot be customized — only the
standard system versions exist. All other trigger types support user-designed
versions.

---

### Custom error message numbers

Custom message numbers in forms must always be **> 500**.

Ref: [Error and Warning Messages](https://prioritysoftware.github.io/sdk/Errors-and-Warnings)

---

### CHECK-FIELD specifics

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

See the system functions and variables reference — *PRE-FORM automation* — for the
full list of related system variables (`:KEYSTROKES`, `:PREFORMQUERY`,
`:ACTIVATE_POST_FORM`, etc.).

---

