## 5. Creating a form programmatically (EFORM)

A form is a record in the standard **EFORM** form, so a new form is created by
loading into EFORM and its sub-levels — not by hand in the Form Generator. Code
that ends in a "now configure this in the Form Generator" comment has not
finished the job; the whole form is loadable.

Ground EFORM before writing (`priority_get_entity_fields EFORM`, or the REST
endpoint described in the form metadata reference) — the field set is what you
are populating.

**Header (EFORM):**

| Field | Purpose |
|-------|---------|
| `ENAME` | Form name. Equals the base table name, carries the customer prefix, and must begin with a letter |
| `TITLE` / `EDES` | Form titles |
| `TNAME` | The base table — your own, never a standard one |
| `MODULENAME` | Internal Development, for custom forms |
| `TYPE` | `'F'` for a form |
| `APPEND` / `INS` / `DEL` | Row-action flags. Clear them to make a query-only form or to block deletion |

**Columns (EFORM → FCLMN_SUBFORM),** one row per column:

| Field | Purpose |
|-------|---------|
| `NAME`, `TNAME` | Column and its table |
| `TYPE` / `WIDTH` | Column type and display width |
| `POS` | Display order |
| `HIDEBOOL` | `'Y'` hides the column — e.g. the auto-unique key |
| `READONLY` | `'R'` read-only, `'M'` read-only after insert |
| `BOOLEAN` | `'Y'` for a flag column |
| `COVERBOOL` | `'Y'` marks the cover field |
| `TITLE` | Override the column's inherited title |

**Sub-levels (EFORM → FLINK_SUBFORM):** one row per link from an upper-level
form to a sub-level form.

### Loading it

Load **through the form interface**, so the load routes through the form and
its logic fires. This is also what keeps a form-creation script inside the
no-direct-write-to-standard-table rule (see the form triggers reference).

For a runnable `.pq`, prefer a **dynamic interface** (v21.0+) — no predefined
interface to set up and no generic-column mapping, which is what makes it worth
preferring:

```sql
EXECUTE INTERFACE 'EFORM', :MSG, '-form', '-i', '-J', '-f', :FILE,
                  '-ignorewrn', '-noskip';
```

The payload's hierarchy mirrors the form (`EFORM` › `FCLMN_SUBFORM`) and its
keys are the real field `NAME`s. See the standard
`ERRMSGS` check that follows `EXECUTE INTERFACE`.

Alternatives: REST/OData record creation for a live system, or a predefined
`GENERALLOAD` interface if one already exists — see the advanced patterns
reference for building that hierarchy.

### Design rules

- A form's own base table only.
- Form message numbers > 500; custom join and column IDs > 5.
- Never add a standard form as a sub-level of a custom one.
- Capacities: 600 columns, 100 sub-levels.

Ref: [Form Generator](https://prioritysoftware.github.io/sdk/Forms-Generator),
SDK chapters 03 (customization rules) and 07 (forms).
