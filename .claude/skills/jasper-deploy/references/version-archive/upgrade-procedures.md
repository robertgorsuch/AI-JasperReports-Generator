# JasperReports Server Upgrade Guides - Distilled Reference

Sources (extracted plain text of official Jaspersoft PDFs, in scratchpad/doctext/):

| Shorthand | File | Actual guide |
|---|---|---|
| [5.6] | jasperreports-server-upgrade-guide__legacy.txt | JRS 5.6 Upgrade Guide |
| [8.0] | jasperreports-server-upgrade-guide__r93.txt | TIBCO JRS 8.0 Upgrade Guide |
| [8.1] | tib_js-jrs_8.1.0_upgrade-guide.txt | TIBCO JRS 8.1.0 Upgrade Guide (Version 0722-JSP81-15) |
| [8.1b] | tib_js-jrs_8.1.0_upgrade-guide_1.txt | Same guide version 0722-JSP81-15, later re-issue (copyright 2005-2023 vs 2005-2022); content substantively identical |
| [8.2] | js-jrs_8.2.0_upgrade-guide.txt | JRS 8.2.0 Upgrade Guide (commercial, Cloud Software Group) |
| [8.2ce] | js-jrs-ce_8.2.0_upgrade-guide.txt | JRS CE 8.2.0 Upgrade Guide (Community Edition) |
| [9.0] | js-jrs_9.0.0_upgrade-guide.txt | JRS 9.0.0 Upgrade Guide (January 2024) |
| [10.0] | JasperReportsServerUpgradeGuidev10.0.0.txt | JRS 10.0.0 Upgrade Guide (November 2025) |
| [10.1] | js-jrs_10.1.0_upgrade-guide.txt | JRS 10.1.0 Upgrade Guide (July 2026) |

All statements below are taken from these documents only. Quotes preserve the docs' own wording (including their typos, e.g. "updgrade").

---

## 1. Supported source versions per target

### Target 5.6 [5.6]
- Direct samedb path: 5.5 -> 5.6 (Chapter 3 "Upgrading from 5.5 to 5.6", js-upgrade-samedb).
- Direct newdb path: 3.7 - 5.2 -> 5.6 (Chapter 4 "Upgrading from 3.7 - 5.2 to 5.6", export + js-upgrade-newdb).
- Overlay zip: "Supports upgrade starting with version 4.0" - explicitly lists sources "4.0, 4.0.1, 4.1, 4.2.1, 4.5.1, 4.5.2, 4.7, 4.7.1, 5.0, 5.0.1, 5.1, 5.2, 5.5".
- WAR file distribution: "Supports upgrade starting with version 3.7".
- Older sources (Chapter 5): "If you are running JasperServer version 3.5, you must upgrade in two steps: 1. Upgrade from version 3.5 to version 3.7. 2. Upgrade from version 3.7 to version 5.6." and "If you are running a JasperServer version earlier than 3.5, first upgrade to 3.7, then to 5.6."

### Target 8.0 [8.0]
- Direct samedb: 7.9 -> 8.0 (Chapter 3). Direct newdb: 7.1.x - 7.5.x -> 8.0 (Chapter 4).
- Both overlay zip and WAR zip: "Supports upgrade ... from version 7.1 or later."
- Matrix note: "Versions prior to 6 are no longer supported and must be upgraded to version 6.3 first. You may also need to updgrade in several steps through an intermediate version." Matrix covers sources 6.0.x-7.9.x with samedb along the diagonal (n to n+1) and newdb for longer jumps.
- Stepping stones (Chapter 6 "Upgrading JasperReports Server 6.4.x or Earlier"):
  - "If you're running JasperReports Server 3.7 through 4.2: 1. Upgrade to the latest version of 6.3.x. 2. Upgrade 6.3.x to the latest version of 7.1.x. 3. Upgrade 7.1.x to version 8.0."
  - "If you're running JasperReports Server 4.5 through 5.x: 1. Upgrade to the latest version of 6.4.x. 2. Upgrade from 6.4.x to the latest version of 7.1.x. 3. Upgrade from 7.1.x to version 8.0."
  - "If you're running JasperReports Server 6.0 through 6.4.x: 1. Upgrade to the latest version of 7.1.x. 2. Upgrade from 7.1.x to version 8.0."

### Target 8.1 [8.1][8.1b]
- Direct samedb: 8.0 -> 8.1 (Chapter 3). Direct newdb: 7.1.x - 7.9.x -> 8.1 (Chapter 4).
- Overlay and WAR zips: "Supports upgrade ... from version 7.1 or later."
- Same "prior to 6 ... upgrade to 6.3 first" matrix note, same three stepping-stone recipes as 8.0 with final step to 8.1.

