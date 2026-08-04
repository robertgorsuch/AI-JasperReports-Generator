# JRS upgrade/migration playbook: 4.7 -> 10.1.0

Cross-version upgrade planning for JasperReports Server, distilled from the official
vendor PDF sets. Terse on purpose. ASCII only.

ALL content here is [doc-only]: distilled from vendor PDFs in docs\ (and their
extracted text), not exercised against a live server. Verify the actual server with
`GET /rest_v2/serverInfo` before relying on any row.

Depth pointers:
- Per-era source detail: references/version-archive/platform-evolution.md (platform
  matrices per version), version-archive/upgrade-procedures.md (guide-by-guide
  procedures, keystore, export/import), version-archive/relnotes-install-deltas.md
  (release notes, install architecture, deprecation timeline).
- Deep 9.0 -> 10.0 -> 10.1 delta (features, REST changes, JR Library levels):
  references/version-matrix.md. This file does not repeat that detail.

GUIDING INPUT: migration planning starts from section 0 (field-reported upgrade
issues, from the engagement tracker "Upgrade Issues - JasperReports Server.xlsx",
docs\ copy, 2026-08-04). Plan mitigations for every Blocker/Common row FIRST,
then walk the ladder (sec 2) and cliffs (sec 3) for the specific hop.

## 0. Field-reported upgrade issues (GUIDING INPUT) [field]

