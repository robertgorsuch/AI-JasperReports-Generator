# JasperReports Server 10.0.0 REST v2 — endpoint map (this install)

Distilled from the JRS 10.0.0 REST API Reference, scoped to the
report-design/deploy/run workflow this skill automates. Each entry is tagged:

- **[verified]** — exercised against this server (`localhost:8081/jasperserver-pro`,
  `superuser`/`superuser`, HTTP Basic) and confirmed working.
- **[doc-only]** — present in the docs / WADL but not yet exercised here; the
  payload/flow below is from the reference, treat as a starting point.

**Source of truth for this exact install:** the live WADL —
`http://localhost:8081/jasperserver-pro/rest_v2/application.wadl?detail=true`
(it never version-drifts the way the external community docs do, and the docs
site 403s scripted fetches anyway). Official reference:
<https://community.jaspersoft.com/documentation/jasperreports-server/tibco-jasperreports-server-rest-api-reference/v1000/jasperreports-server-rest-api-reference-_-overview/>

All paths below are under `…/jasperserver-pro/rest_v2/`. Auth is HTTP Basic on
every call. On **Windows**, POST/PUT JSON bodies from a **file**
(`--data "@req.json"`) — an inline `-d '{...}'` gets its quotes stripped by the
PowerShell→curl boundary and the server answers `400 serialization.error`.

---

## resources — repository CRUD  **[verified]**
The backbone the skill scripts already use.
- `GET  /resources?folderUri=/reports/geocoder&recursive=true&type=reportUnit`
  — list. Use `type=jdbcDataSource` for datasources (the generic `type=dataSource`
  returns `204`/empty on this server).
- `PUT  /resources{uri}?createFolders=true` (`Content-Type:
  application/repository.reportUnit+json`) — create/replace. See `deploy_report.ps1`.
- `DELETE /resources{uri}` — `204` on success; recursive on a folder.
- `GET  /resources{uri}` — fetch a resource descriptor (e.g. to read a deployed
  report's `jrxmlFileReference`, then `GET` that file URI to recover the jrxml —
  this is how the `uspopulation_tibcomaps` sample was pulled back out).

## reports — synchronous run  **[verified]**
- `GET /reports{uri}.{fmt}` — fill + export in one blocking call.
  Formats confirmed `200` here: **pdf, html, xlsx, csv, docx, pptx** (docs also
  list rtf, ods, odt, xml). Verify Office/OpenDocument output by `200` + size
  (magic is `PK`, not `%PDF-`).
- Pass report parameters / input-control values as query string:
  `…/PieChartReport.pdf?MaxOrderID=11077`.
- A `400` with an XML `errorDescriptor` body is a fill failure — read the
  `message`. Common causes here: a leading `WITH` CTE (server SQL validator —
  see SKILL.md gotchas), or an external resource the server can't reach (the
  TibcoMaps sample 400s on `maps.google.com`).

## reportExecutions — asynchronous run  **[verified]**
Proper path for large/slow fills that can time out on the synchronous endpoint.
1. `POST /reportExecutions` body `{"reportUnitUri":"…","outputFormat":"pdf",
   "interactive":false,"async":true}` → `{requestId, exports:[{id,status}]}`.
2. `GET /reportExecutions/{requestId}/status` → `{"value":"ready"}` when done
   (`queued`/`execution` while running).
3. `GET /reportExecutions/{requestId}/exports/{exportId}/outputResource` →
   the bytes. `exportId` is `exports[0].id` from step 1 (or re-`GET
   /reportExecutions/{requestId}`).
- Add more formats to one execution: `POST /reportExecutions/{requestId}/exports`.

