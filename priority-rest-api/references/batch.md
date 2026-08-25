# `$batch` (19.1+)

Combines multiple operations into one HTTP call.

**Each item's `url` must be a full URL**, even though the outer POST already
went to that service root. Item URLs come in exactly two forms:

- the full service-root-prefixed URL —
  `https://<PRIORITY-SERVER>/odata/Priority/tabula.ini/<COMPANY>/MY_LOADFORM`
- a `$<id>` back-reference to an entity created earlier in the same batch —
  `$1/ORDERITEMS_SUBFORM`

A bare entity-set name (`"url": "MY_LOADFORM"`) is **not** valid.

Every item repeats the same headers, written `…H…` in the examples below:

```json
"headers": {
  "content-type": "application/json; odata.metadata=minimal; odata.streaming=true; odata.continue-on-error=false",
  "odata-version": "4.0"
}
```

## Independent records — the bulk-load shape

When operations are independent (N creates into one form, no parent to
reference), drop `dependsOn` and let them run as a flat list:

```http
POST https://<PRIORITY-SERVER>/odata/Priority/tabula.ini/<COMPANY>/$batch
Authorization: Basic <BASE64_USER_PASSWORD>
Content-Type: application/json

{
  "requests": [
    { "id": "1", "method": "POST", "headers": { …H… },
      "url": "https://<PRIORITY-SERVER>/odata/Priority/tabula.ini/<COMPANY>/MY_LOADFORM",
      "body": { "CODE": "0001", "DOCNAME": "2026000016LC", "AMOUNT": 40000.00 } },

    { "id": "2", "method": "POST", "headers": { …H… },
      "url": "https://<PRIORITY-SERVER>/odata/Priority/tabula.ini/<COMPANY>/MY_LOADFORM",
      "body": { "CODE": "0037", "DOCNAME": "4002258778", "AMOUNT": 60000.00 } }
  ]
}
```

One HTTP call instead of N against the 100-calls-per-minute throttle, with a
per-`id` status so you can tell exactly which rows failed.
`odata.continue-on-error=false` stops at the first failure — but earlier
successful writes are **not** rolled back.

## Dependent records — header then lines

`dependsOn` sequences operations; `$<id>` in a later `url` resolves to the
entity that request created. This is how you create a document and its lines as
separate, individually-diagnosable operations:

```json
{
  "requests": [
    { "id": "1", "method": "POST", "headers": { …H… },
      "url": "https://…/usdemo/ORDERS",
      "body": { "CUSTNAME": "T000001" } },

    { "id": "2", "method": "POST", "headers": { …H… }, "dependsOn": ["1"],
      "url": "$1/ORDERITEMS_SUBFORM",
      "body": { "PARTNAME": "MS0001", "DUEDATE": "2022-08-01T00:00:00+03:00" } }
  ]
}
```

Each response carries its `id`, `status`, a `location` header pointing at the
created resource, and the body — so a `responses` array of
`{ "id", "status", "headers": { "location" }, "body" }` objects, which is what
makes per-line error attribution possible.

## Rules and limits

- **Maximum 100 operations per batch.** (Docs briefly claimed 1,000/10,000 for
  versions before 21.1; 100 is the corrected figure.)
- **No rollback** — of the whole batch or of an atomicity group. Once Priority
  writes a change it cannot be undone, only overwritten. Never assume
  batch = transaction; design compensating actions yourself.
- From **22.1** the response format matches the request format (JSON in → JSON
  out); before that it was always `multipart/mixed`. Force the old format with
  `Accept: multipart/mixed`.

**Batch vs. nested POST:** reach for `$batch` when you need per-line error
attribution, or are mixing verbs and entities in one round trip. Nesting
children as an array property on the parent's create request is simpler when
the whole document succeeds or fails as a unit.
