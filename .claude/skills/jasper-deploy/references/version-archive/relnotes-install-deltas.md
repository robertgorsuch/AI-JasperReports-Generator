# JasperReports Server: Release Notes and Install-Guide Deltas for Upgrade/Migration Planning

Distilled 2026-08-04 from the extracted official PDF text files in scratchpad/doctext/.
All facts are taken from the named source files; nothing is inferred from outside
knowledge. Source file names are cited in square brackets.

---

## 1. Per-release-notes summaries

### 8.0.3 [tib_js-jrs_8.0.3_relnotes.txt]
- Type: maintenance/security release. Ships two ways: cumulative service pack
  (patch files) for 8.0.x, or full WAR file (TIB_js-jrs_8.0.3_bin.zip) usable for
  fresh install or direct upgrade from any 7.x via samedb or newdb scripts.
- New features recap for 8.0.0 (carried in this doc): Scalable Query Engine
  (Ad Hoc workers on Kubernetes), Compact vs Split installation (audit/access
  events in a separate DB), Docker/Kubernetes deployment (js-docker repo), new
  Ad Hoc/Dashboard settings panels, dashlet hyperlinks and Replace-dashlet
  action, responsive report viewer, detailed dashboard export, HTML5 High Maps /
  Tilemaps / master-detail charts, Ad Hoc execution in JasperReports IO, Java 11
  support for Studio and JRIO Pro, new connectors (ElasticSearch, Snowflake,
  AWS Athena), PostgreSQL 12 support.
- Changes in 8.0.3: OLAP Views no longer supported (OLAP and XMLA connections
  still usable in Ad Hoc); OLAP JavaScript formatter scripts disabled by default
  (olap.mondrian.scripts.enabled in js.config.properties); CVE fixes (pgjdbc,
  Xalan, Commons, Commons Text, Highcharts); new fallbackColumnWidth property in
  applicationContext-adhoc.xml; configurable input-control date formats via
  jasperserver_config.properties + js.spring.properties calendarFormatProvider;
  inputControl.handler.values.caseSensitive option; aggregate calculated fields
  computed in-memory.
- Changes in 8.0.0: XMLA server component disabled by default (deprecated since
  7.1); can be re-enabled by uncommenting JasperXmlaServlet in web.xml.
- Platform drops as of 8.0: JBoss EAP 7.0/7.1, TIBCO Data Virtualization
  7.0.7-8.1.1, all 32-bit OSes, Tomcat 7 and 8.0, WildFly 8.1-17, GlassFish,
  PhantomJS 2.1.1, PostgreSQL 9.2/9.4, MySQL 5.1, Oracle 11gR2, DB2 9.7/10.1,
  SQL Server 2012R2, JDK 1.7. Also restated: Glassfish and HP-UX dropped as of
  7.5; IE11 last supported in 7.8.0; Java 8 end of support announced; HTTP
  parameter encoding deprecated (use TLS); Rhino deprecation announced; OLAP
  views deprecated; REST API v1 and SOAP web services removed (migrate to REST
  v2); portal servers no longer certified; JFreeChart chart types no longer
  supported in Ad Hoc (migrate to Highcharts); Open Flash deprecated and the
  Flash export option removed from the report viewer (re-enable steps in latest
  6.x release notes).
- Upgrade notes: no database changes across 8.0.0-8.0.3; upgrade from 7.x uses
  WAR + samedb/newdb; upgrade from 8.0.x uses the service pack ZIP.
- Known issues relevant to upgrade: stale maven.jdbc.version references in
  buildomatic sample_conf; clustered app servers must share identical keystore
  files; org-import fails on first attempt (JS-34767); multi-tenant absolute
  resource paths now rejected (JS-34346); repo: image dashlets not exported with
  dashboards (JS-30847).
- Bundled JasperReports Library version: not stated in this document.

### 8.0.4 [js-jrs_8.0.4_relnotes_1.txt]
- Maintenance release: Simba drivers REMOVED from JasperReports Server Pro
  8.0.4 (athena-jdbc42, cassandra-jdbc42, impala-jdbc42, neo4j-jdbc42,
  spark-jdbc42); users must install publicly available or vendor drivers and
  update resources. Plus branding/copyright updates (Cloud Software Group).
- New: Java 17 supported in runtime mode, only when deployed on Tomcat 9.0.x.
- No platform-support changes and no database changes across 8.0.0-8.0.4.
- Ships as cumulative service pack (TIB_js-jrs_8.0.4_sp.zip) or full WAR
  (TIB_js-jrs_8.0.4_bin.zip; direct upgrade from any 7.x via samedb/newdb).
- Notable closed issue: JRL-1820 "Chrome Version 111 breaks export of HTML5
  charts and dashboards" (fixed here) - relevant if pinning Chrome/Chromium.