## jobs — scheduling  **[verified]** (full create→list→get→delete round-trip)
Recurring / triggered / emailed report delivery.
- `PUT /jobs` — create. **Both `Content-Type` AND `Accept` must be
  `application/job+json`** — a plain `application/json` Accept gives `406 Not
  Acceptable`. Returns the created job with a numeric `id`. Minimal descriptor
  that worked here (saves a PDF to the repo, once, at a future date):
  ```json
  {"label":"…","source":{"reportUnitURI":"/reports/geocoder/county_summary","parameters":{}},
   "trigger":{"simpleTrigger":{"timezone":"America/Chicago","startType":2,
     "startDate":"2026-12-01 09:00:00","occurrenceCount":1}},
   "baseOutputFilename":"county_summary_verify","outputFormats":{"outputFormat":["PDF"]},
   "repositoryDestination":{"folderURI":"/reports/geocoder","saveToRepository":true,"overwriteFiles":true}}
  ```
  `simpleTrigger.startType`: 1 = now, 2 = at `startDate` (`yyyy-MM-dd HH:mm:ss`);
  `occurrenceCount` 1 = once, -1 = forever (with `recurrenceInterval` +
  `recurrenceIntervalUnit`). Add `mailNotification` for email delivery.
- `GET  /jobs?reportUnitURI=/reports/geocoder/county_summary` — list (`204` if none).
- `GET  /jobs/{id}` — full descriptor (`Accept: application/job+json`).
- `DELETE /jobs/{id}` — `200`, echoes the id; afterward `GET /jobs/{id}` →
  `resource.not.found`.

## permissions  **[verified]** (set → confirm → restore round-trip)
A resource with no explicit ACL returns `204` and inherits from its parent
(geocoder inherits from `/`). Entries are `{uri, recipient:"role:/ROLE_X", mask}`.
- `GET /permissions{uri}` — explicit perms only (`204` = none/inherited).
- `GET /permissions{uri}?effectivePermissions=true` — resolved/inherited ACLs.
- `PUT /permissions{uri}` — **replace all explicit perms** on the resource.
  **`Content-Type: application/collection+json`** (NOT `…collection.permission+json`,
  which `415`s; that wrong guess cost two tries — the WADL is authoritative).
  Body: `{"permission":[{"uri":"repo:/reports/geocoder","recipient":"role:/ROLE_USER","mask":1}]}`.
- **Remove explicit perms / restore inheritance:** `PUT {"permission":[]}` → back to `204`.
- A single-permission `PUT`/`POST` (per WADL) uses plain `application/json`.
- `mask` values seen live: 1 = administer, 2 = read+delete (docs also: 6
  read+write+delete, 18 read+write, 30 read-only, 32 execute-only, 0 none).

> **Windows/PowerShell gotcha (both services):** an inline `"$baseUrl?query=…"`
> passed to `curl.exe` yields exit-code `000` (request never sent). Assign the
> **full literal URL to a variable first**, then pass the variable. Same root
> cause as the JSON-body quoting issue — keep complex args out of the inline
> PowerShell→curl boundary.

## attributes  **[verified]** (server-level scoped + user-level single, both round-tripped)
Server/org/user key-value attributes — usable in datasource/report expressions
(`{attribute('name')}`), handy for not hard-coding DB creds per environment.
Holders: server `/attributes` · org `/organizations/{id}/attributes` · user
`/users/{u}/attributes`. Entry shape: `{name, value, secure, inherited, holder}`.

- **User / org single attribute** — there's a per-name sub-resource
  `/users/{u}/attributes/{attrName}` (and `/organizations/{id}/…`):
  `PUT` a single `{"name":…,"value":…}` (`application/json`) → `201`;
  `GET` → `200`; `DELETE` → then `GET` is `resource.not.found`. Isolated and safe.
- **Server level has NO `/attributes/{name}` sub-resource** — only the collection
  at `/attributes`. ⚠️ **A bare `PUT /attributes` REPLACES ALL attributes** (this
  server has ~134 system attributes — mondrian/adhoc/log4j/etc.; a full PUT would
  wipe them). **Always scope the partial update with `?name=`:**
  `PUT /attributes?name=foo` body `{"attribute":[{"name":"foo","value":"bar"}]}`
  → updates only `foo`. **Verified:** count went 134 → 135 (delta exactly 1),
  the other 134 untouched. Multiple: repeat `&name=…`.
