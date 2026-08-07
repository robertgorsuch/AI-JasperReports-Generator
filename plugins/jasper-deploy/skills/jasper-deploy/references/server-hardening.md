# JRS server hardening (keystore, encryption, CSRF/XSS, SSL, sessions)

Distilled from js-jrs_10.1.0_server-security.pdf (primary) with a 9.0.0 delta
note at the end. All content is [doc-only]: taken from the vendor PDFs, not
exercised against the live localhost:8081 server. ASCII only. Terse.

## Keystore: .jrsks and .jrsksp

What it protects (10.1 security guide p.10-12): user passwords + secure files
in the repository DB, import/export catalog encryption, passwords in config
files, log-collector output encryption, (deprecated) HTTP param encryption.

Files created at install time, owned by the OS user who ran the install:
- `.jrsks` - the encrypted keystore (the actual keys), in $USER home (p.11).
- `.jrsksp` - keystore properties (key aliases/passwords, encoded not
  plaintext), same location (p.11).
- `keystore.init.properties` - path pointer to the two files above, copied
  into BOTH buildomatic/ and WEB-INF/classes so other OS users (e.g. tomcat)
  running buildomatic find the existing keystore (p.11).

Hard rules:
- If keystore or its passwords are lost, the server stops functioning and its
  data may become inaccessible (p.10). Import/export catalogs encrypted with
  a lost key cannot be decrypted.
- NEVER create a second keystore for a server. If buildomatic cannot find
  keystore.init.properties it prompts to create one; doing so twice can
  overwrite DB passwords and cut the server off from its own repo DB (p.11).
- Backups: copy `.jrsks` + `.jrsksp` together, keep `.jrsksp` encoded, copy
  as the install user, guard like production secrets; restore into the
  install user's $HOME where the server looks at runtime (p.13).
- Upgrade/migration: run upgrade scripts as the original install user, or
  copy both files into the upgrading user's home first. If the upgrade script
  prompts to create a new keystore, QUIT and rerun with keystore access;
  else you need old catalog + old keystore backups to recover (p.12).

Key aliases in the keystore (p.33): `passwordEncSecret` (repo DB secrets),
`deprecatedPasswordEncSecret` (pre-7.5 upgrade carryover),
`diagnosticDataEncSecret` (log collector output; export via js-export to
decrypt), `httpParameterEncSecret` (deprecated). Custom keys added with
js-import get their own alias.

Import/export keys (p.13-14):
- Since 7.5 the server manages its own import-export key; same-server
  round trips need nothing (CLI auto-detects; UI: choose "Server key").
- Pre-7.5 catalogs with default key: UI "Legacy key" / CLI alias
  `deprecatedImportExportEncSecret`.
- Custom-key catalogs: paste the key hex in UI/CLI for one-offs, store it in
  the repository, or js-import it into the keystore for continual use.
Relevant to this skill: export/import (promotion, backup) between STAGE and
PROD only works across servers if the key travels too - a catalog is
undecryptable on a server that lacks the export key.

## Encryption configuration

