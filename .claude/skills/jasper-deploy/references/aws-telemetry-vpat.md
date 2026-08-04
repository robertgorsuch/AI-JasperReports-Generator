# AWS deployment, telemetry program, VPAT (accessibility)

[doc-only] Distilled from the 9.0.x AWS user guides + AWS relnotes, the
telemetry data-collection program doc (June 2025), and VPAT_JRS-9.0.0
(Jan 2024) in docs/. Page cites are printed pages of the named PDF. Nothing
here is live-verified; the local install is on-prem 10.0.0.

## JRS on AWS (9.0.x AWS user guides)

How it ships: AWS Marketplace offerings - Hourly, Annual, BYOL (bring your
own license), and Multi-Tenancy variants - delivered as AMIs plus
CloudFormation templates (9.0.1 AWS guide p6). Three launch paths:
- Single instance in a VPC via the marketplace CFT (stack Outputs tab gives
  the Getting Started URL, instance name, login, S3 license bucket) (p9-11).
- Cluster in a VPC via CFT: Auto Scaling group (max 10 instances, CPU-based
  scale in/out), Application ELB as static endpoint + health-replacement, and
  the repository moved to an EXTERNAL PostgreSQL RDS in the same VPC (only
  PostgreSQL supported) - you create the RDS yourself and run the bundled
  initialization script from a temporary instance to create/recreate the
  repository DB before scaling from 0 to 1 (p12-16).
- Raw AMI from the EC2 console (pick the AMI matching your license type)
  (p16-17).

First login: superuser with the EC2 INSTANCE ID as initial password (find it
in the CloudFormation Outputs tab or EC2 console); change it immediately
(p19-21).

License handling: non-BYOL is billed hourly/annually through the marketplace.
BYOL runs on a trial license until you upload `jasperserver.license` to the
S3 bucket the stack created, or SFTP it to
`/usr/share/tomcat/webapps/jasperserver-pro/WEB-INF` and
`sudo systemctl restart tomcat`; verify via About JasperReports Server
(p25-27). In a BYOL cluster, delete pre-license instances after applying the
license or autoscaling can clone the old trial license (p12).

Key differences vs on-prem:
- Cloud Settings page (superuser-only, Manage > Server Settings > Cloud
  Settings): auto-manages AWS security-group access rules so the server can
  grant itself access to RDS/Redshift when its IP changes (stop/start gets a
  new IP); also Access Rule Name/Description, manual public IP override, and
  Suppress EC2 Credentials Warning for IAM-role-less instances (p27-29).
  Datasource auto-detection for RDS/Redshift/EMR; run with an IAM role rather
  than access keys where possible (p37).
- Config customization is done by mirroring `conf/` and `webapp/` paths in
  the stack's S3 bucket; files there overwrite every instance (including
  autoscaled ones) on reboot. To undo, upload the ORIGINAL file - deleting
  from S3 does not revert instances (p22-23).
- Chrome is an install-time CFT option; needed for export/screenshot
  functionality (p12, p23-24).
- Logs: SSH as ec2-user, `tail -f /var/log/jasperserver/jasperserver.log`
  (p29-30). Upgrades are NOT in-place - follow the community wiki procedure
  (export/import to a new stack) (p29).

Sizing/platform (AWS relnotes 9.0.0, p3-4): base AMI moved to Amazon Linux 2;
default instance type m5.xlarge; supported m5.xlarge/m5.2xlarge,
r5a.xlarge/r5a.2xlarge; m5.large dropped; GovCloud and the QuickStart cluster
CFT dropped (the 9.0.0 guide's GovCloud section p22-26 is legacy).

## Telemetry / data collection program (9.0.0 doc, June 2025)

What it collects (telemetry doc p3):
- Product usage: logged-in user counts, reports run, scheduled jobs, product
  config settings (e.g. Ad Hoc view creations), connected database type.
- License usage: License ID, installation UUID, core counts, OS info - used
  for license compliance.

How it reports and how to disable (p4):
- Delivered as a HOTFIX to 9.0.0; uploads are automatic from
  internet-connected instances.
- Instances on private/offline networks send nothing - that is the documented
  de-facto opt-out for locked-down installs.
- Full opt-out: do not apply the telemetry hotfix.
- Isolated-network customers instead manually collect and upload license
  telemetry at renewal (p3).
- Retention: for the active customer relationship, plus a limited
  legal/analytics tail; then deletion/anonymization (p6).

Do not confuse with the older Heartbeat program (opt-in prompt at first admin
login; env/version info only; disabled via `heartbeat.enabled=false` in
js.config.properties - see server-administration.md). They are separate
mechanisms with separate switches.

## VPAT / accessibility (JRS 9.0.0, Jan 2024)

The VPAT (v2.4Rev WCAG edition) claims WCAG 2.0 and 2.1 conformance at
Levels A and AA for JasperReports Server 9.0.0, evaluated manually with
JAWS/NVDA/VoiceOver/TalkBack across Chrome/Firefox/Safari. Scope is narrow:
only the Login, Home, Library, Repository, and Search Results flows - NOT the
Ad Hoc editor, dashboard designer, or admin pages, and the report notes that
accessibility of content-creation and administration features "is more
limited". Most A/AA criteria are "Supports"; the documented gaps (Partially
Supports) are: 1.3.1 info-and-relationships (some untagged dialogs/non-text
elements), 2.1.1 keyboard (Favorites icon unreachable), 3.3.2 labels (filter
expanders unlabeled), 4.1.2 name/role/value (list items missing interactive
roles), 1.4.10 reflow (footer overlap at 400% zoom), and 4.1.3 status
messages (no announcement after Cut/Copy/Paste). Section 508 is addressed via
the WCAG mapping; AAA criteria are marked Not Applicable/Not Evaluated.
Answer accessibility questionnaires from those gap bullets; anything outside
the five scoped pages is unassessed, not conformant.