- Bundled JasperReports Library version: not stated in this document.

### 8.1.1 [tib_js-jrs_8.1.1_relnotes.txt]
- Maintenance/security release for 8.1.0. Service pack for 8.1.0, or full WAR
  (TIB_js-jrs_8.1.1_bin.zip) for direct upgrade from 8.0.x. Upgrade path: only
  8.0.x can go directly to 8.1.1; 8.0 Compact -> 8.1 Compact and 8.0 Split ->
  8.1 Split only (no Compact<->Split crossover; to reach 8.1 Split from 8.0
  Compact: upgrade to 8.1 Compact, then migrate Compact -> Split).
- 8.1.0 new features (recap): Report Bursting; Ad Hoc crosstab UI changes;
  User Favorites; Server Monitoring Ad Hoc views; Admin Console (beta,
  availableAdminConsole property); fallbackColumnWidth property; JasperReports
  Web Studio integration (pluggable report editor); Section 508 / WCAG 2.1 A+AA
  accessibility on JR Library pages; OpenTelemetry tracing of report executions
  and input controls; OpenShift support; PostgreSQL 13/14 certified (datasource
  and repository), Elasticsearch 8.2.
- Changes in 8.1.0: Diagnostic JMX server disabled by default (re-enable in
  applicationContext-diagnostic.xml); Rhino JavaScript engine REMOVED (reports
  using JavaScript need Rhino 1.7.14 jar manually restored to WEB-INF/lib);
  non-ISO date formats for input controls via messagesCalendarFormatProvider.
- Changes in 8.1.1: OLAP Views no longer supported; OLAP scripts disabled by
  default; CVE fixes (same list as 8.0.3).
- Platform drops as of 8.1: SQL Server 2014, Elasticsearch 7.13.4 (plus all the
  8.0-era drops restated).
- Important Upgrade Information (history restated in this doc): 8.0 introduced
  Compact/Split; 7.9 has database changes; 7.8 switched export rendering to the
  Chromium engine and REMOVED PhantomJS/Rhino support; 7.5 changed encryption
  keys (affects all deployments), UI changes may break custom themes, MongoDB
  query language changes, Impala/Simba driver replacement; 7.2 removed legacy
  dashboards (no longer viewable or editable); 6.0.x/6.1.x/6.2.x/6.4.x contained
  upgrade-impacting changes (6.2.1 replaced Impala/Simba drivers).
- No database changes between 8.1.0 and 8.1.1.
- Known issues relevant to upgrade: Oracle non-default SID breaks js-ant
  import-minimal-pro; keystore files must match across clustered app servers.
- Bundled JasperReports Library version: not stated in this document.

### 8.2.0 commercial [tib_js-jrs_8.2.0_relnotes.txt]
- New features: JDK 17 supported in runtime mode, only on Tomcat 9.0.x; Report
  Splitting; drill-down back navigation; superuser-enabled JDBC driver .JAR
  upload from UI; Highcharts upgraded to 10.1.0 (breadcrumb drill navigation);
  XLSX export option in Scheduler; failed-login account lockout (LDAP and
  External DB auth only; CAS not supported for this feature); JR Library text
  measurer property net.sf.jasperreports.text.measurer.factory=naive for fast
  CSV/XLSX export; resolveRuntimeAdhocFilterLabels property; Hibernate and
  Spring Security update; Access-Control-Allow-Private-Network header support
  for Visualize.js under Chrome PNA; new OS/app-server/DB support (RHEL 8.7,
  Windows 11/Server 2022, Ubuntu 20.04/22.04, JBoss EAP 7.2, WebLogic 12.2.1.4
  and 14.1.1.0, PostgreSQL 13/14, ElasticSearch 8.2.0, AWS Athena 3).
- Changes in functionality: Simba drivers removed (as of 8.0.4, restated);
  Hibernate upgraded 5.2 -> 5.6 (hibernate.properties moved to WEB-INF/classes);
  old Excel formats .xls / .xls-Paginated REMOVED, replaced by .xlsx /
  .xlsx-Paginated (plus Excel metadata exporter); SVG placement config for
  reportExecutions; sample themes DEPRECATED (to be removed in future releases);
  Jaspersoft OLAP views DEPRECATED (migrate to Ad Hoc views on Mondrian or XMLA
  connections); aggregate calculated fields always in-memory; recommended
  architecture for third-party-cookie policies (report execution and input
  control caches no longer session-dependent).
- Platform drops as of 8.2: Windows 2012, macOS 10.8-10.15, Ubuntu 14.04/18.04,
  WebLogic 12.2.1.1-12.2.1.3, WebSphere 9.0.5.1, MySQL 5.5.62/5.6.46, Oracle
  12.1.0.2/12cR2/12.2.0.1, DB2 10.5, SQL Server 2016, AWS Athena 1, AWS RDS
  PostgreSQL 11, Snowflake, Kubernetes 1.19/1.20, JBoss Teiid 9.1.1, PostgreSQL
  9.5.x/9.6.x/10.x/11.x.
