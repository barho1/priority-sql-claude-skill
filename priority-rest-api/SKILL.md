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

This skill is split into this file (core concepts needed for almost every
request) plus `references/*.md` (task-specific detail, read on demand — see
the table below).

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
POSTing a record that already exists; **`429`** when throttled (§ Limits
below). `400`, `404` and `500` behave conventionally.

### Result-count cap

`$top` cannot exceed the system cap: **`MAXAPILINES`** (25.1+, default 2,000
records), or **`MAXFORMLINES`** before 25.1. Raising it hurts performance —
paginate with `$top`/`$skip` instead (`references/query-options.md`). A query
returning a suspiciously round row count has hit the cap.

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
  validations all apply, and errors surface as trigger messages
  (`references/errors-and-debugging.md`).
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

- The **unique key** — what URLs address. Often a business value
  (`ORDNAME`, `CUSTNAME`, `FAMILYNAME`), but on line-item forms it's a
  composite that includes an internal line-sequence field, e.g.
  `ORDERITEMS`/`INVOICEITEMS` are keyed by `ORDNAME` + `KLINE` — `KLINE` is
  not user-facing. Don't assume the unique key is always a meaningful
  business value.
- The **auto-unique key** (`ORD`, `FAMILY`, `PART`) — an internal integer.
  From 21.1 it is annotated read-only and **cannot address a record in `PATCH`
  or `POST`**, nor be changed.

Which properties form the key is declared in `$metadata` under `<Key>`.

---

## Reference files

Load the relevant file with the Read tool when the request needs that detail —
don't load them speculatively. These files and their names are internal
navigation aids for you, not something to mention to the user — answer with
the content itself, never by citing a reference file's path or name.

| File | Load when the request involves… |
|------|----------------------------------|
| `references/discovery.md` | `$metadata`, `GetMetadataFor`, `ClearEntityMetadata`, a field/entity that seems missing from the API, or "what fields does this form have" |
| `references/reading.md` | `GET`, composite keys, `$expand`, reading attachments (`EXTFILES_SUBFORM`), reading text subforms (`_SUBFORM` text bodies) |
| `references/query-options.md` | `$filter`, `$select`, `$orderby`, `$top`/`$skip`, `$since`, date-filter encoding issues |
| `references/writing.md` | `POST`, `PATCH`, `DELETE`, creating a document with child lines, uploading an attachment, writing text (`APPEND`/`SIGNATURE`) |
| `references/batch.md` | `$batch`, `dependsOn`, bulk loading, per-line error attribution |
| `references/errors-and-debugging.md` | `InterfaceErrors`, a write that fails via API but works in the UI, `X-App-Trace` |

---

## Limits and fair use

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
