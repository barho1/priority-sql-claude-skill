# Discovering the model

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

## Refreshing metadata after customization (22.0+)

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
`$metadata` (see the `priority-sql-forms` skill):

```
GET serviceRoot/EFORM(ENAME='ORDERS',TYPE='F')?$expand=FCLMN_SUBFORM,FLINK_SUBFORM
```