### Target 8.2 commercial [8.2]
- Direct samedb: 8.1 (chapter titled "Upgrading from 8.x to 8.2"; matrix shows samedb from 8.0.x and 8.1.x). Direct newdb: 7.1.x - 7.9.x -> 8.2 (Chapter 4).
- Overlay and WAR zips: "Supports upgrade ... from version 7.1 or later."
- Same 6.3-first note and the same three stepping-stone recipes ending "...to version 8.2".

### Target 8.2 CE [8.2ce]
- Same paths as commercial 8.2 but WAR-only: distribution is only "WAR File Distribution Zip ... Supports upgrade from version 7.1 or later. File name is: TIB_js-jrs-cp_8.2.0_bin.zip". No overlay chapter exists.
- Same upgrade-paths matrix (6.x/7.x/8.0.x/8.1.x) and same 6.3-first note; same stepping-stone recipes.

### Target 9.0 [9.0]
- Direct samedb: 8.2.x -> 9.0 ("Upgrading from 8.2.x to 9.0"). Direct newdb: 8.0.x - 8.1.x -> 9.0.
- Overlay zip: "Supports upgrade to 9.0.0 from version 8.0 or later." WAR zip: "Supports upgrade from version 8.0 or later."
- Matrix still shows 7.x sources with newdb; "Versions prior to 6 are no longer supported and must be upgraded to version 6.3 first."
- Stepping stones: "If you are running JasperReports Server 6.0 through 6.4.x: 1. Upgrade to the latest version of 7.1.x. 2. Upgrade from 7.1.x to version 8.2. 3. Upgrade from 8.2 to version 9.0." And: "If you are running a JasperServer version earlier than 3.7, first upgrade to 3.7.0, then to 6.3.x, then 7.x to 8.x and then to 9.0."

### Target 10.0.0 [10.0]
- Direct samedb: 9.0 -> 10.0.0 ("Upgrading from 9.0 to 10.0.0"). Direct newdb: 8.0.x - 8.2 -> 10.0.0 ("Upgrading from 8.0.x - 8.2 to 10.0.0").
- Overlay zip: "Supports upgrade to 10.0.0 from version 9.0 or later." WAR zip: "Supports upgrade from version 8.0 or later."
- Stepping stones: "If you are running JasperReports Server 6.0 through 6.4.x: 1. Upgrade to the latest version of 7.1.x. 2. Upgrade from 7.1.x to version 8.2. 3. Upgrade from 8.2 to version 9.0. 4. Upgrade from 9.0 to version 10.0.0." Pre-3.7 sources: "first upgrade to 3.7.0, then to 6.3.x, then 7.x to 8.x and then to 9.0."

### Target 10.1.0 [10.1]
- Direct samedb: 10.0 -> 10.1.0. Direct newdb: 9.0 -> 10.1.0.
- Overlay zip: "Supports upgrade to 10.1.0 from version 10.0.0 or later." WAR zip: "Supports upgrade from version 9.0 or later."
- The upgrade-paths matrix now only lists sources 9.0.0 (newdb) and 10.0.0 (samedb). "Note: For details on upgrading from version 8.x or older, see the respective Upgrade Guides for those versions." The "6.4.x or Earlier" chapter is gone from this guide.
- 9.0 -> 10.1 note: "While upgrading from version 9.0 to JasperReports Server 10.1.0, the appropriate version of Tomcat must be installed."

### Summary table

| Target | samedb direct | newdb direct | Overlay sources | WAR-zip floor | Older sources |
|---|---|---|---|---|---|
| 5.6 | 5.5 | 3.7 - 5.2 | 4.0 - 5.5 | 3.7 | 3.5 -> 3.7 -> 5.6; earlier -> 3.7 first |
| 8.0 | 7.9 | 7.1 - 7.5 | 7.1+ | 7.1 | 3.7-4.2 -> 6.3 -> 7.1 -> 8.0; 4.5-5.x -> 6.4 -> 7.1 -> 8.0; 6.x -> 7.1 -> 8.0 |
| 8.1 | 8.0 | 7.1 - 7.9 | 7.1+ | 7.1 | same recipes ending 8.1 |
| 8.2 (comm + CE) | 8.0/8.1 | 7.1 - 7.9 | 7.1+ (comm only) | 7.1 | same recipes ending 8.2 |
| 9.0 | 8.2.x | 8.0.x - 8.1.x | 8.0+ | 8.0 | 6.x -> 7.1 -> 8.2 -> 9.0; pre-3.7 -> 3.7 -> 6.3 -> 8.x -> 9.0 |
| 10.0.0 | 9.0 | 8.0.x - 8.2 | 9.0+ | 8.0 | 6.x -> 7.1 -> 8.2 -> 9.0 -> 10.0.0 |
| 10.1.0 | 10.0 | 9.0 | 10.0.0+ | 9.0 | "see the respective Upgrade Guides" for 8.x or older |

