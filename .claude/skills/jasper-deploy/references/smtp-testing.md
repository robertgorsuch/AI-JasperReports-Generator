# Verifying email delivery end-to-end (schedule_job + manage_alert)

`schedule_job.ps1 -MailTo ...` (a scheduled report emailed as an attachment) and
`manage_alert.ps1 -MailTo ...` (a data-threshold alert notification) both build a
`mailNotification` and the REST call returns `2xx` once the descriptor shape is
valid. **That `2xx` only validates the descriptor -- it does NOT prove a mail was
sent.** The actual send happens later in the JRS evaluate -> notify pipeline (at
the trigger fire time for a job, at the threshold-cross for an alert) and needs a
reachable SMTP host configured server-side. To verify real delivery, point JRS at
a LOCAL SMTP catcher and confirm the captured message.

## 1. Run a local SMTP catcher

A catcher accepts SMTP on a local port and shows captured mail in a web UI; it
never relays, so nothing leaves the machine.

**smtp4dev** (Windows-friendly, .NET):
```powershell
# as a dotnet tool
dotnet tool install -g Rnwood.Smtp4dev
smtp4dev --smtpport 2525 --urls http://localhost:5000
# or via Docker
docker run -d -p 2525:25 -p 5000:80 rnwood/smtp4dev
```
SMTP listens on `localhost:2525` (or `:25` in the Docker example); the inbox web
UI is at http://localhost:5000.

**MailHog** (single static binary):
```powershell
# MailHog defaults: SMTP 1025, web UI 8025
.\MailHog.exe
# or
docker run -d -p 1025:25 -p 8025:8025 mailhog/mailhog
```
SMTP on `localhost:1025` (or `:25` in the Docker mapping); web UI at
http://localhost:8025.

Catchers accept any sender/recipient and do not require auth or TLS, so use a
plain host/port with auth disabled. If you bind the catcher to `:25` directly,
make sure nothing else (a real MTA, another catcher) already holds the port.

## 2. Point JasperReports Server at the catcher

JRS reads its mail host from the report scheduler / Quartz mail settings under the
deployed webapp:

```
C:\Jaspersoft\jasperreports-server-10.0.0\apache-tomcat\webapps\jasperserver-pro\WEB-INF\js.quartz.properties
```

Set the host/port to the catcher and disable auth/TLS (catchers want none):
```properties
report.scheduler.mail.sender.host=localhost
report.scheduler.mail.sender.port=2525
report.scheduler.mail.sender.username=
report.scheduler.mail.sender.password=
report.scheduler.mail.sender.protocol=smtp
report.scheduler.mail.sender.from=jasper@localhost
# leave any *.auth / STARTTLS / SSL properties false/empty for a catcher
```
(The exact key names can vary by build; the `report.scheduler.mail.sender.*`
block is what the scheduler/alert sender uses. Some installs also expose these
through `applicationContext-report-scheduling.xml` -- the property file is the
simplest knob.)

**These settings load at startup -- a change requires a server restart:**
```powershell
Restart-Service jasperreportsTomcat -Force   # needs admin/UAC; ~50s downtime
```
Until the restart, JRS keeps using the OLD mail host, so a job/alert that
"succeeded" at create time still will not land in the catcher.

## 3. Fire something and confirm the captured message

Create a job that fires almost immediately (so you do not wait for a future
trigger), or an alert whose threshold is guaranteed to cross:
```powershell
# emails a PDF on the next minute boundary
& $skill\schedule_job.ps1 -ReportUri /reports/foodmart/foodmart_top_categories `
    -StartType now -OutputFormats PDF -MailTo dev@localhost
# alert that fires on the first evaluation (threshold any value will beat)
& $skill\manage_alert.ps1 -ReportUri /reports/foodmart/foodmart_top_categories `
    -ElementUuid <element-uuid> -Operator ">" -Threshold -1 -MailTo dev@localhost
```
Then confirm:
- Open the catcher web UI (smtp4dev http://localhost:5000 / MailHog
  http://localhost:8025) and look for a new message addressed to your `-MailTo`,
  with the report subject and the rendered report as an attachment.
- smtp4dev / MailHog also expose a REST API for scripted assertions, e.g. MailHog
  `GET http://localhost:8025/api/v2/messages` returns the captured items as JSON
  (assert `total > 0` and check `Content` / attachments).
- If nothing arrives: re-check that the restart actually happened, that the
  catcher SMTP port matches `report.scheduler.mail.sender.port`, and tail the JRS
  log (`...\apache-tomcat\logs\jasperserver.log`) for a mail send line or an SMTP
  connection error. A `2xx` from the REST create with an empty catcher almost
  always means the descriptor was fine but the mail host was unreachable or stale.

## Takeaway
Creating jobs/alerts via REST validates only the descriptor SHAPE. Real email
delivery is a separate, server-side step that needs a reachable mail host -- a
local smtp4dev/MailHog catcher plus a one-time `js.quartz.properties` edit and a
Tomcat restart is the fastest way to verify the full path end-to-end without
sending real mail.
