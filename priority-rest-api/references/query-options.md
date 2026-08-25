# Query options

## `$filter`

Documented operators — **these six and nothing else**: `eq`, `ne`, `gt`, `ge`,
`lt`, `le`. Combine with `and` / `or`, group with parentheses.

```
GET serviceRoot/LOGPART?$filter=TYPE eq 'P' and LASTPRICE gt 200
GET serviceRoot/LOGPART?$filter=(TYPE eq 'P' or TYPE eq 'R') and LASTPRICE gt 500
```

Standard OData constructs Priority's documentation **does not** cover —
`contains()` / `startswith()` / `endswith()`, `$count`, `$search`, `not`,
arithmetic operators, server-driven paging via `@odata.nextLink` — should be
treated as unsupported until proven otherwise against the specific
environment. Do not design an integration around them on the assumption that
"OData supports it".

Quote string literals with single quotes. A literal single quote is escaped by
doubling it (`'O''Brien'`) per the OData spec; Priority's docs are silent on
this, so verify against the target system.

## Filtering on dates — the classic trap

Spaces become `%20` and `+` must become `%2B`. The classic failure is writing
`%20` immediately before a year: the escape and the year's leading `20` blur
together, and `%202018` gets mistyped as `%2018` — which parses as the space
plus `18`, silently shifting the date by two millennia:

```
WRONG:   ?$filter=STATUSDATE%20ge%2018-02-23T09:59:00+02:00     /* "ge 18-02-23" */
RIGHT:   ?$filter=STATUSDATE%20ge%202018-02-23T09:59:00%2B02:00
```

If a date filter returns nonsense, check the encoding before checking the data.

## `$since` (20.0+) — changed records only

```
GET serviceRoot/ORDERS?$since=2020-01-01T07:25:00Z&$expand=ORDERITEMS_SUBFORM
```

The right primitive for incremental sync, with three constraints: it works
**only on entities with business process management (BPM)** applied — i.e.
documents, not a general change feed; use **UTC with the `Z` suffix**, since an
offset is DST-dependent and needs hand-adjusting twice a year; and combined
with `$expand` the change detection stays on the parent, returning subform rows
of parents that changed.

## `$orderby`, `$top`, `$skip`, `$select`, and combining

Top-level options are separated by `&`; options **inside** an `$expand` are
separated by `;`:

```
GET serviceRoot/FAMILY_LOG?$orderby=FAMILYDESC desc
GET serviceRoot/FAMILY_LOG?$top=3&$skip=1        /* page 2, size 3; $skip 19.1+ */
GET serviceRoot/ORDERS?$filter=CUSTNAME eq '1011'&$select=CUSTNAME,CDES,ORDNAME&$expand=ORDERITEMS_SUBFORM($filter=PRICE gt 3;$select=PARTNAME,TQUANT,PRICE;$expand=ORDISTATUSLOG_SUBFORM)
```

`$top` + `$skip` is the pagination mechanism — there is no documented
`@odata.nextLink`. Always pair it with a **stable `$orderby`**; without a
deterministic sort, paging repeats and drops rows. `$select` matters more than
it looks: the default is *every* field on the form.

Two gotchas when combining:

- **IIS or a security policy may strip the `;`**, producing a 400 on a query
  that worked before you added a second option inside the `$expand`. Encode it
  as `%3B`.
- **When `$expand`ing a subform with composite keys, the parent's `$select`
  must include every key field of the parent form** — otherwise the subform
  cannot be addressed and the request fails.
