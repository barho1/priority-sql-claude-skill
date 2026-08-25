## 3. Variable scoping

Three types of variables — no block-level isolation within a form context:

| Type | Syntax | Scope |
|------|--------|-------|
| Form field | `:$.COLNAME` or `:FORMNAME.COLNAME` | Current form row. Subforms use `:$$.COL`, `:$$$.COL` etc. |
| Local variable | `:varname` | Visible across all triggers in the form and all subforms. Internally namespaced as `:_company.varname`. |
| Global variable | `:GLOBAL.varname` | Spans all companies in multi-company contexts. |

**`:FIELDNAME` (colon-prefix on a form field) in an UPDATE trigger** returns the value *before* the current change. Use this in PRE-UPDATE checks to inspect the old value.
```sql
/* Block editing a row that already had a price, OR a row that now has a price */
ERRMSG 1 WHERE :QPRICE > 0 OR QPRICE > 0;
/*              ^^^^^^^^^^       ^^^^^^^^  */
/*              old value        new value */
```

**`:$1.FIELDNAME`** — the pre-change value of a form field, used in
buffer triggers and POST-UPDATE triggers to compare the new value
(`:$.FIELDNAME`) against the previous one. This is the standard pattern
for detecting whether a specific field actually changed:

```sql
/* Skip if the FK column wasn't modified */
GOTO 9999 WHERE :$.PRIV_FNCCLASS = :$1.PRIV_FNCCLASS;
```

When multiple fields are tracked by the same buffer trigger, chain the
conditions with `AND` — only skip if *all* tracked fields are unchanged.

---