- Settings live in `.jrsksp` (Java properties; escape # : \ = as \# \: \\ \=)
  (p.33). Defaults: AES/DES ciphers (p.31).
- Best done BEFORE install via default_master.properties so keystore
  generation uses your settings (p.34). After install = long procedure:
  export everything incl. import-export cipher, stop server, decode and edit
  .jrsksp, re-encrypt/reimport (p.34).

## Password encryption in config files (buildomatic)

- Since 5.5, buildomatic can encrypt config-file passwords: internal
  jasperserver DB password, sample DBs, Tomcat JNDI definitions, mail server,
  LDAP bind password (p.37).
- Flags in default_master.properties before install/upgrade:
  `encrypt=true` and `propsToEncrypt=dbPassword,external.ldapPassword,...`
  (add e.g. `tenant.user.password`); install rewrites the cleartext values
  in place with encrypted ones (p.43-45).
- Pre-7.5 "encryption options" (per-machine buildomatic keystore, ks/ksp env
  vars) are legacy-only documentation (p.45).

## CSRF protection - and why scripted REST usually does NOT hit it

- OWASP CSRFGuard: every POST/PUT/DELETE from a browser must carry a token
  (`OWASP_CSRFTOKEN:...`); missing token = server does not reply and logs an
  error (p.47).
- Config: `WEB-INF/csrf/jrs.csrfguard.properties`,
  `org.owasp.csrfguard.Enabled=true` (default; leave on). Restart after
  changes. Do not touch other settings (p.47-48).
- The filter only fires for BROWSER user-agents (Mozilla/Opera strings cover
  Chrome/Firefox/IE/Safari) (p.51). curl/PowerShell/Invoke-RestMethod send
  non-browser UAs, so plain scripted REST is exempt. If a client fakes a
  browser UA or you use a browser REST plugin, add header `X-REMOTE-DOMAIN: 1`
  to every request; GETs never fail the check (p.51).
- Extra browser UAs can be protected via `protectedUserAgentRegexs` on
  csrfGuardFilter in applicationContext.xml (p.52).

## Cross-domain whitelist (Visualize.js / embedding)

- `domainWhitelist` server attribute (also per-org/per-user; set via UI
  Server Settings > Server Attributes or REST attributes API). Requests from
  non-whitelisted domains fail with 401 + a logged CSRF warning (p.48).
- ALWAYS set it: blank value if no cross-domain embedding; else a simplified
  pattern incl. protocol and port, e.g. `http://*.myexample.com:80\d0`
  (server wraps it into a full regex). Extra patterns: `domainWhitelist1`,
  `domainWhitelist2`, or `additionalWhitelistAttributes` on crossDomainFilter
  in applicationContext.xml (p.49-50).
- Never DELETE the server-level attribute: an upgrade would restore a less
  secure default. Defined-but-empty survives upgrades (p.51).
- Skill tie-in: a Visualize.js embed page served from another origin that
  gets 401s -> check this attribute first.

## XSS protection

- Since 6.1 all UI output is escaped; input validation is deprecated (p.52).
- Dynamic-content escaping configured in
  `WEB-INF/classes/esapi/security-config.properties`:
  `xss.soft.html.escape.tag.whitelist` (comma list, leading `+` appends to
  default) and `xss.soft.html.escape.attrib.map` (regex->replacement map);
  defaults live in js-sdk xssUtil.js (p.53-55). Misconfiguration can break
  the UI or silently disable protection - leave alone unless required.
- REST payloads are not blocked by this; it is output escaping, not an input
  filter. If you see literal `<script...>` in UI data, someone is probing.

## SQL injection / query validation

- The server validates report queries to block injection; validation rules
  can be customized in the security framework config, and there are known
  performance implications (p.59-63). Practical effect for this skill: the
  validator rejects some legit shapes - e.g. leading-WITH (CTE) queries fail
  fill with an opaque 400 (see gotchas G15). Fix the query shape before
  touching validation rules.

## SSL/TLS and secure cookies

- Enable HTTPS in Tomcat: keystore + uncomment an SSL `<Connector>`
  (port 8443, scheme=https, secure=true, sslProtocol=TLS) in
  conf/server.xml (p.79-81).
- Force SSL-only: in WEB-INF/web.xml first `<security-constraint>`, set
  `<transport-guarantee>CONFIDENTIAL</transport-guarantee>` (url-pattern /*
  => web services included). NONE = mixed mode (p.81-82). Scripts calling
  http:// after this will get redirected/refused - use https.
- Disable unused HTTP verbs: commented-out `<security-constraint>` block in
  web.xml lists HEAD/OPTIONS/TRACE/PATCH/etc.; uncomment to deny (p.82-83).
  Note PATCH is in that list - keep it allowed if any client uses it.
- Secure flag on cookies: JSESSIONID comes from the app server (configure
  there); the JRS-created cookies (userTimezone, userLocale, UI state) only
  get `secure`/path tweaks by editing source and rebuilding the war
  (p.83-85). httpOnly for the session cookie: set in the app server (p.85).
- HTTP header options (X-Content-Type-Options, X-XSS-Protection): configure
  in the app server, per Tomcat docs (p.83).
- Host header injection protection: p.90-91.

## Login encryption (breaks naive REST if enabled)

- `encryption.on` in WEB-INF/classes/esapi/security-config.properties,
  default FALSE. When true, the login page encrypts the password with a
  server-generated keypair via JavaScript - and web services and URL
  parameters MUST also send encrypted passwords: a script has to fetch the
  public key first and encrypt before sending (p.121-122). So plain
  Basic-auth scripts failing after a security review -> check this flag.
- Whole-parameter HTTP encryption (dynamic/static key) is deprecated since
  7.5; use TLS instead (p.121-124).

## Sessions, timeout, lockout, passwords

- Session timeout: web.xml `<session-timeout>`, default 20 minutes; 0 = never
  (p.92). REST note: a session outlives a web service call for the timeout
  period and is REUSED by later calls with the same credentials - too short
  hurts performance under API load, too long delays role-change pickup
  (p.93).
- Deleted-user session invalidation: js.config.properties
  `user.exists.check.enabled` + `user.exists.check.interval` (default
  60000 ms) (p.93).
- Account lockout: default ON, 10 failed logins disables the account until an
  admin re-enables. Bean `loginLockoutConfig` in
  applicationContext-security.xml, property
  `allowedNumberOfLoginAttempts` (0 = disable) (p.100-101). Failed-attempt
  bookkeeping: JIUser.numberOfFailedLoginAttempts +
  JIExternalUserLoginEvents table (cleanup threshold + cron configurable in
  applicationContext.xml) (p.101-102). LDAP quirk: `user|org` and bare
  `user` are the same account for lockout purposes (p.102).
- Password options (p.94-99): password memory (autocomplete), expiration,
  user password change, pattern enforcement, password history
  (JIUserPasswordHistory table blocks reuse of last N; p.100).
- Password storage strategy (NEW in 10.1, p.102-116): `password.strategy` =
  `legacy` (reversible AES; upgrade-compat only) or `modern` (default for
  new installs; one-way PBKDF2/SCrypt/Argon2 via `password.modern.*` props;
  removes the keystore dependency for user login credentials). Migration of
  legacy hashes is a manual batch utility, zero downtime (p.103).

## Troubleshooting scripted REST 401/403 - checklist

1. 401 from a cross-origin embed page -> domainWhitelist attribute (p.48).
2. POST/PUT/DELETE silently fails from a browser-UA client -> CSRF; add
   `X-REMOTE-DOMAIN: 1` or use a non-browser UA (p.51).
3. Basic auth suddenly rejected -> login encryption `encryption.on` (p.122),
   or account lockout after 10 bad attempts (p.100).
4. Redirect/refusal on http -> SSL-only CONFIDENTIAL constraint (p.82).
5. Import of a foreign catalog fails to decrypt -> missing export key; see
   keystore import/export section (p.13-14).
6. Everything broken after a server move -> .jrsks/.jrsksp not restored to
   the service user's home (p.13).

## 9.0.0 differences (js-jrs_9.0.0_server-security.pdf)

Same structure except 10.1 ADDS four sections (verified by TOC diff):
- Configuring Password Storage Strategy (modern one-way hashing,
  password.strategy) - 10.1 p.102; absent in 9.0 (9.0 has only reversible
  "Encrypting User Passwords", p.93).
- Password History Validation - 10.1 p.98.
- Invalidating Active Sessions for Deleted User - 10.1 p.93.
- Adding Dashboard Web Page Domain Whitelist Attributes to Server Attributes
  - 10.1 p.56.
Everything else (keystore, CSRF, XSS, SSL, lockout) is materially identical;
only page offsets differ (9.0 is 105 pp, 10.1 is 129 pp).
