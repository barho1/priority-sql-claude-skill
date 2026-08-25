## 2. Inspecting form structure via the Priority REST API

When writing triggers or business rules it is often necessary to know:
- what columns a form has (names, types, join info)
- what subforms hang off it

Use the **EFORM** endpoint with `$expand` to retrieve this in one call. For the
REST/OData API itself — authentication, query options, writing data, `$batch` —
see the `priority-rest-api` skill.

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

