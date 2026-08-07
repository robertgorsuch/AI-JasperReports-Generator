# JRS external authentication (LDAP / CAS / external DB / token / OAuth)

Distilled from js-jrs_10.1.0_authentication-cookbook.pdf (primary) with a 9.0.0
delta note at the end. All content is [doc-only]: taken from the vendor PDFs,
not exercised against the live localhost:8081 server. ASCII only. Terse.

Local context: our JRS is 10.0.0 commercial ("jasperserver-pro"); the 10.1
cookbook applies. Default install here uses internal auth (HTTP Basic as
superuser), so everything below is for when external auth enters the picture.

## Architecture: how external auth is activated

- All sample Spring Security files live in
  `<js-install>/samples/externalAuth-sample-config/` (10.1 auth cookbook p.12).
- Activation = copy a sample, rename to `applicationContext-<name>.xml`
  (e.g. `applicationContext-externalAuth-LDAP.xml`), configure its beans, drop
  it into `<js-webapp>/WEB-INF/`, restart the app server (p.12).
- For the bundled Tomcat: `<js-webapp>/WEB-INF` =
  `<js-install>/apache-tomcat/webapps/jasperserver[-pro]/WEB-INF` (p.13).
- The switch is presence-based: when a `proxyAuthenticationProcessingFilter`
  bean exists in any applicationContext-*.xml under WEB-INF, the Spring
  Security filter chain uses the proxy (external) definitions instead of the
  default internal filter. No other toggle (p.36, p.158).
- Sample files are edition-specific; `-mt` in a filename = multi-tenant
  (commercial). The `mt` prefix appears in both editions' bean names (p.20).

## External user synchronization (all mechanisms)

- After external auth succeeds, `externalDataSynchronizer` mirrors the user
  into the internal jasperserver DB: creates missing orgs (from repo
  templates), maps/creates roles, creates the user account (p.20-21).
- External accounts: flagged external, full name = login name, NO password
  stored (no failover if the authority is down), no email/profile attrs by
  default (p.21-22). Admins can only disable them.
- Role types: external (synced, auto-removed when gone upstream), internal
  (admin-created; map explicitly), system (treated like internal) (p.22).
- Mapping an external role to an internal role: append `|*` for org-level
  assignment; bare name = system (root) level with admin-wide reach (p.23).
- Name collision external vs internal role -> `_EXT` suffix added (p.23).
- Do not hand-assign internal roles to external users: sync re-adds/removes
  per the external authority on every login (p.22-23, warning p.41).
- Everyone gets ROLE_USER automatically; never map it (p.47).
- External user ID colliding with an existing *internal* user = login fails;
  admin must resolve manually (p.21).

## LDAP

Sample: `sample-applicationContext-externalAuth-LDAP[-mt].xml`. Key beans
(p.36-37):
- `proxyAuthenticationProcessingFilter` - enables external auth; no config.
- `ldapAuthenticationManager` - ordered provider list; last entry
  `${bean.daoAuthenticationProvider}` falls back to the internal DB, so
  jasperadmin/superuser still work.
- `ldapContextSource` - server URL + admin bind DN/password.
- `ldapAuthenticationProvider` - two inline sub-beans:
  `JSBindAuthenticator` (find + bind user entry) and
  `JSDefaultLdapAuthoritiesPopulator` (find groups -> roles).
- `externalDataSynchronizer` with processors `ldapExternalTenantProcessor`
  (org mapping, commercial only) and `mtExternalUserSetupProcessor` /
  `externalUserSetupProcessor` (role setup).

Connection (p.38-40): preferred path is `default_master.properties` before
install/upgrade: `external.ldapUrl` (URL incl. base DN), `external.ldapDn`,
`external.ldapPassword` - these can be buildomatic-encrypted. Alternative:
hardcode in the XML (then no encryption possible).

User search (p.41-46):
- `userDnPatterns` on JSBindAuthenticator for fixed RDN layouts, e.g.
  `uid={0},ou=users` ({0} = login name; base DN appended automatically -
  never repeat the base DN in the pattern).
- `userSearch` bean (`JSFilterBasedLdapUserSearch`) for anything else:
  constructor args = branch RDN (may be empty), filter e.g. `(uid={0})`,
  ldapContextSource ref; property `searchSubtree` true/false.
