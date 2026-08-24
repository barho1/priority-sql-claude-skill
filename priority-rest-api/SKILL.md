---
name: priority-rest-api
description: >
  Priority ERP REST/OData API — calling into Priority over HTTP. Service root
  URL structure, authentication (Basic, Personal Access Token, OAuth2), the
  form→EntityType / field→Property / subform→NavigationProperty mapping,
  discovering the model ($metadata, GetMetadataFor, ClearEntityMetadata),
  reading data (entity by key, composite keys, $expand, attachments, text
  forms), query options ($filter, $select, $orderby, $top, $skip, $since),
  writing data (POST/PATCH/DELETE, nested children, read-only auto-unique
  keys), $batch with dependsOn, error payloads, X-App-Trace debugging, and
  cloud throttling. Use when integrating an external system with Priority,
  querying or loading Priority data over HTTP, or debugging an OData request.
  Context cues: serviceRoot, odata/Priority, _SUBFORM, $expand, $filter,
  $batch, InterfaceErrors, 429. For calling *out* from Priority SQL to an
  external service, see `priority-sql-integrations` (WSCLIENT). For form and
  column metadata via EFORM, see `priority-sql-forms`.
---

# Priority ERP — REST / OData API

Ref: [REST API documentation](https://prioritysoftware.github.io/restapi/)

**Direction matters.** This skill covers traffic *into* Priority. For traffic
*out* — Priority SQL calling an external web service — use `WSCLIENT`, see the
`priority-sql-integrations` skill.

The API is a thin wrapper around Priority **forms**, not around tables. Every
request runs the form's triggers, validations and business rules, exactly as if
a user typed the data in the UI — so a POST that "should" work can fail because
a CHECK-FIELD trigger rejected it, and the error text you get back is the
trigger's `ERRMSG`. Data modification requires **Priority 17.2+**.

---

## 1. Service root and response basics

```
https://{host}[/ui]/odata/Priority/{ini-file}[,{language}]/{company}

https://www.eshbelsaas.com/ui/odata/Priority/tabmob.ini/usdemo
```

| Segment | Meaning |
|---------|---------|
| `{host}` | Server / tenant host. Cloud tenants may include a `/ui` segment |
| `{ini-file}` | The `tabula.ini` variant for the environment (`tabula.ini`, `tabmob.ini`, …) |
| `,{language}` | Optional language code appended to the ini filename (18.2+), e.g. `tabula.ini,3`. Sets the language of returned error/warning messages |
| `{company}` | Priority company/database name (`usdemo`, `test`, …) |

The administrator can output the correct service root with the **Send Program
Activation Link** program. `GET serviceRoot/` lists every exposed entity set
plus the `$metadata` link. Demo-environment credentials are in the
`priority-sql-forms` skill §2.

### Request / response format

- JSON by default, both directions. Successful reads return `200`.
- **Requests are case sensitive.** Names are usually UPPERCASE, but not always
  (`DOCUMENTS_p`). Match `$metadata` exactly — never guess casing.
- Decimals must use `.` as separator (22.0+), in URL and body alike.
- Dates return as `DateTimeOffset`: `YYYY-MM-DDTHH:MM:SS+HH:MM`.
- Blank fields come back as `null` or `""`, not omitted. Responses cap at 350 MB.

Priority-specific status codes: **`201`** for a successful `POST` (Priority's
own table mislabels it "no content — response to a DELETE"); **`409`** when
POSTing a record that already exists; **`429`** when throttled (§11). `400`,
`404` and `500` behave conventionally.

### Result-count cap

`$top` cannot exceed the system cap: **`MAXAPILINES`** (25.1+, default 2,000
records), or **`MAXFORMLINES`** before 25.1. Raising it hurts performance —
paginate with `$top`/`$skip` instead (§6). A query returning a suspiciously
round row count has hit the cap.

### Timezone caveat (21.0+, potentially breaking)

From 21.0 the timezone can be set per company via the `TZSERVER` constant. With
`TZSERVER=1` *and* a company timezone set, dates use the company's timezone;
otherwise they use the server's. Before 21.0 it was always the server's.
Confirm with the administrator before doing date arithmetic on API output.

### Data privileges

**Row-level data-privilege restrictions that apply in the Priority UI are not
applied to REST API requests.** Field-level permissions *are* respected from
22.1 onward. Do not treat the API user as sandboxed — scope its form
permissions deliberately.

---

## 2. Authentication

**Basic** (default) — standard HTTP Basic header on every request; requests
without it are denied. The username is the **API User Name** field in the
*Personnel File* form, which is a *different value* from the user's normal
Priority login. Unavailable while External ID access is enabled.

**Personal Access Token** (19.1+) — the documented choice for server-to-server
integrations. Admin defines tokens in the **REST Interface Access Tokens**
form; several can belong to one user and be revoked independently. Sent as
*Basic* auth with a quirk worth memorizing:

```
username = the PAT value
password = the literal string "PAT"

Authorization: Basic <base64(THETOKENVALUE:PAT)>
```

**OAuth2 / External ID** — for end-user browser and mobile apps. Requires the
External ID module; only the **Authorization Code flow with PKCE** is
supported, scope `openid rest_api`, endpoints under
`https://{PRIORITY_DOMAIN}/accounts/connect/…` with OIDC discovery at
`/accounts/.well-known/openid-configuration`. `PRIORITY_DOMAIN` is everything
before `/odata` in the service root. Register the app under *System Management
→ System Maintenance → Users → Manage IDs Externally → External Applications*.
Verify with PAT auth first, then swap — that isolates connectivity problems
from flow problems. Full walkthrough:
[Authenticating with the REST API](https://prioritysoftware.github.io/restapi/authenticate/).

```
Authorization: Bearer <access_token>
```

**Per-application licensing** (18.3+) — under a per-app license every request
must carry `X-App-Id` and `X-App-Key`; without them the request falls back to
generic API licensing.

---

## 3. How Priority maps onto OData

| OData | Priority |
|-------|----------|
| `EntityType` / `EntitySet` | **Form** |
| `Property` | **Field in a form** |
| `NavigationProperty` | **Subform** |

Consequences worth stating explicitly:

- You address **forms**, never tables. `ORDERS` is the sales-order form, not
  the `ORD` table. A column on the table but not on the form is unreachable —
  add it to the form first.
- Every write executes the form's triggers, so business logic, defaults and
  validations all apply, and errors surface as trigger messages (§10).
- Subforms are reached by navigation, not by joining.

Property types are `Edm.String` (`"A string"`), `Edm.Int64` (`42`),
`Edm.Decimal` (`42.00`) and `Edm.DateTimeOffset` (`2017-04-16`) — quote
strings, never quote numbers.

### Navigation property cardinality

```xml
<NavigationProperty Name="GENCUSTNOTES_SUBFORM" Type="Collection(Priority.OData.GENCUSTNOTES)" ContainsTarget="true" />
<NavigationProperty Name="SHIPTO2_SUBFORM"      Type="Priority.OData.SHIPTO2"                  ContainsTarget="true" />
```

A `Collection(...)` navigation property returns a **JSON array**; a
non-collection one returns a **single object or `null`**. Code that assumes
every `_SUBFORM` is an array breaks on the singletons (`SHIPTO2_SUBFORM`, text
subforms).

### Keys

Priority has two different "keys" and confusing them is the most common write
failure:

- The **unique key** (`ORDNAME`, `CUSTNAME`, `FAMILYNAME`) — what URLs address.
- The **auto-unique key** (`ORD`, `FAMILY`, `PART`) — an internal integer.
  From 21.1 it is annotated read-only and **cannot address a record in `PATCH`
  or `POST`**, nor be changed.

Which properties form the key is declared in `$metadata` under `<Key>`.

---

## 4. Discovering the model

Never write an integration against guessed field names.

```
GET serviceRoot/$metadata                              /* whole service, large */
GET serviceRoot/GetMetadataFor(entity='CUSTOMERS')     /* one entity, 25.0+    */
GET serviceRoot/GetPriorityVersion()   → "22.0-20.0.0.119"   /* version-server IP */
GET serviceRoot/GetLoginName           → "apidemo"
```

`$metadata` is EDMX listing every EntityType with its Properties and
NavigationProperties. On a full system it is slow to generate and download —
prefer `GetMetadataFor` (25.0+) when you know the entity. Two constraints:
it takes **top-level entities only** (`ORDERS` works, `ORDERITEMS` does not —
subform metadata comes with its parent), and if no request has ever hit that
entity its metadata may not be prepared, returning empty; warm it with
`GET serviceRoot/CUSTOMERS?$top=1` first. On-premises it needs a BIN version
from 29 June 2025 or later plus an application-server reinstall.

From **25.1** metadata carries a `Priority.OData.Mandatory` annotation
(`Bool="true"`) on required fields — use it to build the required-field set for
a create request instead of discovering it through 400s.

`GetPriorityVersion()` (22.0+) is the correct way to feature-gate client code
rather than assuming. `GetLoginName` resolves the effective Priority user when
authenticating through an external IdP.

### Refreshing metadata after customization (22.0+)

Fields added by private customizations **do not appear in the API** until that
form's REST metadata is rebuilt. If a new custom column is invisible or
rejected as unknown, this is almost always why.

```http
POST serviceRoot/ClearEntityMetadata

{ "Entity": "ORDERS" }
```

One entity per request (send several, individually or batched). Name the
**parent** — subforms are included with it. Omitting the body clears *all*
entities. Metadata rebuilds on the next request to that entity, so the
following call is slower. Available in all environments, not just Priority
Cloud.

For form *design* questions — which columns are hidden, read-only, calculated
or joined, and which subforms hang off a form — query `EFORM` rather than
`$metadata` (see the `priority-sql-forms` skill §2):

```
GET serviceRoot/EFORM(ENAME='ORDERS',TYPE='F')?$expand=FCLMN_SUBFORM,FLINK_SUBFORM
```

---

## 5. Reading data

```
GET serviceRoot/FAMILY_LOG                              /* collection          */
GET serviceRoot/LOGPART('111-012')                      /* single entity       */
GET serviceRoot/AINVOICES(IVNUM='T9696',IVTYPE='A',DEBIT='D')   /* composite key */
GET serviceRoot/FAMILY_LOG('001')/FAMILY_LOGPART_SUBFORM        /* navigate    */
```

A collection always returns a `value` array, even for zero or one match:
```json
{ "@odata.context": "serviceRoot/$metadata#FAMILY_LOG", "value": [ … ] }
```
A single entity returns the object itself, with `@odata.context` ending
`/$entity`.

Key segments are parenthesized because they may be composite; separate the
parts with commas, naming each property.

### Expanding subforms inline (18.1+)

```
GET serviceRoot/ORDERS('99100042')?$expand=ORDERITEMS_SUBFORM
GET serviceRoot/ORDERS('99100042')?$expand=ORDERITEMS_SUBFORM,ORDERSTEXT_SUBFORM
GET serviceRoot/ORDERS('SO20000422')?$expand=ORDERITEMS_SUBFORM($expand=ORDERITEMSTEXT_SUBFORM)
```

Nesting is unlimited in principle — subform of subform of subform. Prefer one
expanded request over N+1 round trips; the cloud throttle (§11) counts calls,
not rows.

### Attachments (21.0+, potentially breaking)

```
GET serviceRoot/ORDERS('SO21000113')?$select=CUSTNAME,ORDNAME&$expand=EXTFILES_SUBFORM
```
```json
"EXTFILES_SUBFORM": [
  { "EXTFILEDES": "docx1", "EXTFILENUM": 3, "SUFFIX": "docx", "FILESIZE": 53803,
    "EXTFILENAME": "data:application/vnd.openxmlformats-…;base64,UEsDBBQ…" }
]
```

The file arrives as a **data URI**, not a server path — that was the breaking
change in 21.0, and it applies to images too. Watch the 350 MB cap when
expanding attachments across many records.

### Text (20.0+)

```
GET serviceRoot/ORDERS('SO20000422')/ORDERSTEXT_SUBFORM
```
```json
{ "TEXT": "<style>…</style><p dir=\"ltr\">…</p>", "APPEND": null, "SIGNATURE": null }
```

`TEXT` holds the whole HTML body as one string — text is no longer split into
lines. `APPEND` and `SIGNATURE` are write-only knobs (§8) and read back `null`.

---

## 6. Query options

### `$filter`

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

### Filtering on dates — the classic trap

Spaces become `%20` and `+` must become `%2B`. Because a year always starts
with `20`, an under-encoded space silently merges into the date:

```
WRONG:   ?$filter=STATUSDATE%20ge%2018-02-23T09:59:00+02:00     /* "ge 18-02-23" */
RIGHT:   ?$filter=STATUSDATE%20ge%202018-02-23T09:59:00%2B02:00
```

If a date filter returns nonsense, check the encoding before checking the data.

### `$since` (20.0+) — changed records only

```
GET serviceRoot/ORDERS?$since=2020-01-01T07:25:00Z&$expand=ORDERITEMS_SUBFORM
```

The right primitive for incremental sync, with three constraints: it works
**only on entities with business process management (BPM)** applied — i.e.
documents, not a general change feed; use **UTC with the `Z` suffix**, since an
offset is DST-dependent and needs hand-adjusting twice a year; and combined
with `$expand` the change detection stays on the parent, returning subform rows
of parents that changed.

### `$orderby`, `$top`, `$skip`, `$select`, and combining

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

---

## 7. Creating, updating and deleting

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

### Children

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
split the work with `$batch` and `dependsOn` (§9). From inside Priority SQL
itself, `EXECUTE INTERFACE` / `GENERALLOAD` is the in-system alternative to
REST for document loading — see the `priority-sql` skill.

### Update and delete

```http
PATCH serviceRoot/FAMILY_LOG('765')                     { "FAMILYDESC": "Updated" }
PATCH serviceRoot/ORDERS('SO18000002')/ORDERITEMS_SUBFORM(1)   { "TQUANT": 10 }

DELETE serviceRoot/FAMILY_LOG('765')
DELETE serviceRoot/ORDERS('SO18000002')/ORDERITEMS_SUBFORM(1)
```

**You cannot address a record by its auto-unique key in a PATCH** — read-only
from 21.1. Use the unique key. From 21.1 the response to a related-entity
update also includes the parent entity. Composite keys apply throughout.

---

## 8. Attachments and text forms

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

---

## 9. `$batch` (19.1+)

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

### Independent records — the bulk-load shape

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

### Dependent records — header then lines

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

### Rules and limits

- **Maximum 100 operations per batch.** (Docs briefly claimed 1,000/10,000 for
  versions before 21.1; 100 is the corrected figure.)
- **No rollback** — of the whole batch or of an atomicity group. Once Priority
  writes a change it cannot be undone, only overwritten. Never assume
  batch = transaction; design compensating actions yourself.
- From **22.1** the response format matches the request format (JSON in → JSON
  out); before that it was always `multipart/mixed`. Force the old format with
  `Accept: multipart/mixed`.

**Batch vs. nested POST:** reach for `$batch` when you need per-line error
attribution, or are mixing verbs and entities in one round trip. The nested
POST of §7 is simpler when the whole document succeeds or fails as a unit.

---

## 10. Errors and debugging

Because the API drives the form, **any error a Priority screen would raise
comes back in the response** — the message text is the trigger's own, often the
exact `ERRMSG` string from a CHECK-FIELD trigger. From **19.1** errors are JSON;
the older XML shape shows what the payload conveys — the submitted record plus
an `InterfaceErrors` block:

```xml
<FORM TYPE="FAMILY_LOG">
    <FAMILY_LOG><FAMILYNAME>790</FAMILYNAME><DEBITFLAG>Q</DEBITFLAG></FAMILY_LOG>
    <InterfaceErrors><text>Specify 'N' or 'Y' as the default value…</text></InterfaceErrors>
</FORM>
```

**Diagnostic order for a failing write:**

1. Reproduce it manually in the Priority UI, same form, same values. If it
   fails there too it is a business-rule problem, not an API problem — fix the
   data or the trigger.
2. If it succeeds in the UI but fails through the API, the form is behaving
   differently under the interface. Turn on Trace.

Trace requires the request header `X-App-Trace: 1` **and** server-side enabling
by the administrator, in `tabula.ini`:

```ini
[Internet]
Sqldebug=1
```

Trace files land in Priority's `tmp` folder (path is in `tabula.ini`). This is
the tool for "works in the UI, fails via API".

---

## 11. Limits and fair use

Cloud throttling — exceeding any of these returns **HTTP 429**:

| Limit | Value |
|-------|-------|
| Calls per minute | 100 per user |
| Parallel requests | 10 concurrent, 5 queued (15 total) |
| Request timeout | 3 minutes, then dropped |
| Calls per IP address | 5,000 per day |

Design for these: batch, expand and filter server-side rather than looping
client-side, and back off on 429 rather than retrying immediately.

**Transactions.** Every record *written* counts as one transaction — an order
with 5 lines costs 6, a status update costs 1, reads cost nothing. From 25.1 all
API users share one pool; before 25.1 the quota was divided per user and could
not be shared. Per-form transaction type and consumption are in the *View
License Details* and *API Transaction Count* reports.