- Upgrade: single WAR distribution TIB_js-jrs_8.2.0_bin.zip (no service pack
  path mentioned); direct upgrade from 8.x; from 7.x go via latest 8.0.x; from
  6.x go 6.x -> 7.1.x -> 8.0.x -> 8.2.0 (oldest versions via 6.3.x first).
  Compact/Split rule as in 8.1 (no crossover; Compact->Split is a migration).
- Important upgrade notes: js-upgrade-newdb.sh/bat does NOT import access,
  audit, monitoring data; re-import them afterward via the UI Import page. UI
  customizations (JS/CSS) must be re-applied to source packages and rebuilt
  after upgrade.
- Bundled JasperReports Library version: not stated (only "new version of
  JasperReports Library" with the text-measurer property; Highcharts 10.1.0).

### 8.2.0 Community [js-jrs-ce_8.2.0_relnotes.txt]
- Line-for-line identical in content to the commercial 8.2.0 release notes file
  (verified by diff of all non-empty lines; zero unique lines). All statements
  above apply.

### 9.0.0 [js-jrs_9.0.0_relnotes.txt]
- New features (server): Alerting in Report Viewer (Quartz-based; Schedules and
  Alerts page); chart drill up/down; dashlet hyperlink type for Studio reports
  in dashboards; advanced date-time calculations (Year to Date, Period over
  Period; date grouping functions RENAMED: Quarter -> Quarter and Year, Month ->
  Month and Year); schedule status column; default visualization type setting;
  Always-prompt setting; Ad Hoc Component in JRXML (Ad Hoc reports track parent
  Ad Hoc view); JNDI security with new read-only jasperserverSystemAnalytics and
  jasperserverAuditAnalytics data sources
  (metadata.hibernate.jndi.restrictedAccess.enabled); Trino integration; OAuth
  with OpenID out of the box (Okta, AWS Cognito, ...; single properties file
  config); customizable logging context (USER_ID, SESSION_ID, ...); Office 365
  scheduler mail via Microsoft Graph API; Admin Console enhancements (Alerts tab
  beta); JasperReports Web Studio 3.0.0 integration (two additional web apps to
  deploy, extra app-server memory needed); blank-JRXML report unit flow;
  OpenTelemetry tracing; multi-tenant scheduler mail config;
  undeletable-roles/users config; outputControlMapForContexts;
  calenderTrigger/simpleTrigger resetStartTimeOnImport properties for imported
  scheduled jobs.
- Studio 9.0.0: Eclipse 4.29, bundled JRE Adoptium Temurin OpenJDK 17.0.8.1+1,
  FastExcel-Reader 0.15.6, full support for JasperReports Library 6.21.0
  (i.e., the JR Library level of the 9.0.0 generation).
- JR Library 9.0.0: PDF/A-2a/2b/2u/3a/3b/3u, PPTX table export, WEBP images.
- Changes: Progress JDBC drivers (TI*.jar: TIsqlserver, TIoracle, TIdb2,
  TImongodb, TIredshift, TIsforce, TIhive, TIimpala, TIcassandra,
  TIgooglebigquery, TIautorest, TIsparksql) REMOVED - install native vendor
  drivers; data-type behavior differences documented in Upgrade Guide "Changes
  in 9.0 That May Affect Your Upgrade". Ad Hoc Component: only newly created
  reports get it; importing old resources risks overwriting the new
  /public/templates (restore with js-ant import-minimal-pro); custom Ad Hoc
  templates should be updated. JNDI: resources on jdbc/jasperserver should move
  to jdbc/jasperserverSystemAnalytics (and Audit equivalent) if enabling JNDI
  security. OAuth configs in applicationContext-externalAuth-*.xml must be
  migrated to the new format. Alerting raises org.quartz.threadPool.threadCount
  from 2 to 4. AnonymousUser can no longer be deleted. Visualize.js container
  element must not contain script elements. deploy.base.local.url property for
  scheduler dashboard export.
- Platform: added WebLogic 12.2.1.4 and Tomcat 8.5.x as compatible-not-
  certified, Trino, RHEL 9.0, JWS 5.7.2, Kubernetes 1.25-1.28. Removed: WebSphere
  8.5.5.x (server); Studio drops Xalan, outdated SQLite JDBC, Progress drivers.
- Upgrade paths: any 8.x -> 9.0.0 direct (8.2.0 Compact -> 9.0 Compact only,
  Split -> Split only); 7.x via latest 8.0.x; 6.x via 7.1.x then 8.0.x.
  Upgrade file: js-jrs_9.0.0_bin.zip (WAR distribution). Database changes exist
  between 8.0.x/8.1.x/8.2.x and 9.0.0.
- Known issues relevant to upgrade: Oracle non-default SID vs
  import-minimal-pro; cluster keystore matching; first-attempt org import error.

### 10.0.0 [js-jrs_10.0.0_relnotes_28Jan.txt]
- New features (server): Jakarta upgrade - runs on Jakarta EE 10, Apache Tomcat
  10.1.24 onwards (codebase moved to jakarta namespace; Spring and Commons DBCP
  upgraded; ehcache2 replaced by JCache API, Infinispan the only verified
  implementation); Hibernate 6 (hbm.xml mappings replaced by JPA @Entity);
  enhanced Ad Hoc tooltips; redesigned Ad Hoc Layout Band; one-click Print to
  PDF for reports/dashboards/Ad Hoc; filter/dashlet visual indicators; edit
  external Ad Hoc view from dashboard; isAlertEnabled flag to disable Alerting;
  accessibility improvements; NEW in-house license manager - license file
  renamed to jaspersoft.jrs.license; expanded telemetry (usage/compliance data
  in Diagnostic Report); HTML Pro component (Playwright 1.50.0); SendGrid API
  for scheduler email; custom input controls (show/hide, enable/disable, title
  via expressions); show/hide multiple columns in JIVE tables.
- Studio 10.0.0: Eclipse 4.36 + Java 21 minimum; HTML Pro (Professional only);
  license file jaspersoft.jss.license; new JRXML 7 model (warning when
  publishing; set compatibility/required library version); QR-code offline
  activation for Community.
- Changes: native connectors certified (Elasticsearch, Neo4j, MongoDB, Hive,
  Impala, Cassandra, Spark SQL, Snowflake, Azure SQL, BigQuery, Autonomous REST,
  Athena); csrfguard 3.1.0 -> 4.3.0 (TokenPerPage forced true); library stack:
  Hibernate 6.6.x, Spring 6.2.x, Spring Security 6.5.x, React 18, MUI 6, Node 20,
  Highcharts 11.1.0, commons-dbcp 2.12.0, Lucene 9. Studio: MongoDB connector,
  Google Maps, and CVC now Professional-only; JasperReports IO no longer bundled;
  JRXML model 6.x -> 7 (do not publish JRXML 7 to older servers without setting
  compatibility); SOAP protocol no longer supported for publishing from Studio
  to server (REST v2 only); centralized Log4j2 logging.
- Platform: added SQL Server 2022, MySQL 8.4, Tomcat 10.1.24+, Tomcat 11.0.11+,
  JBoss EAP 8, OpenJDK/Oracle JDK 17, WildFly 36.0.1, PostgreSQL 16/17,
  Debian 11. JR Library 7 is the supported library generation (Studio ships
  JR Library 7.0.5). Removed as of 10.0.0: viewing of OLAP views, PostgreSQL
  12/13, MySQL 5.7, WebSphere (WAS) 9.0.5.5, WebLogic 14.1.1.0, CentOS 6/7;
  Studio removes Subclipse/SVN plug-in, JasperReports IO, Derby jars, old HTML
  and Sort components, Snowflake and ElasticSearch PRO connectors, Rhino and
  Closure compiler.
- Upgrade paths: only 9.0.0 -> 10.0.0 direct (Compact->Compact, Split->Split);
  8.x must first go to 9.0.0; 7.x via latest 8.0.x; 6.x via 7.1.x then 8.0.x.
  Upgrade file: js-jrs_10.0.0_bin.zip. Database changes between 8.x.x, 9.0.0 and
  10.0.0.
- Security section documents many CVE-driven jar upgrades (elasticsearch-jdbc,
  Netty, snowflake-jdbc, Infinispan, ehcache, PostgreSQL jar, Spring, Lucene 9,
  POI, httpclient5, ...).

### 10.1.0 [js-jrs_10.1.0_relnotes.txt]
- New features (server): centralized Scheduler Dashboard in Admin Console
  (job states, restart executions, history); password history validation (off
  by default); modernized one-way-hash password storage (backward compatible);
  MIGRATION FROM CASTOR TO JACKSON for serialization - resources exported from
  10.1.0 CANNOT be imported into older versions; Apache Tiles retired in favor
  of JSP Tag Files (custom JSP overlays must change tiles:insertTemplate to
  <tmpl:*> tags in WEB-INF/tags/templates/).
- Studio 10.1.0: JR Library PDF exporter supports Section 508 / PDF/UA / WCAG
  tagging (Professional); NOTE: accessibility features REMOVED from Community
  Edition starting 10.1.0 - CE reports throw "Tag PDF not supported" on first
  run; SSO (browser) login option capturing JSESSIONID; logging JVM properties
  jss.logging.tmpdir and jss.logging.redirectSystemStreams.
- Changes: PostgreSQL JDBC driver 42.7.11; Spring 6.2.17, Spring Security
  6.5.9, jersey 4.0.2, jakarta.jms-api 3.1.0 and other library bumps.
- Platform: added Oracle 23ai and 26ai, JDK/Jakarta 21. JR Library 7.0.8 is the
  supported library level (Studio: Eclipse 4.38, JR Library Pro 10.1.0, Temurin
  JDK 21.0.10.7). Removed as of 10.1.0: MySQL 8.0 (server); Studio drops
  OLAP/Mondrian data adapters, TIBCO Maps plug-in, TIBCO Data Virtualization
  driver, Jakarta SOAP API library 3.0.2.
- Upgrade paths: 9.0.x or 10.0.x -> 10.1.0 direct (Compact->Compact,
  Split->Split). Upgrade file: js-jrs_10.1.0_bin.zip. Database changes between
  9.0.0, 10.0.0 and 10.1.0.

### 9.0.0 for AWS Marketplace [JS-jrs_9.0.0_aws-relnotes.txt]
- 9.0.0 AMI: latest Amazon Linux 2 base AMI. Marketplace CFT: dropped m5.large,
  default now m5.xlarge (also m5.2xlarge, r5a.xlarge, r5a.2xlarge); dropped
  GovCloud; dropped the Quick Start CFT entirely.
- Historical AMI stack (stated in same doc): 7.5.2 / 7.8.1 / 7.9.x / 8.0.1 AMIs
  ship Tomcat 9.0.54, Java 11, PostgreSQL 11 (8.0.1: PostgreSQL 12);
  upgrade_tomcat.sh script in /etc/jasperserver; single systemd init service;
  8.0.1 replaced Classic Load Balancer with ALB and LaunchConfig with
  LaunchTemplate; tightened IAM permissions (breaks RDS/Redshift datasource
  auto-discovery unless re-granted).

---

## 2. Install-architecture evolution (4.7 / 5.x / 7.1 / 8.1 / 8.2 / 9.0 / 10.1)

Sources: jasperreports-server-install-guide__legacy.txt (4.7),
jasperreports-server-install-guide_0.txt (5.0), _1.txt (5.1), _2.txt (5.2),
_3.txt (5.5), _10.txt (7.1), _6.txt (8.1), js-jrs_8.2.0_install-guide.txt,
js-jrs_9.0.0_installation-guide.txt, js-jrs_10.1.0_installation-guide.txt.

### Distribution formats
- 4.7-5.5: native binary installers per OS and bitness, e.g.
  jasperreports-server-4.7-windows-x86-installer.exe / -linux-x86-installer.run
  / -osx installers (32- and 64-bit; 5.5 drops 32-bit macOS). WAR file
  distribution exists in parallel; 5.5 explicitly says "For production
  environments, use the WAR file distribution." [4.7, 5.5 guides]
- 7.1 (TIBCO era): installers TIB_js-jrs_7.1.0_win_x86_64.exe / _linux_x86_
  64.run / _macosx_x86_64.zip; WAR distribution TIB_js-jrs_7.1.0_bin.zip;
  "For production environments, use the stand-alone WAR file distribution."
  [7.1 guide]
- 8.1/8.2: chapters retitled "Running the Binary Installer for Evaluation" and
  "Installing the WAR File for Production" - the installer is now explicitly
  the evaluation path. Installers TIB_js-jrs_8.x.0_{win,linux,macosx}_x86_64;
  WAR TIB_js-jrs_8.x.0_bin.zip. [8.1, 8.2 guides]
- 9.0: rebranded file names js-jrs_9.0.0_win_x86_64.exe / .run; WAR
  js-jrs_9.0.0_bin.zip; same evaluation-vs-production split. [9.0 guide]
- 10.1: js-jrs_10.1.0 installer names and js-jrs_10.1.0_bin.zip; the guide's
  overview sentence describes the product as "available in a WAR file for
  production" (installer chapter still present for evaluation). [10.1 guide]

### Bundled Tomcat / PostgreSQL / Java
- 4.7-5.2: bundled Tomcat 6 ("the installer puts an instance of Tomcat 6");
  supported app servers Tomcat 5.5/6/7, JBoss 5.1/7.1, GlassFish 2.1/3.0.
  64-bit installer bundles Java 6 and PostgreSQL 9. [4.7-5.2 guides]
- 5.5: bundle lists Apache Tomcat 7; 64-bit installer bundles Java 7 and
  PostgreSQL 9. [5.5 guide]
- 7.1: bundle = Apache Tomcat 8, Java 1.8 runtime, PostgreSQL 9, PhantomJS
  (described as "scriptable headless WebKit, required for exporting
  dashboards"). Known issue: do not install PhantomJS via the bundled installer
  on Windows 7+; install it separately. [7.1 guide]
- 8.1/8.2/9.0/10.1: the Bundled Components table no longer states version
  numbers (just "Apache Tomcat" and "PostgreSQL Database"; versions are in the
  Platform Support datasheet). Sample default_master values reference Tomcat 9.0
  in 8.1/8.2/9.0 and Tomcat 11.0 in 10.1; appServerType lists evolve:
  4.7: tomcat5/6/7, jboss, jboss7, glassfish2/3;
  5.1-5.5: adds jboss-eap-6, jboss-as-7;
  7.1: tomcat [jboss-eap-6, wildfly, glassfish];
  8.1-9.0: tomcat [jboss-eap-7, wildfly];
  10.1: tomcat [jboss-eap-8, wildfly]. [respective guides]
- JDK notes: 8.2 guide: "As of release 8.2, only Tomcat 9.0.x ... is supported
  ... on a system with JDK 17" (extra installation step required); 9.0 guide
  repeats it; 10.1 guide: "As of release 10.1.0, Tomcat 11.0.x is supported ...
  with JDK 17/JDK 21." [8.2, 9.0, 10.1 guides]

### js-install scripts and buildomatic
- Constant across all versions 4.7 -> 10.1: WAR distribution includes
  js-install.bat / js-install.sh at <js-install>/buildomatic, driven by a single
  default_master.properties created by copying <db>_master.properties from
  buildomatic/sample_conf and editing it. Manual buildomatic steps remain the
  alternative. [all guides]
- Notable default_master.properties settings by era:
  - 5.5: password encryption toggle appears (encrypt=true) for passwords on the
    file system under buildomatic. [5.5 guide]
  - 7.1: same password encryption section; maven.jdbc.artifactId /
    maven.jdbc.version JDBC driver pinning (also used for JBoss
    jboss-deployment-structure.xml alignment). [7.1, 8.1 guides]
  - 8.1/8.2: Split installation configuration lives in default_master
    ("Uncomment below settings ONLY for split installation" - separate audit DB
    settings). [8.1, 8.2 guides]
  - 9.0: adds JNDI security installation settings in default_master. [9.0 guide]
  - 10.1: adds password strategy/algorithm settings in default_master.
    [10.1 guide]
- DB2 still requires manual database creation (8-char names jsprsrvr/jsaudit)
  before js-install in all eras sampled. [8.1 guide]

### Default ports and paths
- Web app URL is http://<hostname>:8080/jasperserver-pro in every version
  sampled (installer scans "open Tomcat ports from 8080 up" in 8.1+).
  [4.7-10.1 guides]
- Bundled PostgreSQL uses default port 5432; if taken, the installer prompts
  for an alternative. [4.7-7.1 guides]
- Default install directories (7.1 onward): Windows
  C:\Jaspersoft\jasperreports-server-<ver>, Linux root
  /opt/jasperreports-server-<ver>, non-root <USER_HOME>/jasperreports-server-
  <ver>, macOS /Applications/jasperreports-server-<ver>. [7.1-10.1 guides]
- 9.0/10.1 add optional JasperReports Web Studio endpoints
  jrws.repo.url=http://localhost:8080/repo and
  jrws.jrio.url=http://localhost:8080/jrio. [9.0, 10.1 guides]

### License file handling
- 4.7-5.0: evaluation license installed by default; expires (login blocked,
  server still starts). Replace with commercial license; license sits in
  <js-install> by default, relocatable via -Djs.license.directory in Tomcat
  startup. [4.7, 5.0 guides]
- 5.1-9.0: license file name is jasperserver.license in the deployed server
  root; stop server, replace file, clear <tomcat>/work, restart. Separate
  procedure for Tomcat running as a Windows service. [5.1-9.0 guides]
- 10.x: new in-house license manager; the file is renamed - 10.1 guide:
  "Replace the license named jasperserver.license ... The file name should be:
  jaspersoft.jrs.license." (10.0.0 release notes introduced
  jaspersoft.jrs.license and note correct permissions must be set on it.)
  [10.1 guide; js-jrs_10.0.0_relnotes_28Jan.txt]

### Headless-browser dependency for report/dashboard export
- 7.1: PhantomJS is the bundled/optional headless engine for exporting
  dashboards. [7.1 guide]
- 7.8: server switched to the Chromium JavaScript engine for exporting reports
  and dashboards to PDF and other formats; PhantomJS/Rhino support removed
  (stated in Important Upgrade Information of 8.1.1/8.2.0 release notes).
- 8.1+ installer has a dedicated "Selecting a Chrome/Chromium Configuration"
  step with three options: use existing Chrome/Chromium (path auto-detected at
  default locations, Chrome checked before Chromium), download during install
  (links provided), or install without it - in which case reports and
  dashboards CANNOT be exported to PDF, DOCX, and other formats. A different
  browser (e.g. Edge) is configured by setting the path in
  js.config.properties. WAR-file installs must install/configure
  Chrome/Chromium separately (details in the Administrator Guide).
  [8.1, 8.2, 9.0, 10.1 guides]
- 9.0: deploy.base.local.url in js.config.properties supports scheduler-side
  dashboard export via the headless browser. [js-jrs_9.0.0_relnotes.txt]

### Keystore creation at install time
- Not present in the 4.7-7.1 guides (no keystore content at all in those
  files).
- 8.1 onward: "Installing JasperReports Server automatically generates
  encryption keys that reside on the file system. These keys are stored in a
  dedicated ... Jaspersoft keystore" (.jrsks and .jrsksp files); guides warn
  about permission conflicts when 7.2.x/7.5.x and newer versions share a
  machine, require identical keystore files across cluster nodes, and describe
  backup/decode procedures. The 8.1.1/8.2.0 release notes date the encryption-
  key change to release 7.5 ("changes to encryption keys will affect all
  deployments"). 9.0/10.1 guides add a manual-deploy step: copy
  buildomatic/keystore.init.properties to WEB-INF/classes.
  [8.1, 8.2, 9.0, 10.1 guides; tib_js-jrs_8.1.1_relnotes.txt]

---

## 3. Deprecation timeline

Format: feature - deprecated (version, source) - removed/disabled (version,
source). "Restated in 8.x relnotes" means the fact appears in the cumulative
ending-support list of tib_js-jrs_8.0.3/8.1.1/8.2.0 relnotes.

- Legacy dashboards (dashboards v1): removed in 7.2 - "no longer available to
  view or edit starting in the 7.2 release" [8.1.1/8.2.0 relnotes, Important
  Upgrade Information].
- Original REST API v1 and SOAP web services: removed - "We removed the
  original REST API v1 and SOAP web services ... migrate to Jaspersoft v2 REST
  API" (listed among 7.5-era/8.0 cumulative changes; exact removal version not
  stated in these docs). Consequence: portal servers (JBoss/Liferay) no longer
  certified. [8.0.3/8.1.1/8.2.0 relnotes]. SOAP publishing from Jaspersoft
  Studio to the server removed in 10.0.0 (REST v2 only)
  [js-jrs_10.0.0_relnotes_28Jan.txt]; Studio drops the Jakarta SOAP API library
  in 10.1.0 [js-jrs_10.1.0_relnotes.txt].
