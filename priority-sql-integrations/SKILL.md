---
name: priority-sql-integrations
description: >
  Priority ERP external integrations — WSCLIENT for making HTTP/HTTPS requests
  to external web services and REST APIs (GET, POST, PATCH, PUT, DELETE, custom
  headers with -head2, Bearer token auth, OAuth2 via -authname, Basic auth,
  response capture, error handling via ERRMSGS). Use when writing Priority SQL
  that calls external APIs, sends HTTP requests, or processes web service
  responses. Structured for future extension with XMLPARSE and SFTPCLNT.
---

# Priority ERP — External Integrations

---

## 1. WSCLIENT — HTTP requests to external web services

Ref: [WSCLIENT - Work with Web Services](https://prioritysoftware.github.io/sdk/WSCLIENT)

`WSCLIENT` is Priority's built-in HTTP client. It reads a request body from a file, sends it to an endpoint, and writes the response to another file. All I/O is file-based.

---

### Full syntax

```sql
EXECUTE WSCLIENT :endpoint_url, :inFile, :outFile
  [, '-msg',     :msgFile]
  [, '-head2',   :headerValue]            /* repeatable — one header per -head2 */
  [, '-head',    :headerFile]             /* alternative: all headers in a file */
  [, '-usr',     :wsUser
     [, '-pwd',  :wsUserPwd]
     [, '-domain', :userDomain]]
  [, '-tag'|'-val', :tagName]             /* extract XML tag from response      */
  [, '-action',  :soapAction]             /* SOAP only                          */
  [, '-timeout', :msec]
  [, '-content', :contentType]
  [, '-method',  :method]                 /* GET, POST (default), PATCH, etc.   */
  [, '-headout', :responseHeaderFile]
  [, '-authname', :tokenCode]             /* OAuth2                             */
  [, '-urlfile', :urlFile];               /* use when URL > 127 chars           */
```

---

### Parameters

| Parameter | Required | Notes |
|-----------|----------|-------|
| `:endpoint_url` | Yes | Max 127 characters. Use `'-urlfile'` for longer URLs (pass `''` as the URL arg) |
| `:inFile` | Yes | File sent as the request body. Must be Unicode; WSCLIENT converts encoding to match `content-type` if needed. Use an empty temp file for GET requests |
| `:outFile` | Yes | File where the response body is written |
| `'-msg', :msgFile` | No | File for error message output |
| `'-head2', :value` | No | Add a single header string, e.g. `'Authorization: Bearer abc123'`. Repeat for multiple headers |
| `'-head', :headerFile` | No | File containing all request headers. Each header must end with a newline, including the last one |
| `'-usr'`, `'-pwd'`, `'-domain'` | No | Basic authentication credentials |
| `'-content', :contentType` | No | Sets the `Content-Type` header, e.g. `'application/json'` or `'text/xml;charset="utf-8"'`. Must match the encoding in the XML file header if XML |
| `'-method', :method` | No | HTTP method. Default is `POST`. Set to `'GET'`, `'PATCH'`, `'PUT'`, `'DELETE'` as needed |
| `'-timeout', :msec` | No | Timeout in milliseconds |
| `'-headout', :file` | No | Write response headers to a file (for APIs that return data in headers) |
| `'-authname', :tokenCode` | No | OAuth2 token code from the *OAuth2 Definitions* form |
| `'-urlfile', :urlFile` | No | When URL > 127 chars, put the full URL in an ASCII file and pass `''` as `:endpoint_url` |
| `'-tag'`/`'-val'` | No | Extract a named XML tag from the response. `-tag` includes the tag; `-val` returns the inner content only |

---

### Error handling

Errors are written to:
- The `'-msg'` file (if specified)
- The `ERRMSGS` table with `TYPE = 'w'` and `USER = SQL.USER`

Check for errors after the call:
```sql
:ERRMSG = '';
SELECT MESSAGE INTO :ERRMSG FROM ERRMSGS
WHERE USER = SQL.USER AND TYPE = 'w';
ERRMSG 500 WHERE :ERRMSG <> '';
```

---

### REST JSON example — POST with Bearer token

```sql
:URL      = 'https://api.example.com/orders';
:METHOD   = 'POST';
:CONTENT  = 'application/json';
:AUTH_HDR = STRCAT('Authorization: Bearer ', :TOKEN);

/* Write the JSON body to a temp file */
SELECT SQL.TMPFILE INTO :INFILE FROM DUMMY;
EXECUTE DBLOAD :INFILE USING '{"orderId": 123}';

SELECT SQL.TMPFILE INTO :OUTFILE FROM DUMMY;
SELECT SQL.TMPFILE INTO :MSGFILE FROM DUMMY;

EXECUTE WSCLIENT :URL, :INFILE, :OUTFILE,
  '-msg',     :MSGFILE,
  '-head2',   :AUTH_HDR,
  '-content', :CONTENT,
  '-method',  :METHOD;

/* Parse response */
EXECUTE XMLPARSE :OUTFILE ...;
```

---

### GET request

For GET requests, the `inFile` is required by the syntax but the body is ignored. Pass an empty temp file:

```sql
SELECT SQL.TMPFILE INTO :INFILE  FROM DUMMY;
SELECT SQL.TMPFILE INTO :OUTFILE FROM DUMMY;

:URL = 'https://api.example.com/items/42';

EXECUTE WSCLIENT :URL, :INFILE, :OUTFILE,
  '-head2',  'Authorization: Bearer mytoken',
  '-method', 'GET';
```

---

### URL longer than 127 characters

```sql
/* Write the full URL to a file */
SELECT SQL.TMPFILE INTO :URLFILE FROM DUMMY;
EXECUTE DBLOAD :URLFILE USING :FULL_URL;

SELECT SQL.TMPFILE INTO :INFILE  FROM DUMMY;
SELECT SQL.TMPFILE INTO :OUTFILE FROM DUMMY;

EXECUTE WSCLIENT '', :INFILE, :OUTFILE,
  '-method',  'GET',
  '-urlfile', :URLFILE;
```

---

### Multiple headers with `-head2`

```sql
:HDR1 = 'Authorization: Bearer mytoken';
:HDR2 = 'X-Custom-Header: myvalue';

EXECUTE WSCLIENT :URL, :INFILE, :OUTFILE,
  '-head2', :HDR1,
  '-head2', :HDR2,
  '-method', 'POST';
```

---

### OAuth2

Set up credentials in *Priority → OAuth2 Definitions*, then reference the token code:

```sql
EXECUTE WSCLIENT :URL, :INFILE, :OUTFILE,
  '-authname', 'PRIV_TOKEN',
  '-method',   'POST',
  '-content',  'application/json';
```

Priority automatically refreshes the access token when needed.

---

### Notes

- Debug logging: when the server log is at DEBUG level, both the request sent and the response received are written to the log.
- Response parsing: use `EXECUTE XMLPARSE` to extract values from XML or JSON response files. See §SDK reference for XMLPARSE.
- WSCLIENT **cannot** be used for SFTP — use `SFTPCLNT` instead.
