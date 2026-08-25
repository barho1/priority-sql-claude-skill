# Errors and debugging

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

Trigger execution is otherwise identical between the UI and the API — the one
exception is a trigger that explicitly branches on `:FORM_INTERFACE` /
`:FORM_INTERFACE_NAME`. `:FORM_INTERFACE = 1 AND :FORM_INTERFACE_NAME = ''` is
true when running via the API; `:FORM_INTERFACE = 0 OR :FORM_INTERFACE <> ''`
is true when not. Absent such a check, behavior is identical.
