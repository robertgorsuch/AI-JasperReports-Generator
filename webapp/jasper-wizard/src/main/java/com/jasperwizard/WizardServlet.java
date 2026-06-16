package com.jasperwizard;

import jakarta.servlet.ServletConfig;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PrintWriter;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Single dispatcher servlet for the Jaspersoft Artifact Wizard.
 *
 *  Reads / preview  -> proxied straight to JasperReports Server REST (auth added
 *                      server-side, so the browser needs no creds and dodges CORS).
 *  Create / deploy  -> shells out to the verified jasper-deploy scripts via
 *                      ScriptRunner (the decision: reuse the tested pipeline).
 *
 * Routes (all under the /api/* mapping):
 *   GET  /api/health
 *   GET  /api/datasources                      list JDBC datasources (raw JRS JSON)
 *   POST /api/datasources                      create a JDBC datasource
 *   GET  /api/reports?folder=/reports          list deployed reportUnits (raw JRS JSON)
 *   POST /api/reports                          scaffold + compile + deploy a report
 *   POST /api/dashboards                       compose a dashboard from deployed reports
 *   GET  /api/run?uri=...&format=pdf           run a report and stream the output
 */
public class WizardServlet extends HttpServlet {

    private String jrsUrl, jrsUser, jrsPass, repoRoot, pgPassword, pythonExe, scriptsDir;
    private int timeoutSec;
    private File workDir;

    @Override
    public void init(ServletConfig cfg) throws ServletException {
        super.init(cfg);
        jrsUrl     = ctx("jrsUrl", "http://localhost:8081/jasperserver-pro");
        jrsUser    = ctx("jrsUser", "superuser");
        jrsPass    = ctx("jrsPass", "superuser");
        repoRoot   = ctx("repoRoot", "C:\\Users\\rgorsuch\\tx-geocoder");
        pgPassword = ctx("pgPassword", "postgres");
        pythonExe  = ctx("pythonExe", "python");
        timeoutSec = Integer.parseInt(ctx("scriptTimeoutSec", "180"));
        // The jasper-deploy scripts are bundled INSIDE the webapp (WEB-INF/scripts)
        // so the Tomcat service account can read+execute them from its own webapps
        // dir -- no access to the user profile / repo is required. Fall back to the
        // repo copy only for an unpacked/dev run where getRealPath is unavailable.
        String bundled = getServletContext().getRealPath("/WEB-INF/scripts");
        if (bundled != null && new File(bundled).isDirectory()) {
            scriptsDir = bundled;
        } else {
            scriptsDir = repoRoot + File.separator + ".claude" + File.separator + "skills"
                       + File.separator + "jasper-deploy" + File.separator + "scripts";
        }
        // Generated jrxml/manifests and the child processes' working directory must
        // live somewhere the Tomcat service account (NT AUTHORITY\LocalService) can
        // write -- the repo and user profile are NOT writable by it. The servlet
        // container's temp dir always is.
        File ctxTmp = (File) getServletContext().getAttribute("jakarta.servlet.context.tempdir");
        workDir = (ctxTmp != null) ? new File(ctxTmp, "work") : new File(System.getProperty("java.io.tmpdir"), "jasper-wizard");
        workDir.mkdirs();
    }

    private String ctx(String name, String dflt) {
        String v = getServletContext().getInitParameter(name);
        return (v == null || v.isEmpty()) ? dflt : v;
    }

    // ----------------------------------------------------------------- GET ----

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        String path = req.getPathInfo() == null ? "/" : req.getPathInfo();
        try {
            switch (path) {
                case "/health":
                    json(resp, 200, "{\"ok\":true,\"server\":" + Json.str(jrsUrl) + "}");
                    return;
                case "/datasources":
                    proxyJson(resp, "/rest_v2/resources?type=jdbcDataSource&recursive=true");
                    return;
                case "/reports": {
                    String folder = param(req, "folder", "/reports");
                    proxyJson(resp, "/rest_v2/resources?folderUri=" + enc(folder)
                            + "&type=reportUnit&recursive=true");
                    return;
                }
                case "/run":
                    runReport(req, resp);
                    return;
                default:
                    json(resp, 404, err("unknown endpoint " + path));
            }
        } catch (Exception e) {
            json(resp, 500, err(e.getMessage()));
        }
    }

    // ---------------------------------------------------------------- POST ----

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        String path = req.getPathInfo() == null ? "/" : req.getPathInfo();
        try {
            switch (path) {
                case "/datasources": createDatasource(req, resp); return;
                case "/reports":     deployReport(req, resp);     return;
                case "/dashboards":  composeDashboard(req, resp); return;
                default:             json(resp, 404, err("unknown endpoint " + path));
            }
        } catch (Exception e) {
            json(resp, 500, err(e.getMessage()));
        }
    }

    // -------------------------------------------------------- create steps ----

    private void createDatasource(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        String uri      = req.getParameter("uri");
        String label    = param(req, "label", "");
        String database = req.getParameter("database");
        if (empty(uri) || empty(database)) { json(resp, 400, err("uri and database are required")); return; }

        List<String> a = new ArrayList<>();
        addArg(a, "-Uri", uri);
        addArg(a, "-Label", label.isEmpty() ? uri : label);
        addArg(a, "-Database", database);
        addArg(a, "-DbHost", param(req, "host", "localhost"));
        addArg(a, "-DbPort", param(req, "port", "5432"));
        addArg(a, "-DbUser", param(req, "dbUser", "postgres"));
        addArg(a, "-DbPassword", param(req, "dbPassword", "postgres"));

        ScriptRunner.Result r = runner(jrsEnv()).powershell(script("create_datasource.ps1"), a);
        StringBuilder sb = new StringBuilder("{");
        sb.append("\"ok\":").append(r.ok());
        sb.append(",\"uri\":").append(Json.str(uri));
        sb.append(",\"output\":").append(Json.str(r.output));
        sb.append("}");
        json(resp, r.ok() ? 200 : 500, sb.toString());
    }

    private void deployReport(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        String name  = req.getParameter("name");
        String query = req.getParameter("query");
        String ds    = req.getParameter("dataSourceUri");
        if (empty(name) || empty(query) || empty(ds)) {
            json(resp, 400, err("name, query and dataSourceUri are required")); return;
        }
        String folder = param(req, "folder", "/reports/wizard");
        String label  = param(req, "label", name);
        String db     = param(req, "db", "postgis_34_sample");
        String safeName = name.replaceAll("[^A-Za-z0-9_]", "_");
        File jrxml = new File(workDir, safeName + "_" + System.currentTimeMillis() + ".jrxml");

        // --- 1. scaffold (introspects the query against local PostgreSQL) ---
        List<String> sa = new ArrayList<>();
        addArg(sa, "--name", safeName);
        addArg(sa, "--title", param(req, "title", name));
        addArg(sa, "--subtitle", param(req, "subtitle", ""));
        addArg(sa, "--db", db);
        addArg(sa, "--query", query);
        addArg(sa, "--template", param(req, "template", "slate"));
        addArg(sa, "--out", jrxml.getAbsolutePath());
        String chart = param(req, "chart", "");
        if (!empty(chart) && !chart.equalsIgnoreCase("none")) {
            addArg(sa, "--chart", chart);
            addArg(sa, "--chart-category", param(req, "chartCategory", ""));
            addArg(sa, "--chart-value", param(req, "chartValue", ""));
            addArg(sa, "--chart-series", param(req, "chartSeries", ""));
        }
        addArg(sa, "--group-by", param(req, "groupBy", ""));
        addArg(sa, "--page-size", param(req, "pageSize", "letter"));
        if ("true".equalsIgnoreCase(req.getParameter("landscape"))) sa.add("--landscape");

        Map<String, String> scaffoldEnv = new HashMap<>();
        scaffoldEnv.put("PGPASSWORD", pgPassword);
        ScriptRunner.Result scaffold = runner(scaffoldEnv).python(pythonExe, script("scaffold_jrxml.py", true), sa);
        if (!scaffold.ok()) { json(resp, 500, stepFail("scaffold", scaffold)); return; }

        // --- 2. deploy to JasperReports Server (it compiles the jrxml server-side;
        //        deploy_report.ps1 also lints the SQL before publishing) ---
        String targetUri = (folder + "/" + safeName).replaceAll("//+", "/");
        List<String> da = new ArrayList<>();
        addArg(da, "-Jrxml", jrxml.getAbsolutePath());
        addArg(da, "-TargetUri", targetUri);
        addArg(da, "-Label", label);
        addArg(da, "-DataSourceUri", ds);
        da.add("-Overwrite");
        ScriptRunner.Result deploy = runner(jrsEnv()).powershell(script("deploy_report.ps1"), da);
        if (!deploy.ok()) { json(resp, 500, stepFail("deploy", deploy)); return; }

        String preview = req.getContextPath() + "/api/run?uri=" + enc(targetUri) + "&format=pdf";
        StringBuilder sb = new StringBuilder("{");
        sb.append("\"ok\":true");
        sb.append(",\"reportUri\":").append(Json.str(targetUri));
        sb.append(",\"previewUrl\":").append(Json.str(preview));
        sb.append(",\"output\":").append(Json.str(
                "[scaffold]\n" + scaffold.output + "\n[deploy]\n" + deploy.output));
        sb.append("}");
        json(resp, 200, sb.toString());
    }

    private void composeDashboard(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        String name    = req.getParameter("name");
        String reports = req.getParameter("reports");   // comma-separated full report URIs
        if (empty(name) || empty(reports)) { json(resp, 400, err("name and reports are required")); return; }
        String folder = param(req, "folder", "/reports/wizard");
        String label  = param(req, "label", name);
        int cols      = Integer.parseInt(param(req, "cols", "2"));
        String safeName = name.replaceAll("[^A-Za-z0-9_]", "_");

        String[] uris = reports.split(",");
        int gridW = 40, tileW = Math.max(1, gridW / cols), tileH = 10;
        StringBuilder dl = new StringBuilder();
        for (int i = 0; i < uris.length; i++) {
            String uri = uris[i].trim();
            if (uri.isEmpty()) continue;
            String leaf = uri.substring(uri.lastIndexOf('/') + 1);
            int col = i % cols, row = i / cols;
            if (dl.length() > 0) dl.append(",");
            dl.append("{")
              .append("\"kind\":\"report\",")
              .append("\"name\":").append(Json.str(leaf)).append(",")
              .append("\"title\":").append(Json.str(leaf)).append(",")
              .append("\"reportUri\":").append(Json.str(uri)).append(",")
              .append("\"x\":").append(col * tileW).append(",")
              .append("\"y\":").append(row * tileH).append(",")
              .append("\"width\":").append(tileW).append(",")
              .append("\"height\":").append(tileH)
              .append("}");
        }
        String manifest = "{"
                + "\"folder\":" + Json.str(folder) + ","
                + "\"name\":" + Json.str(safeName) + ","
                + "\"label\":" + Json.str(label) + ","
                + "\"cols\":" + cols + ","
                + "\"dashlets\":[" + dl + "]}";

        File mf = new File(workDir, safeName + "_dash_" + System.currentTimeMillis() + ".json");
        Files.write(mf.toPath(), manifest.getBytes(StandardCharsets.UTF_8));

        List<String> a = new ArrayList<>();
        addArg(a, "-Manifest", mf.getAbsolutePath());
        // keep compose's scratch dir in writable temp, not the repo-relative default
        addArg(a, "-WorkDir", new File(workDir, "dash_build_" + System.currentTimeMillis()).getAbsolutePath());
        ScriptRunner.Result r = runner(jrsEnv()).powershell(script("compose_dashboard.ps1"), a);

        String dashUri = (folder + "/" + safeName).replaceAll("//+", "/");
        String viewer = jrsUrl + "/dashboard/viewer.html#" + enc(dashUri);
        StringBuilder sb = new StringBuilder("{");
        sb.append("\"ok\":").append(r.ok());
        sb.append(",\"dashboardUri\":").append(Json.str(dashUri));
        sb.append(",\"viewerUrl\":").append(Json.str(viewer));
        sb.append(",\"output\":").append(Json.str(r.output));
        sb.append("}");
        json(resp, r.ok() ? 200 : 500, sb.toString());
    }

    // ------------------------------------------------------------- preview ----

    private void runReport(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        String uri = req.getParameter("uri");
        String fmt = param(req, "format", "pdf");
        if (empty(uri)) { json(resp, 400, err("uri is required")); return; }
        String rest = "/rest_v2/reports" + uri + "." + fmt;
        HttpURLConnection c = open(rest, "GET");
        int code = c.getResponseCode();
        resp.setStatus(code);
        String ct = c.getContentType();
        if (ct != null) resp.setContentType(ct);
        else resp.setContentType(contentTypeFor(fmt));
        try (InputStream in = code < 400 ? c.getInputStream() : c.getErrorStream();
             OutputStream out = resp.getOutputStream()) {
            if (in != null) {
                byte[] b = new byte[8192];
                int n;
                while ((n = in.read(b)) != -1) out.write(b, 0, n);
            }
        }
    }

    // --------------------------------------------------------- JRS helpers ----

    /** GET a JRS REST path and forward the JSON body verbatim to the response. */
    private void proxyJson(HttpServletResponse resp, String restPath) throws IOException {
        HttpURLConnection c = open(restPath, "GET");
        int code = c.getResponseCode();
        String body;
        try (InputStream in = code < 400 ? c.getInputStream() : c.getErrorStream()) {
            body = in == null ? "" : new String(in.readAllBytes(), StandardCharsets.UTF_8);
        }
        // 204 (no datasources/reports) -> hand back an empty-but-valid shape
        if (code == 204 || body.isEmpty()) body = "{}";
        json(resp, code == 204 ? 200 : code, body);
    }

    private HttpURLConnection open(String restPath, String method) throws IOException {
        URL u = new URL(jrsUrl + restPath);
        HttpURLConnection c = (HttpURLConnection) u.openConnection();
        c.setRequestMethod(method);
        c.setRequestProperty("Accept", "application/json");
        String auth = Base64.getEncoder().encodeToString((jrsUser + ":" + jrsPass).getBytes(StandardCharsets.UTF_8));
        c.setRequestProperty("Authorization", "Basic " + auth);
        c.setConnectTimeout(10000);
        c.setReadTimeout(timeoutSec * 1000);
        return c;
    }

    // --------------------------------------------------------------- utils ----

    private ScriptRunner runner(Map<String, String> extraEnv) {
        // Run from the writable temp dir, not the repo (LocalService can't CWD there).
        return new ScriptRunner(workDir, timeoutSec, extraEnv);
    }

    private Map<String, String> jrsEnv() {
        Map<String, String> e = new HashMap<>();
        e.put("JRS_URL", jrsUrl);
        e.put("JRS_USER", jrsUser);
        e.put("JRS_PASS", jrsPass);
        e.put("PGPASSWORD", pgPassword);
        return e;
    }

    private String script(String file) { return script(file, false); }
    private String script(String file, boolean ignore) { return scriptsDir + File.separator + file; }

    private static void addArg(List<String> a, String flag, String value) {
        if (value != null && !value.isEmpty()) { a.add(flag); a.add(value); }
    }

    private static String param(HttpServletRequest req, String name, String dflt) {
        String v = req.getParameter(name);
        return (v == null || v.isEmpty()) ? dflt : v;
    }

    private static boolean empty(String s) { return s == null || s.trim().isEmpty(); }

    private static String enc(String s) {
        try { return URLEncoder.encode(s, "UTF-8"); } catch (Exception e) { return s; }
    }

    private static String contentTypeFor(String fmt) {
        switch (fmt.toLowerCase()) {
            case "pdf":  return "application/pdf";
            case "html": return "text/html";
            case "csv":  return "text/csv";
            case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
            default:      return "application/octet-stream";
        }
    }

    private static String err(String msg) { return "{\"ok\":false,\"error\":" + Json.str(msg) + "}"; }

    private static String stepFail(String step, ScriptRunner.Result r) {
        return "{\"ok\":false,\"failedStep\":" + Json.str(step)
             + ",\"output\":" + Json.str(r.output) + "}";
    }

    private static void json(HttpServletResponse resp, int status, String body) throws IOException {
        resp.setStatus(status);
        resp.setContentType("application/json;charset=UTF-8");
        try (PrintWriter w = resp.getWriter()) { w.write(body); }
    }
}