- Open Flash / Flash charts and export: deprecated in favor of HTML5; Flash
  export option removed from the report viewer (re-enable instructions live in
  the latest 6.x release notes, implying the removal predates 7.x; exact
  version not stated in these docs). [8.0.3/8.1.1/8.2.0 relnotes]
- JFreeChart chart types in Ad Hoc: no longer supported (migrate to
  Highcharts); stated in the 8.0-era cumulative list. [8.0.3 relnotes]
- PhantomJS: bundled component at 7.1 [7.1 install guide]; support REMOVED in
  7.8 when Chromium became the export engine [8.1.1/8.2.0 relnotes]; PhantomJS
  2.1.1 listed as no-longer-supported third-party software as of 8.0
  [8.0.3 relnotes].
- Rhino JavaScript engine: deprecation announced in the 8.0-era list ("will be
  deprecating Rhino in a future release") [8.0.3 relnotes]; REMOVED in 8.1.0
  (manual re-add of Rhino 1.7.14 jar restores JS-dependent reports)
  [8.1.1 relnotes]. Studio removes Rhino + Closure compiler in 10.0.0
  [10.0.0 relnotes].
- XMLA server component (OLAP XMLA-as-a-server): deprecated since 7.1; disabled
  by default in 8.0.0 (re-enable via JasperXmlaServlet in web.xml); XMLA client
  connections remain usable. [8.0.3 relnotes]
- Jaspersoft OLAP views: deprecated in the 8.0-era list; "OLAP Views no longer
  supported" stated in Changes in 8.0.3 and 8.1.1 (OLAP/XMLA connections still
  usable in Ad Hoc); deprecation restated in 8.2.0 (migrate to Ad Hoc on
  Mondrian/XMLA); VIEWING of OLAP views removed in 10.0.0. Studio removes
  OLAP/Mondrian data adapters in 10.1.0. [8.0.3, 8.1.1, 8.2.0, 10.0.0, 10.1.0
  relnotes]
