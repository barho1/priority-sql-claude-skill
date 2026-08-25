## 4. `#INCLUDE` and buffers

`#INCLUDE` works in form triggers and procedure SQLI steps alike —
any trigger or SQLI block can include a trigger defined on any form.

`#INCLUDE` pulls the entire contents of another trigger into the current
one at compile time. Use it when the same logic must run in multiple
forms or columns without being duplicated:

```sql
/* CHECK-FIELD for TYPE in LOGPART — reuse the PART form's trigger */
#INCLUDE PART/TYPE/CHECK-FIELD
```

Syntax:
- `#INCLUDE form_name/trigger_name` — for row/form triggers
- `#INCLUDE form_name/column_name/trigger_name` — for column triggers

The including trigger inherits all SQL statements *and* error/warning
messages from the included trigger. Additional statements can be written
before or after the `#INCLUDE` line. Any changes to the included trigger
automatically affect all including triggers — check the *Use of Trigger*
sub-level before modifying a shared trigger.

**Buffers** are triggers that exist only to be included — they hold
shared logic that no form activates directly. Numbered buffers (`BUF1`
through `BUF19`) are predefined; named buffers follow the same naming
rules as custom triggers. The conventional home for shared buffers is
the `TRANSTRIG` form, a system form that exists purely to hold reusable
trigger code.

`#INCLUDE` can be nested — an included trigger may itself include
another.

**`SUB` vs `#INCLUDE`:** Use `SUB` for reuse *within* a single
trigger (extract a repeated block into a subroutine). Use `#INCLUDE`
for reuse *across* different forms or trigger positions (share logic
between LOGPART and PART, or between multiple PRE-INSERT triggers).

For the abstract SUB pattern that builds on `#INCLUDE`, see the advanced patterns reference.

Ref: [Including One Trigger in Another](https://prioritysoftware.github.io/sdk/Include-Triggers)

---