16 issues observed across real customer upgrades (source: Issues sheet of the
tracker; impact and frequency are the tracker's own ratings, not doc-derived).
"Mitigation" points into this playbook or names the gap.

| # | Issue (field wording) | Impact | Frequency | Mitigation / coverage |
|---|---|---|---|---|
| 1 | Keystore inconsistency between original and upgraded environment (upgrade onto another machine creates two incompatible keystores) | Blocker | Common | sec 4a: carry $HOME/.jrsks + .jrsksp to the new machine BEFORE first start; never let the upgrade create a fresh keystore. Validate consistency before cutover |
| 2 | Buildomatic driver configuration (JAR name -> default_master.properties mapping unclear) | Major | Occasional | sec 4c + version-archive/upgrade-procedures.md sec 5 (driver-swap steps per era). Doc gap: no JAR-to-property map anywhere; record the working config before export |
| 3 | JDBC connection string configuration (templates/XML, no central config) | Blocker | Occasional | Doc gap: connection strings live in default_master.properties + context.xml + repo datasources. Inventory all three pre-upgrade (skill: extract_lineage.py lists repo datasources) |
| 4 | Figuring out which files were customized (customers do not know) | Major | Common | sec 4d/4e. Doc gap: no detection procedure. Diff a pristine same-version WAR against the deployed one before planning (see sec 0 tooling roadmap) |
| 5 | Configuring SSO after upgrade (LDAP, OAuth2) | Major | Occasional | references/authentication.md; sec 4d for the Jakarta hop (Spring Security bean rewrites at 7.2 and 10.0) |
| 6 | Configuring SMTP after upgrade | Minor | Rare | references/server-administration.md + smtp-testing.md; re-enter mail config in default_master.properties post-upgrade |
| 7 | Adjusting REST calls after upgrade (behavior changes) | Major | Rare | version-matrix.md "REST / API-visible changes" + jrs-rest-api.md version deltas (csrfguard 4.3.0 at 10.0 is the big one) |
| 8 | Exporting a large repository (resource limits in UI and buildomatic) | Blocker | Common | sec 4b. Doc gap: guides never size the export. Mitigate: js-export from buildomatic (not UI), raise JVM heap, export in slices (per-folder) and merge, verify zip before wiping anything |
| 9 | Theme adjustment (new versions break themes, silently) | Major | Common | sec 4e; back up the default theme before touching it; re-test themes on the new version (7.5 and 8.2 are the documented theme-overhaul releases) |
| 10 | Importing a large repository | Blocker | Common | Same as #8: buildomatic js-import, heap, slices; import audit/access events separately (sec 4b) |
| 11 | Upgrade guide unclear on why/when leap-frog upgrades are needed | Minor | Env-specific | sec 2 IS the answer: direct-source windows per target + documented stepping stones |
| 12 | Upgraded WAR deployed under different OS user than the app server | Blocker | Env-specific | Doc gap (guides only say run js-upgrade as the installing user, sec 4a). Add to checklist: chown/icacls the deployed webapp to the app-server user before start |
| 13 | Merging customizations built on older XML files | Major | Env-specific | sec 4d: three-way merge (old-pristine vs old-customized vs new-pristine); Jakarta hop forces javax->jakarta rewrite on top |
| 14 | samedb upgrade not possible LTS -> LTS (newdb required) | Major | Common | sec 2 direct-source table: samedb only from the adjacent release (e.g. 9.0 samedb only from 8.2.x; 8.0 LTS -> 9.0 LTS = newdb). Plan newdb + export early |
| 15 | Buildomatic import/export errors not verbose enough | Major | Common | Doc gap. Mitigate: always run js-upgrade-newdb `test` mode first; read buildomatic/logs/js-upgrade-*.log; keep the export zip for re-runs (sec 5 checklist) |
| 16 | Legacy key alias obfuscated (deprecatedImportExportEncSecret) | Minor | Common | sec 4a/4b: that alias IS the pre-7.5 import/export key; needed when importing old exports into 7.5+ keystored servers |

Reading of the tracker for planning: the Blocker+Common cluster is keystore
consistency (#1) and large-repo export/import (#8/#10) -- exactly sec 4a and 4b.
Those two areas get engineering time FIRST in any migration plan; everything
else is schedulable around them.

### Tooling roadmap implied by the tracker (Functionality sheet)

Primary: config-file diff; java/backend customization diff (incl. external
auth); frontend customization diff; keystore consistency validation across
instances; buildomatic driver config helper; JDBC connection string helper;
WAR permission validator; auto-upgrade of resolvable conflicts + report of
remaining conflicts.
Secondary: SMTP post-upgrade config; REST request validation/upgrade;
automated theme upgrade (may be promoted to primary).
Important but complex: simplified any-to-any upgrade path; direct LTS-to-LTS
upgrade; large-repo migration; buildomatic error/stacktrace assistant.
Skill overlap today: diff_resource.ps1 (repo-resource drift, not server
config), extract_lineage.py (datasource inventory), doctor.ps1 (env
preflight). The rest is open field for new skill scripts.

## 1. Version lineage and naming eras

Naming era = prefix on installers/WAR zips: jasperreports-server-* (Jaspersoft era),
TIB_js-jrs_* (TIBCO era), js-jrs_* (Cloud Software Group era)
(see version-archive/relnotes-install-deltas.md sec 2).

| JRS | Era / date | File-name era | Identity in one phrase |
|---|---|---|---|
| 4.7 | Jun 2012 | jasperreports-server-* | Ad Hoc split into views vs reports; Flash charts; data snapshots (jasperreports-server-upgrade-guide__legacy) |
| 5.0/5.0.1 | Feb 2013 | jasperreports-server-* | UI repository export added; samedb keeps custom global props, newdb does not (jasperreports-server-upgrade-guide__legacy) |
| 5.5 | Nov 2013 | jasperreports-server-* | "Use the WAR file for production" first stated; buildomatic password encrypt toggle (jasperreports-server-install-guide_3) |
| 5.6 | ~2014 | jasperreports-server-* | Overlay upgrade introduced; commercial JDBC drivers (Oracle/MSSQL/DB2) removed from package (jasperreports-server-upgrade-guide__legacy) |
| 6.0 | Nov 2014 | jasperreports-server-* | Last of the Java 6 line (jaspersoft_platform_support_v6.0) |
| 6.1 | Jun 2015 | jasperreports-server-* | Java 8 first certified; theme changes (jaspersoft_platform_support_v6.1) |
| 6.2 | Nov 2015 | jasperreports-server-* | Java 6 dropped; last Flash listing; last tc Server/JBoss AS (jaspersoft_platform_support_v6.2) |
| 6.3 | Jun 2016 | jasperreports-server-* | Flash gone; PhantomJS headless section appears; Edge appears; canonical stepping stone for 3.7-4.2 sources (jaspersoft_platform_support_v6.3) |
| 6.4 | Jun 2017 | jasperreports-server-* | 64-bit JDKs only; stepping stone for 4.5-5.x sources (jaspersoft_platform_support_v6.4_0) |
| 7.1 | May 2018 | TIB_js-jrs_* | Java 8 only; 64-bit WAR only; XMLA server deprecated; canonical stepping stone for all 6.x sources (jaspersoft_platform_support_v_7.1_0) |
| 7.2 | May 2019 | TIB_js-jrs_* | Spring Security 4.2 rewrite; legacy dashboards permanently deleted; Tomcat 9 first (jasperreports-server-upgrade-guide__r93 appendix) |
| 7.5 | Nov 2019 | TIB_js-jrs_* | Keystore (.jrsks) introduced; Java 11 first; Simba driver swap; MongoDB query change; theme overhaul (tib_js-jrs_7.5_jaspersoft_platform_support-commercial-edition) |
| 7.8 | ~2020 | TIB_js-jrs_* | Export engine switched PhantomJS/Rhino -> Chrome/Chromium; last IE11 (tib_js-jrs_8.1.1_relnotes) |
| 7.9 | Mar 2021 | TIB_js-jrs_* | Chromium in platform docs; newdb stops importing access/audit/monitoring data (tib_js-jrs_7.9_platform-support-commercial-edition; js-jrs_10.1.0_upgrade-guide) |
| 8.0.x | 2021-2022 | TIB_js-jrs_* | Compact vs Split installs; XMLA server disabled; REST v1/SOAP removed; installer demoted to eval-only; 8.0.4 removes Simba + adds Java 17 runtime (tib_js-jrs_8.0.3_relnotes; js-jrs_8.0.4_relnotes_1) |
| 8.1 | 2022 | TIB_js-jrs_* | Rhino removed; JMX diagnostics off by default; Report Bursting; avoid Tomcat 9.0.67 (tib_js-jrs_8.1.1_relnotes; tib_js-jrs_8.1.0_platform-support-commercial-edition) |
| 8.2 | 2023 | js-jrs_* (CSG rebrand) | .xls export removed (.xlsx only); Hibernate 5.2 -> 5.6; sample themes deprecated; UI JDBC driver upload (tib_js-jrs_8.2.0_relnotes) |
| 9.0 | Jan 2024 | js-jrs_* | Progress/TI* drivers removed; JNDI security; OAuth/OpenID built in; Alerting; JR Library 6.21.0 (js-jrs_9.0.0_relnotes) |
| 10.0.0 | Nov 2025 | js-jrs_* | Jakarta EE 10 + Tomcat 10.1/11; Java 17/21; Hibernate 6; new license manager; csrfguard 4.3.0; JR Library 7 (js-jrs_10.0.0_relnotes_28Jan) |
| 10.1.0 | Jul 2026 | js-jrs_* | Castor -> Jackson (exports not importable to older versions); one-way password hashing; Oracle 23ai/26ai; Tiles retired (js-jrs_10.1.0_relnotes) |

## 1b. Support status and End-of-Life dates [web-only]

Source: www.jaspersoft.com/support/end-of-life-policies, Wayback snapshot
2026-05-15 (live page Akamai-403s scripted fetches; extracted text saved as
docs\jaspersoft-eol-policy-20260515.txt). This is VENDOR POLICY, not PDF-derived.

Release model: Mainstream (MS) vs Long-Term Support (LTS). Numbering V.R.L:
V = LTS version, R = Mainstream release, L = Service Pack. MS ships every 3-6
months and is supported >= 12 months after the NEXT release ships; hotfixes/SPs
go only to the latest MS. LTS ships every 18-24 months, supported ~2 years with
hotfixes/SPs. Extended Support is purchasable. Only the latest MS/LTS is
downloadable from eDelivery (older versions on request). LTS upgrade path:
LTS -> next LTS, or latest LTS -> any subsequent MS.

| JRS | Released | Type | EOL cases | EOL hotfix/SP | Ext. w/ patches | Ext. w/o patches |
|---|---|---|---|---|---|---|
| 10.0.0 | 11/21/2025 | LTS | 12/31/2029 | 12/31/2029 | 12/31/2030 | 12/31/2030 |
| 9.0.0 | 1/25/2024 | LTS | 12/31/2027 | 12/31/2027 | 12/31/2028 | 12/31/2029 |
| 8.2.0 | 4/28/2023 | MS | 1/25/2025 | 1/25/2024 | 12/31/2024 | 5/31/2025 |
| 8.1.0 | 7/26/2022 | MS | 4/28/2024 | 4/28/2023 | 12/31/2024 | 5/31/2025 |
| 8.0.x | 11/18/2021 | LTS | 12/31/2025 | 12/31/2025 | 6/30/2026 | 6/30/2027 |
| 7.9.x | 12/7/2020 | MS | 11/18/2023 | 11/18/2021 | N/A | 11/18/2024 |
| 7.8.x | 8/21/2020 | MS | 12/7/2022 | 12/7/2020 | N/A | N/A |
| 7.5.x | 12/18/2019 | MS | 8/21/2022 | 8/21/2020 | N/A | N/A |

- Extended Support is no longer for sale for 8.0.x and 9.0.
- Everything older than 7.5.x: already EOL, unsupported.
- JasperReports IO tracks the same dates (JRIO 10.0.0/4.0.0/3.2.0/3.1.0/3.0.x
  map to the JRS rows above).
- The 2026-05-15 capture predates 10.1.0 (Jul 2026): its type/EOL dates are not
  yet published there. Given the V.R.L scheme, 10.1.0 is an R (Mainstream)
  release after the 10.0.0 LTS; verify on the live page before planning on it.

Planning implications (as of 2026-08):
- 8.x and older: fully out of support (8.0.x LTS ext-with-patches lapsed
  6/30/2026; only no-patch extended support runs to 6/30/2027). Any 7.x/8.x
  estate is running unsupported software: EOL pressure IS the migration driver.
- 9.0.0 is safe until 12/31/2027 but Extended Support cannot be bought anymore:
  hard wall.
- 10.0.0 LTS is the long-runway target (cases + hotfixes to 12/31/2029);
  10.1.0 MS gets hotfixes only until the next release ships (MS policy).

## 2. The upgrade ladder

### Direct-source window per target (what the target's own guide accepts)

| Target | samedb direct | newdb direct | Overlay sources | WAR-zip floor | Guide |
|---|---|---|---|---|---|
| 5.6 | 5.5 | 3.7 - 5.2 | 4.0 - 5.5 | 3.7 | jasperreports-server-upgrade-guide__legacy |
| 8.0 | 7.9 | 7.1 - 7.5 | 7.1+ | 7.1 | jasperreports-server-upgrade-guide__r93 |
| 8.1 | 8.0 | 7.1 - 7.9 | 7.1+ | 7.1 | tib_js-jrs_8.1.0_upgrade-guide |
| 8.2 | 8.0/8.1 | 7.1 - 7.9 | 7.1+ (commercial only) | 7.1 | js-jrs_8.2.0_upgrade-guide (CE: js-jrs-ce_8.2.0_upgrade-guide, WAR only) |
| 9.0 | 8.2.x | 8.0.x - 8.1.x | 8.0+ | 8.0 | js-jrs_9.0.0_upgrade-guide |
| 10.0.0 | 9.0 | 8.0.x - 8.2 | 9.0+ (table) / 8.0+ (chapter) [contradiction, see sec 7] | 8.0 | JasperReportsServerUpgradeGuidev10.0.0 |
| 10.1.0 | 10.0 | 9.0 | 10.0.0+ (table) / 9.0+ (chapter) [contradiction] | 9.0 | js-jrs_10.1.0_upgrade-guide |

### Stepping-stone ladder to 10.1 from ANY source

Each hop is documented by the target's own upgrade guide; method in parentheses.
Rule from every guide: samedb only for the adjacent-release chapter; newdb (export
from OLD buildomatic, import into fresh DB) for everything older
(version-archive/upgrade-procedures.md sec 1).

| You are on | Hop sequence | Documented by |
|---|---|---|
| pre-3.5 | -> 3.7 first, then follow 3.7 row | jasperreports-server-upgrade-guide__legacy ch.5 |
| 3.5 | -> 3.7 -> follow 3.7 row | jasperreports-server-upgrade-guide__legacy ch.5 |
| 3.7 - 4.2 | -> 6.3.x (newdb) -> 7.1.x (newdb) -> 8.2 (newdb) -> 9.0 (newdb) -> 10.0/10.1 | 8.0-9.0 guides "6.4.x or Earlier" chapters; js-jrs_9.0.0_upgrade-guide |
| 4.5 - 5.x | -> 6.4.x (newdb) -> 7.1.x (newdb) -> 8.2 (newdb) -> 9.0 -> 10.0/10.1 | jasperreports-server-upgrade-guide__r93 ch.6 (ending version updated per guide) |
| 6.0 - 6.4.x | -> 7.1.x (newdb) -> 8.2 (newdb) -> 9.0 (newdb) -> 10.0.0 (samedb) -> 10.1 (samedb) | JasperReportsServerUpgradeGuidev10.0.0 stepping stones |
| 7.1 - 7.9 | -> 8.2 (newdb) -> 9.0 (samedb from 8.2) -> 10.0/10.1 | js-jrs_8.2.0_upgrade-guide ch.4; js-jrs_9.0.0_upgrade-guide |
| 8.0.x - 8.2 | -> 10.0.0 (newdb, direct) -> 10.1 (samedb); or -> 9.0 first | JasperReportsServerUpgradeGuidev10.0.0; js-jrs_9.0.0_upgrade-guide |
| 9.0 | -> 10.1.0 (newdb, direct; install matching Tomcat first) or -> 10.0 (samedb) -> 10.1 (samedb) | js-jrs_10.1.0_upgrade-guide |
| 10.0 | -> 10.1.0 (samedb or overlay) | js-jrs_10.1.0_upgrade-guide |

Notes:
- "Versions prior to 6 are no longer supported and must be upgraded to version 6.3
  first" appears in every 8.x/9.0 guide (jasperreports-server-upgrade-guide__r93).
- The 10.1 guide drops the "6.4.x or Earlier" chapter entirely: for 8.x or older
  "see the respective Upgrade Guides for those versions" (js-jrs_10.1.0_upgrade-guide).
- Compact/Split never crosses during a hop: Compact -> Compact, Split -> Split;
  change type only via the migrate-to-split step AFTER landing (sec 4g).
- Overlay = commercial + Tomcat + WAR-install + default keys + certified repo DB
  only, at every version 5.6 -> 10.1 (version-archive/upgrade-procedures.md sec 2).

## 3. Platform cliffs

What breaks when you cross a version boundary, regardless of upgrade method.
Full matrices: version-archive/platform-evolution.md sec 1-2.

| At version | What breaks | Mitigation |
|---|---|---|
| 6.2 | Java 1.6 dropped (last listed 6.1) | move JVM to 1.7/1.8 before the hop (jaspersoft_platform_support_v6.2) |
| 6.3 | Flash dropped; Pro Charts/Maps/Widgets Flash era ends; PhantomJS becomes the headless engine | migrate Flash content to HTML5 charts (jaspersoft_platform_support_v6.3) |
| 6.4/7.1 | 32-bit JVM/OS dropped (6.4 lists 64-bit JDKs only; 7.1 WAR is 64-bit only) | migrate host + JVM to x86-64 (jaspersoft_platform_support_v6.4_0; jaspersoft_platform_support_v_7.1_0) |
| 7.1 | Java 8 floor (1.7 last at 6.4) | JVM to 1.8 first (jaspersoft_platform_support_v_7.1_0) |
| 7.2 | Spring Security 3.x -> 4.2: external-auth applicationContext-externalAuth-*.xml and custom security code break; legacy (pre-5.6.2) dashboards PERMANENTLY DELETED, no rollback | re-implement auth config on the new sample files (bean names/packages changed); recreate legacy dashboards as new dashboards BEFORE upgrading (jasperreports-server-upgrade-guide__r93 appendix) |
| 7.5 | Keystore introduced: all encryption keys move to $HOME/.jrsks/.jrsksp; Simba Spark/Impala drivers replaced; MongoDB aggregate query syntax changes; themes break (large classname changes); GlassFish/HP-UX dropped | adopt keystore backup discipline (sec 4a); update Mongo queries; re-do themes (tib_js-jrs_7.5_jaspersoft_platform_support-commercial-edition; tib_js-jrs_8.1.1_relnotes) |
| 7.5 (Java) | Java 11 first certified; Java 8 min build 1.8.0_163 | ok to stay on 8 until 10.0 (tib_js-jrs_7.5_jaspersoft_platform_support-commercial-edition) |
| 7.8/7.9 | PhantomJS/Rhino export engine REMOVED; Chromium required for PDF/DOCX export of reports/dashboards | install + configure Chrome/Chromium; without it exports fail (jasperreports-server-upgrade-guide__r93 appendix 7.8; tib_js-jrs_7.9_platform-support-commercial-edition) |
| 7.9 | js-upgrade-newdb stops importing access/audit/monitoring data | reimport the export zip via UI Import page with those checkboxes after upgrade (js-jrs_10.1.0_upgrade-guide) |
| 8.0 | XMLA server component disabled by default (deprecated since 7.1); REST v1 + SOAP removed; Compact/Split split introduced; installer demoted to evaluation-only | re-enable JasperXmlaServlet in web.xml if needed; move clients to REST v2; pick install type deliberately (tib_js-jrs_8.0.3_relnotes) |
| 8.0.4 | Simba drivers removed (athena/cassandra/impala/neo4j/spark-jdbc42) | install public/vendor drivers, update resources (js-jrs_8.0.4_relnotes_1) |
| 8.1 | Rhino removed (JS-dependent reports break); SQL Server 2014 repo dropped; Tomcat 9.0.67 broken (bug 66277) | manually restore rhino-1.7.14 jar to WEB-INF/lib if needed; upgrade repo DB; pin another 9.0.x (tib_js-jrs_8.1.1_relnotes; tib_js-jrs_8.1.0_platform-support-commercial-edition) |
| 8.1+ | Chromium becomes an install-time dependency: installer has a dedicated Chrome/Chromium step; "install without" = no PDF/DOCX export | preinstall Chrome/Chromium or set alternate browser path in js.config.properties (tib_js-jrs_8.1.0 install guide, see relnotes-install-deltas.md sec 2) |
| 8.2 | .xls / .xls-Paginated export REMOVED (.xlsx only); Java 17 arrives but runtime-only and Tomcat 9.0.x only; repo DB cliff: Oracle 12c/18c, PostgreSQL 9.x-11, DB2 10.5, MySQL 5.5/5.6 dropped | fix schedules/integrations that request .xls; upgrade repo DB first (tib_js-jrs_8.2.0_relnotes; js-jrs_8.2.0_platform-support-commercial-edition) |
| 9.0 | Progress/TI* JDBC drivers removed (12 jars) with data-type behavior changes in migrated domains/ad hoc views; WebSphere 8.5.5.x dropped; JNDI renames required | install vendor drivers; remediate types via WEB-INF/applicationContext-jdbc-metadata.xml bean (sec 4c); create new JNDI resources (js-jrs_9.0.0_relnotes; js-jrs_9.0.0_upgrade-guide) |
| 10.0 | Java 17/21 floor (8 and 11 dropped); Jakarta EE 10: Tomcat 10.1.24+/11.0.11+ only, JBoss EAP 8, WildFly 36; WebSphere/WebLogic/JWS have NO supported target; Hibernate 6 (hbm.xml -> JPA); new license manager + renamed license file; csrfguard 4.3.0 per-page tokens forced on; ehcache2 -> JCache/Infinispan; repo DB cliff: MySQL 5.7, PostgreSQL 12/13 dropped | re-host to a Jakarta container; rebuild custom code javax.* -> jakarta.*; rename license; rework cookie-session clients for CSRF tokens (js-jrs_10.0.0_platform-support-commercial_28Jan; JasperReportsServerUpgradeGuidev10.0.0) |
| 10.1 | Castor -> Jackson: exports from 10.1.0 CANNOT be imported into older versions; one-way password hashing (samedb + modern strategy needs migration utility); Oracle repo needs new dbVersion property (quartz-23onwards.ddl for 23ai+); MySQL 8.0 repo dropped (8.4 only); Apache Tiles retired (custom JSP overlays break) | never demote exports; run password migration utility; set dbVersion in default_master.properties; port tiles:insertTemplate to tag files (js-jrs_10.1.0_upgrade-guide; js-jrs_10.1.0_relnotes) |

Repo DB support cliffs in one line: 8.1 drops SQL Server 2014; 8.2 drops Oracle
pre-19c + PostgreSQL <12 + DB2 10.5; 10.0 drops MySQL 5.7 + PostgreSQL 12/13;
10.1 drops MySQL 8.0. Upgrade the repository DB before or with the JRS hop
(version-archive/platform-evolution.md sec 2 "Repository databases").

## 4. Pain-point catalog

### 4a. Keystore / .jrsks loss
- Symptom: upgrade prompts "create a new keystore"; or post-restore the login page
  errors out; or repository decrypt fails and users cannot log in.
- Cause: keystore introduced in 7.5; keys live in $HOME/.jrsks + .jrsksp of the OS
  user who installed the server (jasperreports-server-upgrade-guide__r93 A.3.3).
- Mitigation: back up both files to JS_BACKUP before any upgrade; run js-upgrade as
  the same OS user; if prompted to create a keystore, ABORT, fix location, rerun --
  continuing corrupts the repository. 8.2+ alternative: point
  keystore.init.properties (WEB-INF/classes/, buildomatic/, buildomatic/conf_source/
  iePro/) at the real location. Lost-keystore recovery: on the old server
  `js-export.sh --everything --genkey` (prints secret key + alias), import the key
  into the new keystore BEFORE importing the catalog
  (version-archive/upgrade-procedures.md sec 3).
- Clusters: keystore files must be identical across nodes (tib_js-jrs_8.0.3_relnotes
  known issues).

### 4b. Export/import compatibility direction
- Rule: exports flow old -> new only. Each target guide states which old exports it
  imports (see sec 2 table). Only explicit backward statement in the corpus:
  "Resources exported from version 10.1.0 cannot be imported into older versions"
  (js-jrs_10.1.0_upgrade-guide). Repo DB schema changes exist between every pair of
  releases, so treat newer -> older as unsupported everywhere.
- Export always runs with the OLD version's buildomatic; import-upgrade runs in
  non-update mode (new core resources win) with update-core-users (old superuser/
  jasperadmin passwords kept) (js-jrs_8.2.0_upgrade-guide).
- Since 7.9.0 js-upgrade-newdb does NOT import access/audit/monitoring events;
  reimport the same zip via UI Import with those checkboxes afterwards; on Split the
  import routes them to the audit DB (js-jrs_10.1.0_upgrade-guide).
- Encrypted catalogs: import the key first, then import with
  `--include-server-settings --secret-key` (jasperreports-server-upgrade-guide__r93).
- Legacy landmine: 5.1 UI export is buggy; export from CLI, or hand-edit index.xml
  "5.0.0 CE" -> "5.1.0 PRO" (jasperreports-server-upgrade-guide__legacy 4.4.1).

### 4c. Driver removals and remediation
- Timeline: 5.6 removes bundled commercial Oracle/MSSQL/DB2 drivers (copy your own
  into buildomatic/conf_source/db/<db>/jdbc before upgrading); 6.2.1/6.4 remove the
  community Impala connector (long jar list to restore); 7.5 replaces Simba
  Spark/Impala; 8.0.4 removes Simba athena/cassandra/impala/neo4j/spark-jdbc42;
  9.0 removes all Progress/DataDirect TI*.jar drivers
  (version-archive/upgrade-procedures.md sec 5; js-jrs_8.0.4_relnotes_1).
- 9.0 remediation: install native vendor drivers, then update resources. Data-type
  drift (SQL Server Time no longer Timestamp, Float -> Double) causes "missing
  fields or columns" in domains/ad hoc views and time/datetime operator errors in
  JRXML; either update the resources or uncomment the
  JdbcDriverMetaConfigurationImpl bean in WEB-INF/applicationContext-jdbc-metadata.xml
  to restore old mappings (js-jrs_9.0.0_upgrade-guide).

### 4d. Custom code / overlays across the Jakarta jump (10.0)
- Symptom: custom jars, chart customizers, servlet filters, anything importing
  javax.servlet.* fails to load on 10.0+.
- Cause: codebase moved to the jakarta namespace; Tomcat 10.1.x; Hibernate 6 drops
  .hbm.xml; Spring/Spring Security 6.x (JasperReportsServerUpgradeGuidev10.0.0;
  js-jrs_10.0.0_relnotes_28Jan).
- Mitigation: rebuild custom code against jakarta.* and Java 17; note that through
  8.x/9.0 source builds stayed on Java 8 bytecode (Java 11 "compatibility mode"),
  so 10.0 is the first forced recompile (js-jrs_9.0.0_platform-support-commercial
  footnotes). Re-verify every WEB-INF/lib jar after the hop. The overlay procedure
  at 10.0 includes copying the webapp from Tomcat 9.0 to Tomcat 10.1.x and needs
  Windows long-path support enabled (JasperReportsServerUpgradeGuidev10.0.0).
- General rule in every guide: manually carry WEB-INF customizations
  (applicationContext-*.xml, *.properties, *.js, *.jar) forward; nothing migrates
  them for you (version-archive/upgrade-procedures.md sec 5).

### 4e. UI customizations / themes
- Symptom: custom themes/branding broken after upgrade.
- Cause versions: 6.1 theme changes; 4.7 Ad Hoc split; 7.5 large CSS classname
  overhaul (Banner, Ad Hoc Designer, Report Viewer, Dashboard Designer); 8.2
  deprecates the sample themes; 10.1 retires Apache Tiles (JSP overlays must move
  from tiles:insertTemplate to <tmpl:*> tag files)
  (tib_js-jrs_8.1.1_relnotes; tib_js-jrs_8.2.0_relnotes; js-jrs_10.1.0_relnotes).
- Mitigation (9.0+ doctrine): upgrade first, then get the JRS Source Packages,
  reapply JS/CSS customizations there, rebuild and publish
  (js-jrs_9.0.0_upgrade-guide).

### 4f. samedb vs newdb vs overlay decision
- samedb: in-place DB migration; only for the adjacent source window (sec 2 table);
  preserves custom global properties (5.6-era note) and, at 10.1, may require the
  password migration utility (jasperreports-server-upgrade-guide__legacy A.2.1;
  js-jrs_10.1.0_upgrade-guide).
- newdb: fresh DB + import of an export zip; required for older sources; loses
  custom global properties and (since 7.9.0) audit/access/monitoring data until
  reimported (sec 4b).
- overlay: fastest, rollback-capable, but commercial edition + Tomcat + WAR-file
  install + default encryption keys + certified repo DB only; "not possible if you
  configured custom encryption keys" (every commercial guide 8.0-10.1).
- Both js-upgrade scripts support `test` dry-run mode; logs land in
  buildomatic/logs/js-upgrade-<date>-<n>.log (js-jrs_10.1.0_upgrade-guide).
- CE: WAR-only, script names suffixed -ce, no overlay chapter
  (js-jrs-ce_8.2.0_upgrade-guide).

### 4g. Compact vs Split constraints (8.0+)
- Compact (default) = repo + audit/access/monitoring in one DB; Split = separate
  audit DB (installType=split + audit.db* in default_master.properties).
- Hard rule: upgrades never cross type. 8.1 Compact -> 8.2 Split is forbidden;
  upgrade Compact -> Compact, then run js-migrate-to-split-newdb (optionally with
  include-access-events include-audit-events include-monitoring-events). Same rule
  restated for 9.0 -> 10.0 and 10.0 -> 10.1 (js-jrs_9.0.0_upgrade-guide appendix;
  js-jrs_10.1.0_upgrade-guide).
- After a Split samedb upgrade run transfer-audit-data.bat/.sh (resumable if
  interrupted) (js-jrs_8.2.0_upgrade-guide).

### 4h. License file handling
- 4.7-5.0: eval license in <js-install>, relocatable via -Djs.license.directory.
- 5.1-9.0: file is jasperserver.license in the deployed root; replace, clear
  tomcat/work, restart (version-archive/relnotes-install-deltas.md sec 2).
- 10.0+: new in-house license validator; file renamed jaspersoft.jrs.license and
  needs correct file permissions (js-jrs_10.0.0_relnotes_28Jan). The 10.1 upgrade
  guide is internally inconsistent: p.83 says jaspersoft.jrs.license, p.44 shows
  jasperserver.jrs.license -- check both names, do not silently pick one
  (js-jrs_10.1.0_upgrade-guide; see version-matrix.md sec 3).
- License must be in place BEFORE running the upgrade scripts (all guides).

### 4i. OLAP / XMLA migration
- 5.6: XML/A connections to remote JRS must change DataSource to
  "Provider=Mondrian;DataSource=JRS"; superuser XML/A fails on multi-org instances
  (test as jasperadmin). 5.0: tenantID in the Data Source field no longer supported
  (jasperreports-server-upgrade-guide__legacy A).
- 7.1: XMLA server deprecated; 8.0.0: disabled by default (re-enable
  JasperXmlaServlet in web.xml); 8.0.3/8.1.1: OLAP Views no longer supported and
  OLAP JS formatter scripts disabled (olap.mondrian.scripts.enabled); 8.2: OLAP
  views deprecated, migrate to Ad Hoc on Mondrian/XMLA connections; 10.0: viewing
  of OLAP views removed; 10.1: Studio drops OLAP/Mondrian data adapters
  (version-archive/relnotes-install-deltas.md sec 3).
- CP -> commercial upgrades: re-point XML/A URIs /jasperserver/xmla ->
  /jasperserver-pro/xmla and user "jasperadmin" -> "jasperadmin|organization_1"
  (jasperreports-server-upgrade-guide__r93 CP chapter).

### 4j. CE vs commercial upgrade tooling
- CE: WAR distribution only (no binary-installer upgrade path documented, no
  overlay); scripts are js-upgrade-samedb-ce / js-upgrade-newdb-ce; no
  Compact->Split migration chapter (js-jrs-ce_8.2.0_upgrade-guide).
- CE platform docs certify only PostgreSQL for the repository; other repo DBs are
  Compatible (jasperreports-server-platform-support-community).
- CP -> commercial jump is only valid within the same major release (5.6 CP ->
  5.6 commercial; 9.0 CP -> 9.0 commercial); procedure = export CP repo, deploy
  commercial WAR, import (adds superuser, Themes, default tenant structure)
  (version-archive/upgrade-procedures.md sec 2 "Community Edition specifics").
- 10.1 CE library loses PDF accessibility ("Tag PDF not supported")
  (js-jrs_10.1.0_relnotes).

## 5. Pre-upgrade checklist

1. Record current state on the source server: `GET /rest_v2/serverInfo` (version,
   edition, dateFormatPattern). Skill: doctor.ps1 does this against an env profile.
2. Read the cliffs table (sec 3) for every version boundary you will cross;
   "changes are cumulative, so review all topics that affect you" (every guide).
3. Verify target platform prerequisites BEFORE touching the server: JVM version,
   app server, repo DB version against sec 3 / version-archive/platform-evolution.md.
   Upgrade the repo DB first if it falls off the support list at the target.
4. Back up the keystore: copy $HOME/.jrsks and $HOME/.jrsksp (of the installing OS
   user) to a secure JS_BACKUP folder. Non-negotiable for any 7.5+ source (sec 4a).
5. Back up the repository database (pg_dump or DB-native) and the whole
   <js-install> tree, including the deployed webapp.
6. Export the repository as a portable catalog:
   `js-export --everything --output-zip js-<ver>-export.zip` with the OLD
   buildomatic. Skill: export_resource.ps1 covers per-resource REST exports; the
   everything-zip needs buildomatic on the host.
7. Inventory customizations: WEB-INF applicationContext-*.xml, *.properties, *.js,
   custom jars in WEB-INF/lib (chart customizers!), themes, external-auth config.
   Diff against a stock WAR so nothing is silently lost (sec 4d/4e).
8. Copy required JDBC drivers into the new tree (buildomatic/conf_source/db/...)
   and plan replacements for any driver removed at the target (sec 4c).
9. Place the license file for the target (mind the 10.x rename, sec 4h).
10. Confirm Chrome/Chromium present on the target host if crossing 7.8+ or
    installing 8.1+ (export of PDF/DOCX depends on it, sec 3).
11. Decide method (sec 4f) and Compact/Split shape (sec 4g); configure
    default_master.properties accordingly (installType, audit.db*, dbVersion for
    Oracle 23ai+, password strategy at 10.1).
12. Dry-run: `js-upgrade-samedb test` or `js-upgrade-newdb test <zip>` -- validates
    default_master.properties, app-server path, DB connectivity without changes.
13. Run the upgrade as the SAME OS user who installed the server; if prompted to
    create a keystore, abort (sec 4a).
14. Post-upgrade hygiene: clear app-server work/temp dirs; clear JIRepositoryCache
    (update item_reference = null; delete rows); clear browser cache (every guide).
15. Verify: `GET /rest_v2/serverInfo` shows the new version; log in; fill a sample
    report; test datasource connections. Skill: doctor.ps1 + smoke_test.ps1 +
    verify_report.ps1 cover serverInfo, connections, and a sample fill.
16. Reimport audit/access/monitoring data via UI Import if the hop used newdb
    (sec 4b); rerun transfer-audit-data on Split samedb.
17. Reapply UI customizations on the new source packages; rebuild and publish
    (sec 4e). Re-verify custom jars (sec 4d).
18. Re-promote or re-verify cross-env content: promote.ps1 -FromEnv/-ToEnv only
    after both ends report expected versions (sec 6).
19. Back up the NEW keystore and DB again (guides tell you to; do it).

## 6. What this means for this skill

- Migration-planning entry point is sec 0: any upgrade/migration plan produced
  with this skill must open by walking the 16 field issues (Blocker/Common
  first: keystore consistency, large-repo export/import) and stating the
  mitigation or accepted risk for each, THEN pick the ladder hop (sec 2) and
  platform prerequisites (sec 3). The sec 0 tooling roadmap is the backlog for
  new skill scripts.
- Promotion direction is one-way: promote.ps1 -FromEnv/-ToEnv must only move
  content old -> new or same-version. 10.1 exports are explicitly not importable
  into older servers, and repo schema changes exist at every release; treat any
  newer -> older move as unsupported (sec 4b).
- Gate every cross-server operation on `GET /rest_v2/serverInfo` from BOTH ends
  (doctor.ps1); warn or refuse when target < source. Never infer version from
  file naming era alone -- verify live.
- JRXML compatibility follows the JR Library, not the server marketing version:
  9.0 servers run Library 6.21.0, 10.x run Library 7/10.x. JR7-model jrxml (this
  skill's default) will not load on 9.0-or-older servers without setting Studio
  compatibility/required library version; lint before deploying to an older PROD
  (see version-matrix.md sec 4).
- Keystore awareness: content that embeds encrypted values (datasource passwords in
  server-settings exports) only moves across servers with a key export/import;
  plain repo resources (jrxml, images, .jrtx) are unaffected (sec 4a, 4b).
- If STAGE or PROD is ever upgraded: run the sec 5 checklist; afterwards rerun the
  skill's connection tests and a sample fill -- the Jakarta/Tomcat jump can change
  resource behavior with zero error at upgrade time (sec 4d).
- Which reference to open: platform question (JVM/Tomcat/DB per version) ->
  version-archive/platform-evolution.md; procedure/keystore/export question ->
  version-archive/upgrade-procedures.md; "when was X removed/deprecated" ->
  version-archive/relnotes-install-deltas.md sec 3; anything 9.0 -> 10.1 in depth
  -> version-matrix.md.
- Cookie/browser-session tooling against 10.0+ must handle per-page CSRF tokens
  (csrfguard 4.3.0); basic-auth rest_v2 calls (this skill's default) are unaffected
  (version-matrix.md sec 1/4).

## 7. Contradictions the docs leave open (reported, not resolved)

- Overlay floor at 10.0: distribution table says "from version 9.0 or later",
  overlay chapter says "versions 8.0 and later" (JasperReportsServerUpgradeGuidev10.0.0).
- Overlay floor at 10.1: table says "from version 10.0.0 or later", chapter says
  "versions 9.0 and later" (js-jrs_10.1.0_upgrade-guide).
- 10.x license file name: jaspersoft.jrs.license (10.1 UG p.83, 10.0 relnotes) vs
  jasperserver.jrs.license (10.1 UG p.44). Check both at runtime.
- newdb audit non-import dating: 10.x guides say "starting version 7.9.0"; the
  8.1/8.2/9.0 guides said only "currently" (version-archive/upgrade-procedures.md
  sec 2).

## 8. Gaps (what this corpus cannot answer)

- No native release notes for 6.x or 7.2-7.9; those eras are known only through
  the cumulative sections of the 8.x relnotes (version-archive/relnotes-install-deltas.md sec 4).
- No CE platform-support or upgrade docs for 9.0/10.x; CE facts stop at 8.2.
- No platform-support files for 5.6, 7.8, or 8.0.0/8.0.1; the exact platform state
  at those releases is interpolated from neighbors.
- Upgrade-path matrix figures extracted poorly; mid-matrix cells (e.g. 7.2 -> 7.8)
  are not individually asserted anywhere in the archive.
- ehcache/web.xml overlay-merge procedures, exact REST v1/SOAP and Flash removal
  versions, the js.config.properties key for the Chromium path, and bundled JR
  Library versions for 8.0.3-8.2.0 are absent from the doc set.
