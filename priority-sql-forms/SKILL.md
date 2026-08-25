---
name: priority-sql-forms
description: >
  Priority ERP form development — all form trigger types (CHECK-FIELD,
  POST-FIELD, CHOOSE-FIELD, SEARCH-FIELD, PRE-INSERT, POST-INSERT,
  PRE-UPDATE, POST-UPDATE, PRE-DELETE, POST-DELETE, PRE-FORM, POST-FORM),
  trigger execution order, trigger naming conventions, CHOOSE-FIELD variants
  (AND STOP, NO SORT, MCHOOSE-FIELD, union), CHOOSE-FIELD column creation
  workflow (CREATE TABLE, FOR TABLE INSERT, form setup, buffer trigger for
  expansion tables), inspecting form/column structure via the Priority REST
  API (EFORM endpoint, FCLMN_SUBFORM, FLINK_SUBFORM), and creating a form
  programmatically by loading into EFORM (header/column/sub-level fields,
  dynamic interface, form design rules). Use when creating or modifying form
  triggers, designing CHOOSE-FIELD picklists, creating a new form in code, or
  exploring form column and subform metadata.
---

# Priority ERP Form Development

Load the relevant file with the Read tool when the request needs that detail —
don't load them speculatively. These files and their names are internal
navigation aids for you, not something to mention to the user — answer with
the content itself, never by citing a reference file's path or name.

| File | Load when the request involves… |
|------|----------------------------------|
| `references/triggers.md` | Any trigger type (`CHECK-FIELD`, `POST-FIELD`, `PRE-INSERT`, `POST-UPDATE`, `PRE-FORM`…), trigger execution order, trigger naming, `CHOOSE-FIELD` variants (`MCHOOSE-FIELD`, `AND STOP`, `NO SORT`, union), combined triggers |
| `references/choose-field.md` | Creating a picklist end to end — the values table, the FK column, the form, and the buffer trigger for expansion tables |
| `references/metadata.md` | `EFORM` queries, `FCLMN_SUBFORM`, `FLINK_SUBFORM`, which columns are hidden/read-only/calculated, exploring form structure |
| `references/eform-create.md` | Creating a form programmatically by loading into `EFORM` |
| `references/include-buffers.md` | `#INCLUDE`, buffer triggers, sharing logic between triggers |