- OLAP JavaScript formatter scripts: disabled by default in 8.0.3/8.1.1
  (olap.mondrian.scripts.enabled). [8.0.3, 8.1.1 relnotes]
- Diagnostic JMX server: disabled by default in 8.1.0. [8.1.1 relnotes]
- TIBCO Data Virtualization: support for TDV 7.0.7-8.1.1 dropped as of 8.0
  [8.0.3 relnotes]; TDV driver removed from Studio in 10.1.0 [10.1.0 relnotes].
- TIBCO Maps plug-in: removed from Studio in 10.1.0. [10.1.0 relnotes]
- Simba drivers (athena/cassandra/impala/neo4j/spark-jdbc42): removed in 8.0.4
  (restated as of 8.2.0). [8.0.4, 8.2.0 relnotes]
- Progress JDBC drivers (TI*.jar): removed in 9.0.0; migrate to native vendor
  drivers (data-type behavior differences flagged). [9.0.0 relnotes]
- Old Excel export formats (.xls, .xls-Paginated): removed in 8.2.0, replaced
  by .xlsx / .xlsx-Paginated. [8.2.0 relnotes]
- Sample themes: deprecated in 8.2.0, "will be removed in the future releases".
  [8.2.0 relnotes] (7.5 UI changes were already flagged as potentially breaking
  custom themes [8.1.1 relnotes, Important Upgrade Information].)
