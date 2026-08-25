# Reading data

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

## Expanding subforms inline (18.1+)

```
GET serviceRoot/ORDERS('99100042')?$expand=ORDERITEMS_SUBFORM
GET serviceRoot/ORDERS('99100042')?$expand=ORDERITEMS_SUBFORM,ORDERSTEXT_SUBFORM
GET serviceRoot/ORDERS('SO20000422')?$expand=ORDERITEMS_SUBFORM($expand=ORDERITEMSTEXT_SUBFORM)
```

Nesting is unlimited in principle — subform of subform of subform. Prefer one
expanded request over N+1 round trips; the cloud throttle (see the Limits
table in SKILL.md) counts calls, not rows. `$filter`/`$select`/`$orderby` can
also be used inside an `$expand`, separated by `;` instead of `&`.

## Attachments (21.0+, potentially breaking)

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
expanding attachments across many records. To upload an attachment, POST a
data URI into `EXTFILES_SUBFORM` instead of reading it.

## Text (20.0+)

```
GET serviceRoot/ORDERS('SO20000422')/ORDERSTEXT_SUBFORM
```
```json
{ "TEXT": "<style>…</style><p dir=\"ltr\">…</p>", "APPEND": null, "SIGNATURE": null }
```

`TEXT` holds the whole HTML body as one string — text is no longer split into
lines. `APPEND` and `SIGNATURE` are write-only knobs used when PATCHing text
(append vs. replace, signature append) and read back `null` here.