---

## 2. Upgrade-method evolution

### Buildomatic js-upgrade scripts (samedb vs newdb)
- Present in every guide from 5.6 through 10.1. The docs state the scripts replaced older manual steps "in release 4.0": "This section describes the older, manual upgrade steps used before we implemented the js-upgrade shell scripts in release 4.0. They're provided here mainly as a reference for internal use." [8.0][8.1][8.2][8.2ce][9.0][10.0]; the same "Old Manual Upgrade Steps" appendix exists in [5.6].
- samedb: in-place upgrade of the existing repository DB; no export file argument. E.g. `cd <js-install-8.0>/buildomatic; js-upgrade-samedb.bat` [8.0]; identical pattern in [5.6][8.1][8.2][9.0][10.0][10.1].
- newdb: fresh DB + import of an export zip taken from the old server. E.g. `js-upgrade-newdb.bat <path>\js-7.9-export.zip` [8.2]; `js-upgrade-newdb.bat <path>\js-9.0export.zip` [10.1].
- Both support a dry run: "Use the test option to run the js-upgrade script in test mode", e.g. `js-upgrade-samedb.bat test` (all guides).
- samedb vs newdb selection is exactly the upgrade-paths matrix: samedb for the adjacent-release chapter, newdb for the older-source chapter (see section 1).
- 5.6-era note on the difference: "the js-upgrade-samedb script will automatically preserve any custom global properties you have set, whereas the js-upgrade-newdb script will not preserve your custom global properties." [5.6, A.2.1]
- newdb limitation (8.1 onward, retro-dated to 7.9.0 by later guides): "Starting version 7.9.0, the js-upgrade-newdb.sh/bat script does not import the access, audit, monitoring data when upgrading. However, once the upgrade process has completed, you can use the JRS UI - Import page to reimport the ... export file ... and select the checkboxes for including access, audit, and monitoring data." [10.0][10.1]; 8.1/8.2/9.0 carry the same note phrased as "Currently, the js-upgrade-newdb.sh/bat script does not import..." [8.1][8.2][9.0].
- CE 8.2 uses suffixed script names: js-upgrade-samedb-ce.bat/.sh and js-upgrade-newdb-ce.bat/.sh [8.2ce]. The commercial editions use the unsuffixed names.

### Overlay upgrade
- Introduced in the 5.6 guide as new: "JasperReports server now has an overlay upgrade procedure. For now, this is only available with JasperReports Server Commercial edition and only with the Apache Tomcat application server." [5.6]
- Constant restrictions in every commercial guide 8.0-10.1: Tomcat only; WAR-file installs only ("The binary installer is not supported"); "The overlay upgrade is not possible if you configured custom encryption keys in your previous server"; certified repository databases only. [8.0][8.1][8.2][9.0][10.0][10.1]
- Supported overlay source windows: 4.0-5.5 for 5.6; "7.1 and later" for 8.0/8.1/8.2; "8.0 and later" for 9.0; "8.0 and later" for 10.0.0 (distribution table says "from version 9.0 or later" while the overlay chapter says "versions 8.0 and later" - the doc is internally inconsistent); "9.0 and later" for 10.1.0 (distribution table says "from version 10.0.0 or later", overlay chapter says "versions 9.0 and later" - again inconsistent between table and chapter).
- Overlays were never dropped: all commercial guides through 10.1 keep the Overlay Upgrade chapter. CE guides do not have it at all ([8.2ce] lists only the WAR File Distribution Zip).
- Overlay mechanics (8.x-10.x): run `overlay install`; prompts for working folder (default ../overlayWorkspace), database-backup confirmation, Tomcat shutdown, keystore (see section 3), path to default_master.properties, path to the app server; "Your jasperserver-pro war file will be automatically backed up. Potential customizations in your environment will be analyzed."; rollback procedure included. [8.0][8.2][9.0][10.0][10.1]
- 10.x overlay additions: "The overlay upgrade uses paths that exceed the 260-character limit on Windows. To extract the package, Enable NTFS long paths (Windows 10 only) or use a third-party file archive such as 7-Zip." [10.0][10.1]. 10.0 overlay steps add: "Copy ../webapps/jasperserver-pro directory from Tomcat 9.0 to Tomcat 10.1.x." (Jakarta/Tomcat 10.1 move) [10.0].

### WAR file vs installer
- Upgrades are documented via the WAR File Distribution zip + buildomatic in every guide; the overlay explicitly does not support binary-installer installs [8.0-10.1].
- "Best Practices for Upgrading under Windows" (5.6, and "on Windows" in 8.x-10.0): binary installer bundles Tomcat/PostgreSQL/Java "hard coded ... to a specific version"; for a long-lived, upgradeable instance "it is recommended that you install to preexisting components" using the WAR zip (js-install.bat + default_master.properties) or the installer pointed at existing components. [5.6][9.0][10.0]

