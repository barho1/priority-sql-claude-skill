# Priority ERP — External Integrations

This skill covers traffic *out* of Priority. For traffic *in* — an external
system reading or writing Priority data over HTTP — see the `priority-rest-api`
skill.


## 1. WSCLIENT — HTTP requests to external web services

Ref: [WSCLIENT - Work with Web Services](https://prioritysoftware.github.io/sdk/WSCLIENT)

`WSCLIENT` is Priority's built-in HTTP client. It reads a request body from a file, sends it to an endpoint, and writes the response to another file. All I/O is file-based.


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


### Error handling

Errors are written to:
- The `'-msg'` file (if specified)
- The `ERRMSGS` table with `TYPE = 'w'` and `USER = SQL.USER`

Check for errors after the call:
```sql
:ERRMSG = '';
SELECT MESSAGE INTO :ERRMSG FROM ERRMSGS
WHERE USER = SQL.USER AND TYPE = 'w';
ERRMSG 501 WHERE :ERRMSG <> '';
```


### Writing the request body to a file

All WSCLIENT I/O is file-based, so the request body must be written to a file
first. The mechanism is `ASCII` output redirection on a `SELECT ... FROM DUMMY`
— **not** `DBLOAD`, which is a table-load command that reads files rather than
writing them.

```sql
SELECT SQL.TMPFILE INTO :BODY FROM DUMMY;
SELECT 'first line'  FROM DUMMY ASCII :BODY;        /* write (replaces)  */
SELECT 'second line' FROM DUMMY ASCII ADDTO :BODY;  /* append            */
```

`ASCII :file` writes, `ASCII ADDTO :file` appends. Successive `ADDTO`
statements are how you build a body larger than a single CHAR variable —
relevant because `STRCAT` results cap at 127 characters, so a JSON payload of
any size must be accumulated across several statements rather than
concatenated into one variable.

Ref: [WSCLIENT - Work with Web Services](https://prioritysoftware.github.io/sdk/WSCLIENT)

---

### REST JSON example — POST with Bearer token

```sql
:URL      = 'https://api.example.com/orders';
:METHOD   = 'POST';
:CONTENT  = 'application/json';
:AUTH_HDR = STRCAT('Authorization: Bearer ', :TOKEN);
/* Write the JSON body to a temp file */
SELECT SQL.TMPFILE INTO :INFILE FROM DUMMY;
SELECT '{"orderId": 123}' FROM DUMMY ASCII :INFILE;
SELECT SQL.TMPFILE INTO :OUTFILE FROM DUMMY;
SELECT SQL.TMPFILE INTO :MSGFILE FROM DUMMY;
EXECUTE WSCLIENT :URL, :INFILE, :OUTFILE,
  '-msg',     :MSGFILE,
  '-head2',   :AUTH_HDR,
  '-content', :CONTENT,
  '-method',  :METHOD;
/* Parse the response */
SELECT SQL.TMPFILE INTO :TAGS FROM DUMMY;
LINK INTERFXMLTAGS TO :TAGS;
EXECUTE XMLPARSE :OUTFILE, :TAGS, 0, :MSGFILE, '', 'Y';
SELECT VALUE INTO :ORDERID FROM INTERFXMLTAGS WHERE TAG = 'orderId';
UNLINK INTERFXMLTAGS;
```

---

### Parsing the response

`EXECUTE XMLPARSE` reads a response file and writes every tag it finds into a
linked `INTERFXMLTAGS` table, which you then query with ordinary SQL.

```sql
EXECUTE XMLPARSE :xmlFile, :linkFile, 0, :msgFile [, '-all'] [, :json];
```

| Argument | Notes |
|----------|-------|
| `:xmlFile` | The response file written by WSCLIENT (`:outFile`) |
| `:linkFile` | Temp file linked to `INTERFXMLTAGS`, where parsed tags land |
| `0` | Required positional argument |
| `:msgFile` | File for parse error messages |
| `'-all'` | Optional. Parse *every* instance of a tag; without it, only the first |
| `:json` | Pass `'Y'` to parse **JSON** instead of XML — note it occupies the 6th position, so pass `''` for `'-all'` when you only want JSON |

Results are read from `INTERFXMLTAGS` by its `LINE`, `TAG`, `VALUE` and `ATTR`
columns. Link it to a temp file before the call and unlink it after, exactly as
with any other linked temp table.

From **23.1** a single tag can hold up to 45,000 characters; before that the
limit was 1,023.

Ref: [XMLPARSE](https://prioritysoftware.github.io/sdk/XMLPARSE)


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


### URL longer than 127 characters

```sql
/* Write the full URL to a file */
SELECT SQL.TMPFILE INTO :URLFILE FROM DUMMY;
SELECT :FULL_URL FROM DUMMY ASCII :URLFILE;
SELECT SQL.TMPFILE INTO :INFILE  FROM DUMMY;
SELECT SQL.TMPFILE INTO :OUTFILE FROM DUMMY;
EXECUTE WSCLIENT '', :INFILE, :OUTFILE,
  '-method',  'GET',
  '-urlfile', :URLFILE;
```


### Multiple headers with `-head2`

```sql
:HDR1 = 'Authorization: Bearer mytoken';
:HDR2 = 'X-Custom-Header: myvalue';
EXECUTE WSCLIENT :URL, :INFILE, :OUTFILE,
  '-head2', :HDR1,
  '-head2', :HDR2,
  '-method', 'POST';
```


### OAuth2

Set up credentials in *Priority → OAuth2 Definitions*, then reference the token code:

```sql
EXECUTE WSCLIENT :URL, :INFILE, :OUTFILE,
  '-authname', 'PRIV_TOKEN',
  '-method',   'POST',
  '-content',  'application/json';
```

Priority automatically refreshes the access token when needed.


### Notes

- Debug logging: when the server log is at DEBUG level, both the request sent and the response received are written to the log.
- Response parsing: use `EXECUTE XMLPARSE` — see *Parsing the response* above.
- WSCLIENT **cannot** be used for SFTP — use `SFTPCLNT` instead.