- Search must return exactly ONE entry. Two users with the same login in
  different orgs cannot both log in (org mapping happens after user search).

Role mapping (p.46-47): configure `JSDefaultLdapAuthoritiesPopulator`:
- constructor-arg index=1: branch DN for group entries (empty = whole tree)
- `groupRoleAttribute`: attribute whose value becomes the role name (often cn)
- `groupSearchFilter`: e.g. match uniqueMember; `{0}` = full user DN,
  `{1}` = username
- `searchSubtree`: extend below the branch/base DN
Role name charset is restricted; extend `permittedExternalRoleNameRegex` on
the user setup processor, default `[A-Za-z0-9_]+`; never allow spaces or
most punctuation (p.55).

Organization mapping (commercial, p.55-63):
- Multi-org: `ldapExternalTenantProcessor` maps the user RDN hierarchy to an
  org hierarchy; missing orgs are auto-created with a default admin
  (change its password; see p.56). `organizationMap` renames upstream orgs;
  unsupported chars become `_` (list in `tenantIdNotSupportedSymbols` of
  configurationBean, applicationContext.xml) (p.62).
- Single org: comment out the first ldapExternalTenantProcessor instance,
  uncomment the second, set `defaultOrganization` (e.g. organization_1) and
  `excludeRootDn=true`. NEVER leave defaultOrganization empty - users can
  land in the null org, which sees every organization's repo (p.62-63).
- Multiple providers: add providers to the ldapAuthenticationManager list;
  first success wins (p.63).
- Active Directory: use userSearch (sAMAccountName), set the Spring referral
  property = follow; troubleshooting section p.66-75.

## CAS

Samples (p.85): `...-CAS.xml` and `...-CAS-staticRoles.xml` (community),
`...-CAS-db-mt.xml` and `...-CAS-LDAP-mt.xml` (commercial; roles/orgs pulled
from a JDBC DB or LDAP because CAS itself only proves identity).
Setup outline:
1. Java must trust the CAS server certificate: import into the JRE cacerts
   (`keytool -importcert ...`), or point `-Djavax.net.ssl.trustStore` at a
   custom store (p.84-85).
2. Configure `casServiceProperties` (class JSCASServiceProperties):
   `service` = the JRS URL that receives tickets and MUST end in
   `j_spring_security_check`; `sendRenew` true/false (p.87-88).
3. Configure `externalAuthProperties`: `ssoServerLocation` (HTTPS URL where
   tickets are validated), `externalLoginUrl` and `logoutUrl` (may be
   relative, `#ssoServerLocation#/login`) (p.88).
4. Roles: static roles, or `externalDataSource` + `casJDBCUserDetailsService`
   (SQL queries for user details) (p.87, p.89-93). Orgs: same processor
   patterns as LDAP (p.94-96).
Login URL changes: users are redirected to the CAS server's login page; the
JRS login page is bypassed for external users.

## SAML

Not covered: neither the 10.1 nor the 9.0 authentication cookbook has a SAML
chapter (verified against both TOCs). If SAML is required, front JRS with a
SAML-capable gateway and use token-based pre-auth, or use the OAuth/OIDC
chapter if the IdP speaks OIDC.

## Token-based (pre-authentication / header token)

Sample: `sample-applicationContext-externalAuth-preauth[-mt].xml` (p.125).
Flow (p.122-123): no login screen. First request carries the token in the
`principalParameter`; JRS (optionally) decrypts it, builds the principal,
syncs the user, then issues a normal app-server session cookie - the token is
not needed again until logout/expiry.

Beans (p.125-126):
- `proxyPreAuthenticatedProcessingFilter`: `principalParameter` (fixed string
  that triggers token auth), `tokenInRequestParam` (true = URL only, false =
  header only, absent = header first then URL), `tokenDecryptor`.
- `preAuthenticatedManager` -> `JSPreAuthenticatedAuthenticationProvider`
  -> `preAuthenticatedUserDetailsService` (token format).

Token format (p.128-129): key/value pairs joined by `tokenPairSeparator`
(default `|`; cannot be `,` `?` `=`). `tokenFormatMapping` maps JRS fixed
keys to token field names: `username`, `roles`, `orgId` (multi-tenant),
`expireTime`, `profile.attribs` (nested map). `tokenExpireTimestampFormat`
e.g. `yyyyMMddHHmmssZ`. In URLs, encode `=` as %3D and `|` as %7C.