- Static/dynamic HTTP parameter encoding: deprecation announced (8.0-8.2
  cumulative list); use TLS instead. Removal version not stated. [8.0.3-8.2.0
  relnotes]
- Java 8: end of support announced in the 8.x cumulative list ("in a subsequent
  version"); migrate to Java 11. [8.0.3 relnotes] JDK 17 runtime arrives in
  8.0.4/8.2.0 (Tomcat 9 only); JDK 17/21 with Tomcat 10.1/11 at 10.x.
  [8.0.4, 8.2.0, 10.0.0, 10.1.0 relnotes; 10.1 install guide]
- Internet Explorer 11: 7.8.0 is the last supporting version. [8.0.3 relnotes]
- GlassFish and HP-UX: no longer certified as of 7.5. [8.0.3 relnotes]
- ehcache2: replaced by JCache API (Infinispan) in 10.0.0. [10.0.0 relnotes]
- Apache Tiles: retired in 10.1.0 (JSP Tag Files; custom overlays must be
  updated). [10.1.0 relnotes]
- Castor serialization: replaced by Jackson in 10.1.0; exports from 10.1.0 are
  not importable into older releases. [10.1.0 relnotes]
- JasperReports IO: no longer bundled with Studio as of 10.0.0. [10.0.0
  relnotes]
- Studio Subclipse (SVN) plug-in, Derby jars, old HTML and Sort components,
  Snowflake and ElasticSearch PRO connectors: removed from Studio in 10.0.0.
  [10.0.0 relnotes]
- PDF accessibility features: removed from Community Edition library builds
  starting 10.1.0 ("Tag PDF not supported" in CE). [10.1.0 relnotes]
- WebSphere: 8.5.5.x dropped at 9.0.0; WAS 9.0.5.5 dropped at 10.0.0. [9.0.0,
  10.0.0 relnotes]

---

## 4. Gaps and caveats

- Java applets: no statement about applets was found in any of the reviewed
  files; the deprecation timeline for applets cannot be sourced from this set.
- Bundled JasperReports Library version is NOT stated in the 8.0.3, 8.0.4,
  8.1.1, or 8.2.0 release notes. It is only explicit from 9.0.0 onward
  (JR Library 6.21.0 generation at 9.0.0; JR Library 7 / Studio 7.0.5 at
  10.0.0; JR Library 7.0.8 / Studio JR Library Pro 10.1.0 at 10.1.0).
- No 6.x, 7.2-7.9, or 8.1.0/8.2.x-patch release notes are in the file set;
  facts about 6.x, 7.2, 7.5, 7.8, 7.9 come from the cumulative "Important
  Upgrade Information" and "Changes in Platform Support" sections of the 8.x
  release notes, not from those releases' own notes.
- No 6.x or 7.5/7.8/7.9 install guides are present; the 5.5 -> 7.1 jump hides
  when Tomcat 7->8 and PhantomJS bundling actually happened between those
  versions. Similarly 7.1 -> 8.1 hides the exact guide edition that introduced
  the Chrome/Chromium installer step (release notes date the engine switch to
  7.8) and the keystore generation (release notes date the key change to 7.5).
- The 9.0 and 10.1 installation guides were skimmed for deltas only, per task
  scope; their full body (e.g., complete Split-installation and JNDI-security
  walkthroughs) was not distilled line by line.
- Exact removal versions for REST v1/SOAP and the Flash export option are not
  stated in the reviewed docs (only "we removed" in cumulative lists and a
  pointer to 6.x release notes for Flash re-enablement).
- The old Excel (.xls) removal is documented in the 8.2.0 release notes; the
  install guides do not mention it.
- Chrome/Chromium executable path property name: the install guides say to set
  the path "in the js.config.properties file" but do not name the property key
  in the extracted text.