- `GET /attributes?name=foo` reads one; `DELETE /attributes?name=foo` removes one
  (also scoped — verified count restored 135 → 134).
- `secure:true` write-masks the value in reads; `?_embedded=...` and `hal+json`
  representations are available per the WADL.

## inputControls — parameterized reports  **[verified]** (author → discover → run)
Verified by deploying a parameterized geocoder report (`county_summary_param`:
`HAVING count(*) >= $P{minEdges}`) with an embedded control, then filtering it
via REST — `?minEdges=50000` shrank the output from 254 to 17 counties.

**Read / run flow:**
- `GET /reports{uri}/inputControls` — control definitions. Each has an `id`,
  a string `type` (e.g. `singleValueNumber`, `singleSelect`), and `state.options`.
- `GET /reports{uri}/inputControls/{id}/values` — selectable values (cascading
  controls supported; `200` even for a free single-value control).
- Run with the chosen value(s) as query params on the run endpoints:
  `…/reports{uri}.pdf?{controlId}=50000` (confirmed to filter; output size
  tracks the row count). The same works on `reportExecutions` via `parameters`.

**Authoring an input control in the report-unit descriptor** (what
`deploy_report.ps1` does *not* yet do — build the descriptor by hand). Several
non-obvious shapes, each found by reading the `400` body:
- `inputControls` on the report unit is a **flat array** (the `{inputControl:[…]}`
  XML nesting is wrong in JSON → `ArrayList … from Object value`).
- Each element is a **polymorphic wrapper object**: `{"inputControl":{…}}` for an
  inline control or `{"inputControlReference":{"uri":…}}` for a shared one
  (`known type ids = [inputControl, inputControlReference]`).
- The embedded control uses **legacy numeric type codes**, NOT the string enums
  the read API returns (`Cannot deserialize value of type 'byte' from String
  "singleValue"`): control `type` `2` = single value; the nested
  `dataType.dataType.type` is **ordinal** `0`=text, `1`=number, `2`=date,
  `3`=dateTime, `4`=time (so `1` for a numeric control — `2` silently yields a
  *date* control).
- **Binding:** the control's repo id = its URI last segment, derived from its
  **`label`** (spaces→`_`, case kept). That id MUST equal the jrxml `$P{param}`
  name or the value never reaches the query. (Set `label:"minEdges"`, put prose
  in `description`.) JRS materializes the inline control + dataType into
  `…_files/` sub-resources.
- Re-deploying `409`s (optimistic lock) — DELETE the report unit first
  (cascades the `_files`), confirm `404`, then PUT.
Minimal inline control that worked:
```json
"inputControls":[{"inputControl":{
  "label":"minEdges","description":"Minimum TIGER edge count per county",
  "mandatory":false,"readOnly":false,"visible":true,"type":2,
  "dataType":{"dataType":{"label":"minEdges number","type":1}}}}]
```

## import / export — promotion & backup  **[verified]**
Already wrapped by `export_resource.ps1` / `import_resource.ps1` (the supported
path for dashboards, and for moving any folder between servers).
- `POST /export {uris,parameters}` → `{id}`; poll `/export/{id}/state` until
  `phase=finished`; download `/export/{id}/exportFile` (the `/exportFile`
  suffix is required — a bare `GET /export/{id}` is `405`).
- `POST /import?update=true` (multipart zip); poll `/import/{id}/state`.

---

### Deliberately out of scope
Users/roles/organizations admin, domains/semantic layer, Ad Hoc / OLAP,
themes, diagnostics — present in the API but outside this skill's
geocoder-reporting remit. Discover them via the WADL if ever needed.
