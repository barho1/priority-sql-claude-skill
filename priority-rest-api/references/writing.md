# Creating, updating and deleting

Requires Priority 17.2+. `PUT` is **not** supported — it was removed from the
documentation in 22.0. Use `PATCH`.

```http
POST serviceRoot/FAMILY_LOG
OData-Version: 4.0
Content-Type: application/json;odata.metadata=minimal
Accept: application/json

{ "FAMILYNAME": "765", "FAMILYDESC": "My OData Family" }
```

The response is the created entity with **every** field the form computed —
defaults, joined descriptions, and the generated auto-unique key
(`"FAMILY": 26`). Read the generated document number (`ORDNAME`, `IVNUM`) out
of the response; do not try to predict it.

## Children

Navigate to the parent by key, then POST to the subform collection. The
response carries the assigned line number (`"KLINE": 1`) plus everything the
form filled in (`PDES`, `PRICE`, …):

```http
POST serviceRoot/ORDERS('SO18000002')/ORDERITEMS_SUBFORM

{ "PARTNAME": "TR0001", "TQUANT": 5, "DUEDATE": "2018-03-15T00:00:00+02:00" }
```

Or create parent and children in one request, passing the subform as an array
property:

```http
POST serviceRoot/ORDERS

{ "CUSTNAME": "007",
  "ORDERITEMS_SUBFORM": [ { "PARTNAME": "111-001", "DUEDATE": "2016-08-01T00:00:00+03:00" },
                          { "PARTNAME": "111-002", "DUEDATE": "2016-08-01T00:00:00+03:00" } ] }
```

From **21.1** the response contains both parent and created children. The
trade-off against `$batch`: one request is simpler, but if one line fails you
get a single error and less certainty which line caused it. When that matters,
split the work into separate `$batch` operations sequenced with `dependsOn`,
which gives per-line error attribution. From inside Priority SQL itself,
`EXECUTE INTERFACE` / `GENERALLOAD` is the in-system alternative to REST for
document loading — see the `priority-sql` skill.

## Update and delete

```http
PATCH serviceRoot/FAMILY_LOG('765')                     { "FAMILYDESC": "Updated" }
PATCH serviceRoot/ORDERS('SO18000002')/ORDERITEMS_SUBFORM(1)   { "TQUANT": 10 }

DELETE serviceRoot/FAMILY_LOG('765')
DELETE serviceRoot/ORDERS('SO18000002')/ORDERITEMS_SUBFORM(1)
```

**You cannot address a record by its auto-unique key in a PATCH** — read-only
from 21.1. Use the unique key. From 21.1 the response to a related-entity
update also includes the parent entity. Composite keys apply throughout.

## Attachments and text forms

### Attaching a file (21.0+)

POST a data URI into the attachments subform; allowed types are governed by the
MIME types the application server permits. From **22.0** an explicit `SUFFIX`
overrides MIME-type detection — **include the period**:

```http
POST serviceRoot/ORDERS('SO21000113')/EXTFILES_SUBFORM

{
    "EXTFILEDES": "myorder",
    "EXTFILENAME": "data:application/vnd.openxmlformats-…;base64,UEsDBBQAAAAIAMhJ…",
    "SUFFIX": ".docx"
}
```

To read attachments back afterward, `GET` the parent record with
`$expand=EXTFILES_SUBFORM` — the file comes back as the same kind of data URI.

### Writing text (20.0+)

Text subforms take an object with three properties: `TEXT` (HTML including
tags), `APPEND` (`true` = append, `false` = replace) and `SIGNATURE` (`true`
appends the user's signature).

```http
PATCH serviceRoot/ORDERS('SO20000422')/ORDERSTEXT_SUBFORM

{ "TEXT": "This is my order. <br> There are many like it.", "APPEND": true, "SIGNATURE": false }
```

- **`PATCH` and `POST` behave identically here** — `APPEND` decides replace vs.
  append, not the verb.
- **Do not use square brackets** to address text forms. Required before 20.0;
  must be removed from older code.
- For RTL languages (Hebrew) include explicit `dir="rtl"` tags, or it renders
  wrong.
- Embed images as a data URL inside the text:
  `<img src="data:image/png;base64,iVBORw0KGgo…" alt="">`
- **Text-only forms** (`:$.NOHTML.T = 1`) return no HTML tags, use `\n` for
  line breaks, take plain text only, and always treat `SIGNATURE` as `false`.