### Compact vs Split (8.0+)
- "As of version 8.0, JasperReports Server supports the following installations: Compact installation: The Repository, Audit, Access, and Monitoring tables are created in a single repository database ... Split installation: Only the Repository tables are created in the repository database. The Audit, Access, and Monitoring tables are created in a separate audit database ... The default installation is the Compact installation." [8.2, 1.2; introduced per 8.0 appendix]
- Split upgrade configuration: uncomment `installType=split` plus `audit.dbHost/dbUsername/dbPassword/dbPort/dbName` (per-database samples; DB2 audit.dbName must be uppercase; Oracle adds sysUsername/sysPassword/sid or serviceName) in default_master.properties. "If the installType=split property is not configured, the upgrade will be compact." [8.2, 1.2.1; same section in 8.0/8.1/9.0/10.x]
- After a Split upgrade: "run the following command: Windows: transfer-audit-data.bat, Linux and Mac OSX: ./transfer-audit-data.sh. The data is transferred to the audit database and the tables are deleted from the jasperserver database. Rerun the command if there is any interruption ... it will resume ... from where it was interrupted." [8.0][8.1][8.2][9.0][10.1]
- Compact-to-Split migration chapters (8.0-10.x): "Migrating From Compact to Split (samedb)" and "(newdb)" using js-migrate-to-split-newdb.bat/.sh with optional `include-access-events include-audit-events include-monitoring-events` arguments. [8.0 Ch.5][8.1 Ch.5][8.2 Ch.5][9.0][10.0]
- Cross-type upgrades are forbidden: "Users will not be able to upgrade: From 8.1 Compact to 8.2 Split. From 8.1 Split to 8.2 Compact. If users need 8.2 Split installations but they are on 8.1 Compact, the required upgrade path is to: 1. Upgrade 8.1 Compact to 8.2 Compact. 2. Then, migrate from 8.2 Compact to 8.2 Split." [9.0 appendix]; identical rules stated for 8.0->8.1 [9.0], 9.0->10.0.0 [10.0], 10.0->10.1.0 [10.1].

### Community Edition specifics
- CE upgrade guide [8.2ce]: WAR-only distribution (TIB_js-jrs-cp_8.2.0_bin.zip), no Overlay chapter, -ce script suffixes, same paths matrix, same keystore backup steps, same Old Manual Upgrade Steps appendix. The Split/Compact migration chapter is absent from the CE guide's TOC (chapters: 8.x->8.2, 7.1-7.9->8.2, 6.4.x or earlier).
- CP -> commercial ("Upgrading from the Community Project" chapter in commercial guides 5.6-10.0): "This CP to commercial upgrade procedure is only valid for upgrade within a major JasperReports Server release, for example 5.6 CP to 5.6 commercial" [5.6] (same wording with 9.0/10.0.0 examples in [9.0][10.0]). Procedure: back up CP WAR + DB (+ keystore from 8.0 on), export CP repository, deploy commercial WAR, import CP data; import "Adds superuser, Themes, and default tenant structure" [8.0]. Post-upgrade, re-configure XML/A connections for multi-tenancy: change "jasperadmin" to "jasperadmin|organization_1" and URI "http://localhost:8080/jasperserver/xmla" to ".../jasperserver-pro/xmla" [8.0, 7.8].

---

## 3. Keystore / .jrsks handling per era

### Introduction
- The 5.6 guide contains zero occurrences of "keystore"/".jrsks" - no keystore existed in that era. [5.6]
- Introduced in 7.5, per the appendix carried in 8.x-10.x guides: "JasperReports Server 7.5 streamlines how it manages the encryption keys ... There is no more any need to configure the encryption keys because all keys are generated automatically during the installation and stored in a central keystore ... as long as the same user performs the upgrade, the upgrade scripts have access to the same keys in the keystore. The new keys are backward compatible with the default keys from previous servers." [8.0 A.3.3; same text in 8.1/8.2/8.2ce/9.0/10.0]

### Documented carry-across steps (identical in 8.0, 8.1, 8.2, 8.2ce, 9.0, 10.0, 10.1)
Backup (part of "Back Up Your JasperReports Server Instance", plus a dedicated "Backing Up Your Keystore" section in the CP chapter):
1. "Create a folder (if you did not do so already) where you can save your server's keystore, for example C:\JS_BACKUP or /opt/JS_BACKUP."
2. "As the user who originally installed the server, copy $HOME/.jrsks and $HOME/.jrsksp to <path>/JS_BACKUP. Remember that these files contain sensitive keys for your data, so they must always be transmitted and stored securely."