Security notes (p.126-127): JRS accepts ANY properly formatted token, so:
use SSL; encrypt the token (implement Jaspersoft's `CipherI` interface from
jasperserver-api.common.jar, wire the class into `tokenDecryptor`; default =
plaintext passthrough); always set expireTime (about 1 minute) to kill
replay. If a Siteminder-style front end injects headers, the network must
prevent header forgery (p.162).

## OAuth 2.0 / OIDC (JWT)

Present in both 9.0 and 10.1. Provider MUST support OpenID Connect; JRS
validates and decodes the JWT id token, then syncs the user (p.143-145).
Enable: edit web.xml `spring.profiles.active` param, append `,oauth` ->
`default,engine,jrs,oauth` (p.145).
Configure: `WEB-INF/classes/oauth-clientconfig.properties` (p.146-151):
- Client: `spring.security.oauth2.client.registration.oidc.registration-id`,
  `.client-id`, `.client-secret`, `.client_authenticationMethod`,
  `.redirect-uri` (JRS endpoint is `/oauth`, give the full URL, e.g.
  `https://host/jasperserver-pro/oauth`), `.scope`, `.filterProcessesUrl`,
  `.authorization-uri`; provider: `...provider.oidc.token-uri`, `.jwk-uri`,
  `.issuer-uri`.
- JRS side: `spring.security.oauth2.jrs.entrypoint` (must end with the
  registration-id), `spring.security.oauth2.jrs.logouturl`.
Mapping (p.149-155):
- `spring.security.oauth2.user.attributes.mapping.name` = JWT claim used as
  user id; `.mapping.roles` = claim holding roles/groups.
- `spring.security.oauth2.external.user.organizationRoleMap` = JSON (escape
  quotes with \) mapping JWT role values to JRS roles; `|*` suffix = tenant
  (org-level) role; unknown roles are created at sync (p.153-154).
- Org hierarchy: `.mapping.organization-id` claim + `.mapping.org-delimiter`
  (e.g. `main-org|unit1|department1`) (p.154).
- Profile attributes: claims starting with
  `spring.security.oauth2.profile.attributes.prefix` become profile attrs.
- Admins: `...external.user.adminUserNames`, `.defaultAdminRoles`,
  `.defaultInternalRoles` (keep at least ROLE_USER) (p.153-155).
There is no standalone "JWT authentication" chapter; JWT appears only as the
OIDC token inside OAuth.

## REST and filter-chain implications

- Filter chains (p.157-158): `/rest/login`, `/rest/**`, `rest_v2/**` are
  handled by `restAuthenticationProcessingFilter` + basicProcessingFilter;
  `/**` (browsers) by authenticationProcessingFilter. The external-auth proxy
  beans cover REST too - the cookbook notes REST/SOAP wiring is implemented
  in the LDAP sample files.
- With LDAP/external-DB auth, HTTP Basic on rest_v2 authenticates against the
  provider chain; the trailing daoAuthenticationProvider keeps internal
  admins (superuser) working (p.36, p.157).
- Multi-org login: external users leave the org id BLANK (the authority
  supplies it); internal users still need `user|org` form (p.34).
- Token-based REST: send the token (header or URL principalParameter) on the
  first call, then reuse the session cookie; a timestamped token stops URL
  copy/replay (p.123, p.126).
- CAS/OAuth are browser-redirect flows - not usable for headless REST
  scripts; keep an internal account or token pre-auth for automation.
- Cross-domain (Visualize.js) callers must be on the server's domainWhitelist
  or they get 401 - see references/server-hardening.md.

## 9.0.0 differences (js-jrs_9.0.0_authentication-cookbook.pdf)

- Section-by-section structure is IDENTICAL to 10.1, including the OAuth
  chapter (9.0 cookbook p.133 vs 10.1 p.143). Only page offsets differ
  (9.0 is 158 pp, 10.1 is 168 pp; e.g. LDAP starts p.31 vs p.32,
  token-based p.113 vs p.121).
- 10.1 slightly expands "Maintenance of External Users" (p.25-30 vs 24-30);
  no new mechanisms, no removed mechanisms. Neither version covers SAML.