Restore (rollback procedure): "Copy the .jrsks and .jrsksp files from the C:\JS_BACKUP folder back to the $HOME folder, where they were originally backed up from."

Run-as rule (appendix preamble, 8.0+): "Run the upgrade script as the same user who originally installed the server, or make sure the server's keystore is available in the home directory of the user running the upgrade script."

8.2+ adds an alternative to moving the files: "Alternatively, update the current location of the keystore in the keystore.init.properties file at the following locations: .../WEB-INF/classes/keystore.init.properties, .../buildomatic/keystore.init.properties, .../buildomatic/conf_source/iePro/keystore.init.properties" [8.2 overlay; 9.0; 10.0; 10.1].

Post-upgrade reminder (all 8.0+): "Installing JasperReports Server automatically generates encryption keys that reside on the file system. These keys are stored in a dedicated ... Jaspersoft keystore. Make sure this keystore is properly secured and backed up, as described in the ... Security Guide."

### Failure modes when skipped (documented)
- During upgrade/overlay: "If you are prompted to create a new keystore, this means that the server's original keystore was not found in the user's home directory. Proceed with caution: In general, it is recommended to exit the upgrade procedure and make sure the keystore is in the proper location, then rerun the upgrade. If you continue and create a new keystore, then the upgrade will proceed but your repository will be corrupted and users unable to login. In this case, you will need to manually export the server's repository with a custom key, then import the key before importing the repository, as described in [the Encryption Keys appendix]." [8.0][8.1][8.2][8.2ce][9.0][10.0][10.1]
- After restore-without-keystore: "If the backed up .jrsks and .jrsksp files are not copied from the C:\JS_BACKUP folder back to the $HOME folder, JasperReports Server login page does not open and gives an error." [8.0][8.1][8.2][9.0][10.0][10.1]
- Overlay hard stop: "The overlay upgrade is not possible if you configured custom encryption keys in your previous server." [8.0-10.1]

### Lost-keystore recovery plan (Encryption Keys appendix, 8.0+ / 8.2ce)
"if you do not have access to the user who installed the 7.5 instance, you may not be able to access the keystore anymore" - documented workaround: export with a generated custom key:
`js-export.sh --everything --output-zip js-7.5-export.zip --genkey` which prints "Secret Key: 0xb1 0x44 ..." and "Key Alias (UUID): ..."; then on the new server import the key into the keystore first, import the catalog ("As the data is imported, it is decrypted with the given key, and re-encrypted with the server's new keys"), and "back up your data and new keystore once again". [8.2ce A.x.3; same appendix in 8.0/8.1/8.2/9.0/10.0]

---

## 4. Repository export/import rules across versions

- Export tooling for the newdb path, three documented ways in 5.6: "Use the JasperReports Server UI (since 5.0 release); Use the buildomatic scripts (if you originally installed using buildomatic); Use the js-export.bat/.sh script found in the <js-install>/buildomatic folder." Buildomatic form: `js-ant export-everything -DexportFile=js-5.2-export.zip` [5.6]. Later guides standardize on the js-export script: `js-export.bat --everything --output-zip js-8.0-export.zip` [9.0]; same pattern in 8.x/10.x.
- Export is always run with the OLD version's buildomatic (`cd <js-install-8.0.x>/buildomatic` when upgrading to 9.0) [9.0][10.0][10.1][8.2].
- 5.6 UI-export landmine: "Export from the UI in Release 5.1 has a bug. So, it is best to export from the command line if upgrading from 5.1. If you do export from the UI with 5.1, you can unpack the resulting export.zip file, edit the index.xml file and change the string '5.0.0 CE' to '5.1.0 PRO'." [5.6, 4.4.1]
- Import during newdb upgrade is performed by js-upgrade-newdb itself; the docs describe its semantics: "'import-upgrade' will import resources from the 7.9 instance in a 'non-update' mode (so that core resources from 8.2 will stay unchanged). Additionally, the 'update-core-users' option will be applied so that the superuser and jasperadmin users will have the same password as set in the 7.9 instance." [8.2; same wording with respective versions in 8.0/8.1/8.2ce/10.0/10.1]
- Encrypted-catalog imports: "--include-server-settings --secret-key specifies the key to use for the import. Use the same key you imported into the keystore." [8.0][8.1][8.2][10.0][10.1]
- Split imports: "If the upgrade is Split, the Access, Audit, and Monitoring events are imported to the audit database during the import process." [9.0][10.0]
- Backward compatibility statement (only explicit one in these guides): "Note: Resources exported from version 10.1.0 cannot be imported into older versions of the application." (in the context of the Castor-to-Jackson serializer change) [10.1]
- Forward compatibility is otherwise expressed structurally: each guide's newdb chapter states which old versions' export zips the new server imports (3.7-5.2 for 5.6; 7.1-7.5 for 8.0; 7.1-7.9 for 8.1/8.2; 8.0-8.1 for 9.0; 8.0-8.2 for 10.0; 9.0 for 10.1). The 9.0/10.x key encryption note: imported data "is decrypted with the given key, and re-encrypted with the server's new keys" [8.0-10.0 Encryption Keys appendix].

---

## 5. Version-specific mandatory steps and landmines (as called out by the guides)

Cumulative-review rule stated in every guide: "Changes are cumulative, so review all topics that affect you." [5.6][8.0][9.0][10.0]

### Called out in [5.6] (Appendix A)
- 5.6: "Removal of commercial JDBC drivers" - Oracle, SQL Server, DB2 drivers removed from the package; "You will need to obtain a JDBC driver before running the upgrade steps" (copy from `<js-install-existing>/buildomatic/conf_source/db/oracle/jdbc/` into the 5.6 tree). Also "Check for JDBC Driver (Oracle, SQL Server, DB2)" is a numbered overlay step.
- 5.6 OLAP engine change: XML/A connections to a remote JRS must change DataSource, "Provider=Mondrian;DataSource=Foodmart" must become "Provider=Mondrian;DataSource=JRS". "if your instance hosts multiple organizations, XML/A connections will fail for superuser" - test as jasperadmin instead.
- 5.0: samedb preserves custom global properties, newdb does not (see section 2). XML/A connections passing tenantID in the Data Source field are "no longer supported" - remove the tenantID argument (except when connecting as superuser).
- 4.7: Ad Hoc workflow split into views vs reports; theme customizations affected; data snapshots may increase repository size.

### Called out in [8.0] (Appendix A; carried forward into 8.1/8.2/9.0/10.0 appendices)
- 8.0: Split installation introduced (see section 2).
- 7.8: "the JavaScript engine is switched to Chrome/Chromium from PhantomJS/Rhino ... PhantomJS/Rhino support has been removed. You need to install and configure Chrome/Chromium to export the reports and dashboards to PDF and other output formats." Without it, "reports and dashboards cannot be exported to PDF, DOCX, and other output formats."
- 7.5: Simba JDBC drivers for Spark and Impala replaced ("due to vulnerabilities"); old drivers require manually adding listed jars to WEB-INF/lib. MongoDB query language changed: "All aggregate commands must be updated to the new API-driven query syntax. All other command-driven queries (queries that use runCommand) are deprecated." Encryption keys centralized into the keystore (section 3). Theme changes (large classname-modification tables for Banner, Ad Hoc Designer, Report Viewer, Dashboard Designer elements).
- 7.2: "Removal of Legacy Dashboards" - "legacy dashboards, created in ... 5.6.2 and earlier ... If you continue with the upgrade, your legacy dashboards will be permanently deleted. You cannot roll back this operation." Recreate them as new dashboards before upgrading. Login-page layout changed. "Spring Security Upgrade": framework updated to Spring Security 4.2; external-auth applicationContext-externalAuth-*.xml files must be re-implemented on the new sample files ("the name and package of the class in many bean definitions have changed. Make sure not to overwrite the new names with the old ones."); custom Spring Security code must be migrated ("The Spring Security codebase was significantly restructured from 3.x to 4.x. Many classnames have changed...").
- 7.1: Login-page layout changed; absolute repo: paths in reports ("repo:/organizations/organization_1/...") now error - "Consider using relative path, or the public folder".
- 6.4 / 6.2.1: community Impala connector removed; keeping it requires adding a long list of jars to WEB-INF/lib and deleting applicationContext-HiveDatasource.xml.
- 6.2: default Ad Hoc templates changed. 6.1: themes changed.
- Customizations generally: "If you made modifications to the original JasperReports Server application, you'll need to manually copy configuration changes, like client-specific security classes or LDAP server configurations, from your previous environment ... typically found in the files at the WEB-INF/ location, for example, applicationContext-*.xml, *.properties, *.js, *.jar, and so on." [8.0, 7.9.1; repeated in every guide's "Handling JasperReports Server Customizations"]
- Post-upgrade hygiene tasks in every guide: clear app-server work and temp folders; "Clearing the Repository Cache Database Table" - `update JIRepositoryCache set item_reference = null; delete from JIRepositoryCache;` (compiled JR resources cached there go stale across releases and "cause errors at runtime") [5.6-10.1]; clear browser cache before login.

### Called out in [8.1]/[8.2]
- 8.1: "Users will not be able to upgrade from 8.0 Compact to 8.1 Split, or from 8.0 Split to 8.1 Compact. Currently, the js-upgrade-newdb.sh/bat script does not import the access, audit, monitoring data." [8.1 appendix, quoted in 9.0]
- 8.2 (documented in [9.0] appendix): "As of release 8.0.4, Simba drivers are removed" (athena-jdbc42, cassandra-jdbc42, impala-jdbc42, neo4j-jdbc42, spark-jdbc42) - "you must manually install publicly available drivers ... After installing new drivers, update the resources."
- 8.2 samedb/newdb allowed only Compact->Compact and Split->Split (see section 2).

### Called out in [9.0]
- "Progress Driver Removal": "As of release 9.0, Progress drivers are removed" (TIautorest, TIcassandra, TIdb2, TIgooglebigquery, TIhive, TIimpala, TImongodb, TIoracle, TIredshift, TIsforce, TIsparksql, TIsqlserver jars) - install vendor drivers and update resources. Extensive follow-on data-type landmines for SQL Server/Oracle/DB2 (e.g. SQL Server Time read as Time not Timestamp, Float as Double, causing "missing fields or columns" in migrated domains/ad hoc views; fix by updating resources or uncommenting the JdbcDriverMetaConfigurationImpl bean in WEB-INF/applicationContext-jdbc-metadata.xml to restore old mappings; possible "The data types time and datetime are incompatible in the equal to operator" errors in JRXML reports).
- UI customizations: "you have to first perform the JasperReports Server upgrade, then get the JasperReports Server Source Packages, apply the customizations in the UI source files, rebuild them and publish."
- AdHoc Component: new 9.0 report templates in /public/templates share names with old ones; "During the import of older resources, there is a risk of overwriting these templates by accident" - re-import via `jsant import-minimal-pro`.
- JasperReports Web Studio needs two additional deployed applications (memory planning).
- Date grouping renames (Quarter -> Quarter and Year; Month -> Month and Year).
- JNDI data sources: "it is required to create the new JNDI resources even if the feature is currently disabled" - jdbc/jasperserver -> jdbc/jasperserverSystemAnalytics, jdbc/jasperserverAudit -> jdbc/jasperserverAuditAnalytics.
- OAuth/OpenID: "If your deployment relied on OAuth configurations customized within applicationContext-externalAuth-*.xml, it is required to migrate these configurations to the new format" (External Authentication Cookbook).
- Alerting: quartz threadCount default raised 2 -> 4.
- Schedules page column renames; deleting AnonymousUser disabled; viz.js container element restrictions; dashboard scheduler needs deploy.base.local.url in js.config.properties.

### Called out in [10.0]
- "Jakarta Upgrade": "Jakarta runs on Apache Tomcat 10.1.x, embracing the latest advancements in the Jakarta EE 10 specifications. This transition also involves updating the codebase to align with the new Jakarta namespace." Resources may "stop functioning or display altered behaviors" due to the Tomcat change; the overlay procedure includes copying the webapp from Tomcat 9.0 to Tomcat 10.1.x.
- "Hibernate Upgrade": Hibernate 6; migration "from the legacy XML-based object-relational mappings (.hbm.xml) to the modern, annotation-driven JPA approach using @Entity classes."
- "New License": "a new in-house license validator. The license file itself is now named jaspersoft.jrs.license ... Correct permissions must be set on this new file."
- csrfguard 3.1.0 -> 4.3.0: "causes server requests to be rejected ... org.owasp.csrfguard.TokenPerPage property is set to true by default and cannot be set to false" (per-page CSRF tokens are now standard behavior).
- New Layout Band redesign; Custom Input Controls (expressions for enable/disable, show/hide, dynamic titles).
- New JNDI Security chapter: `jndi.restrictedAccess=true` plus analytics.*/auditAnalytics.* read-only users in default_master.properties; WebSphere/WebLogic-specific procedures. [10.0][10.1]
- Compact/Split cross-type upgrade still forbidden (9.0 -> 10.0.0).

### Called out in [10.1]
- "Password History Validation": server "can now validate a new password against the last N passwords."
- "Password Storage Strategy": "replaces older, reversible encryption methods with highly secure, one-way hashing algorithms: PBKDF2, SCrypt, and Argon2 ... eliminates the need to synchronize keystores across clustered deployments. If you used the samedb upgrade process and chose the modern password strategy, your existing users' passwords must be updated using the migration utility" (Password Migration section of the Installation Guide).
- "Castor Serializer to Jackson": serialization framework replaced; "Resources exported from version 10.1.0 cannot be imported into older versions of the application."
- "Oracle 23ai Certification": new quartz-23onwards.ddl; "a new property, dbVersion, is added in the oracle_master.properties file. You must set this property in the default_master.properties file before running the installation or upgrade."
- 9.0 -> 10.1 requires installing "the appropriate version of Tomcat."
- Compact/Split cross-type upgrade still forbidden (10.0 -> 10.1.0).

---

## 6. What changed between consecutive guides (procedure deltas)

- 5.6 -> 8.0: Same skeleton (overlay chapter, samedb chapter, newdb chapter, pre-cutoff chapter, CP chapter, Old Manual Steps, Planning appendix). 8.0 adds: keystore backup/restore/run-as-same-user steps everywhere (keystore arrived in 7.5); an explicit "Upgrade Paths" samedb/newdb matrix (5.6 had only chapter ranges); Compact vs Split installation types, split default_master.properties settings, transfer-audit-data scripts, and a Compact->Split migration chapter; "Plan Your Upgrade" becomes a numbered overlay step; overlay floor moves from 4.0 to 7.1; unsupported floor moves from 3.7 to "versions prior to 6 ... must be upgraded to version 6.3 first".
- 8.0 -> 8.1: Essentially identical document; only the version windows shift (samedb source 7.9 -> 8.0; newdb window widens to 7.1-7.9). New landmine text: Compact<->Split cross-type upgrades forbidden and newdb no longer carries access/audit/monitoring data.
- 8.1 -> 8.2: Same procedures; branding changes from TIBCO to Cloud Software Group; samedb chapter renamed "Upgrading from 8.x to 8.2" (accepts 8.0.x and 8.1.x); appendix adds the 8.0.4 Simba-driver removal. A separate CE 8.2 upgrade guide exists (WAR-only, -ce scripts, no overlay).
- 8.2 -> 9.0: Support floor jumps to 8.0 (WAR and overlay); 7.x and older forced through newdb/stepping stones. Keystore relocation via keystore.init.properties documented as an alternative to $HOME placement. Large new migration surface: Progress driver removal with data-type remediation, JNDI resource renames, OAuth config migration, AdHoc template overwrite risk, Web Studio co-deployments.
- 9.0 -> 10.0.0: Adds the JNDI Security chapters (restricted access, read-only users, WebSphere/WebLogic variants). Overlay gains Windows long-path instructions and the Tomcat 9 -> Tomcat 10.1 webapp copy step (Jakarta). Appendix adds Jakarta/Tomcat 10.1, Hibernate 6, new license file, csrfguard 4.3.0.
- 10.0.0 -> 10.1.0: Direct-path matrix collapses to only 9.0 (newdb) and 10.0 (samedb); the "6.4.x or Earlier" chapter is dropped ("see the respective Upgrade Guides for those versions"). Overlay floor formally 10.0.0 (chapter text says 9.0 and later). New appendix items: password history validation, one-way password hashing with a required migration utility for samedb upgrades, Castor -> Jackson (with the no-import-into-older-versions warning), Oracle 23ai dbVersion property.

---

## Gaps and caveats

- Internal inconsistencies in the docs themselves: [10.0] distribution table says overlay supports "from version 9.0 or later" while its overlay chapter says "versions 8.0 and later"; [10.1] table says "from version 10.0.0 or later" while its overlay chapter says "versions 9.0 and later". Both statements are reported above as written.
- The upgrade-path matrices are figures/tables that extracted poorly to text (row/column alignment lost). The samedb-diagonal / newdb-elsewhere pattern and the prose around them are reliable; individual cell-by-cell readings for mid-matrix combinations (e.g. 7.2.x -> 7.8.x) could not be reconstructed with confidence and are not asserted.
- "ehcache" and "web.xml" do not appear anywhere in these eight upgrade guides; the guides' customization guidance is limited to the generic WEB-INF file list (applicationContext-*.xml, *.properties, *.js, *.jar). Any ehcache/web.xml overlay-merge procedures live outside these documents.
- Mondrian/OLAP content in these guides is limited to the XML/A items quoted (5.6 DataSource=JRS change, tenantID removal, CP-to-commercial XML/A reconfiguration). No Mondrian schema migration steps appear in the upgrade guides.
- The 8.1.0 guide exists twice in the corpus ([8.1], [8.1b]); both are "Version 0722-JSP81-15", differing only in copyright year (2022 vs 2023) and PDF text extraction layout. They were treated as one source.
- The 5.6 guide's Appendix A covers only changes back to 4.7; the 8.x-10.0 appendices cover only back to 6.1 ("For versions of the software earlier than 6.1, see earlier versions of the ... Upgrade Guide"); the 10.1 appendix covers only 9.0/10.0/10.1. Changes for 5.x-6.0 era targets other than those quoted are not documented in this corpus.
- Theme-change specifics for 7.5 are large CSS classname tables in [9.0]/[10.0]; they extracted as fragmented table text and are summarized, not reproduced.
- The Encryption Keys appendix sections referenced by the failure-mode text (A.3.3/A.4.3/A.5.3 depending on guide) are summarized from the recoverable fragments; the full key-import command sequence ("import the key before importing the repository") is delegated by the docs themselves to the Security Guide, which is not part of this file set.
