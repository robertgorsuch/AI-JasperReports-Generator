package com.jasperwizard;

import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.Base64;

/**
 * Thin REST client for JasperReports Server. Centralises the base URL, HTTP Basic
 * auth, and the read/stream helpers so the servlet's feature handlers don't each
 * re-implement connection wiring. Read/preview traffic goes through here; create
 * and deploy still shell out to the verified scripts via {@link ScriptRunner}.
 */
public class JrsClient {

    public static class Resp {
        public final int code;
        public final String body;
        Resp(int code, String body) { this.code = code; this.body = body; }
        public boolean ok() { return code >= 200 && code < 300; }
    }

    private final String baseUrl;
    private final String authHeader;
    private final int readTimeoutMs;

    public JrsClient(String baseUrl, String user, String pass, int readTimeoutSec) {
        this.baseUrl = baseUrl;
        this.authHeader = "Basic " + Base64.getEncoder()
                .encodeToString((user + ":" + pass).getBytes(StandardCharsets.UTF_8));
        this.readTimeoutMs = readTimeoutSec * 1000;
    }

    public String base() { return baseUrl; }

    public static String enc(String s) {
        try { return URLEncoder.encode(s, "UTF-8"); } catch (Exception e) { return s; }
    }

    /** Open an authenticated connection to a rest_v2-relative path. */
    public HttpURLConnection open(String restPath, String method, String accept) throws IOException {
        URL u = new URL(baseUrl + restPath);
        HttpURLConnection c = (HttpURLConnection) u.openConnection();
        c.setRequestMethod(method);
        if (accept != null) c.setRequestProperty("Accept", accept);
        c.setRequestProperty("Authorization", authHeader);
        c.setConnectTimeout(10000);
        c.setReadTimeout(readTimeoutMs);
        return c;
    }

    /** GET a path and return {code, body}. Reads the error stream on failure. */
    public Resp get(String restPath) throws IOException {
        HttpURLConnection c = open(restPath, "GET", "application/json");
        return read(c);
    }

    /** DELETE a path and return {code, body}. */
    public Resp delete(String restPath) throws IOException {
        HttpURLConnection c = open(restPath, "DELETE", "application/json");
        return read(c);
    }

    private Resp read(HttpURLConnection c) throws IOException {
        int code = c.getResponseCode();
        try (InputStream in = code < 400 ? c.getInputStream() : c.getErrorStream()) {
            String body = in == null ? "" : new String(in.readAllBytes(), StandardCharsets.UTF_8);
            return new Resp(code, body);
        }
    }

    /**
     * Stream a JRS path straight to the servlet response (used for report
     * rendering / exports). Preserves the upstream status and content type.
     */
    public void stream(String restPath, HttpServletResponse resp) throws IOException {
        HttpURLConnection c = open(restPath, "GET", null);
        int code = c.getResponseCode();
        resp.setStatus(code);
        String ct = c.getContentType();
        if (ct != null) resp.setContentType(ct);
        String disp = c.getHeaderField("Content-Disposition");
        if (disp != null) resp.setHeader("Content-Disposition", disp);
        try (InputStream in = code < 400 ? c.getInputStream() : c.getErrorStream();
             OutputStream out = resp.getOutputStream()) {
            if (in != null) {
                byte[] b = new byte[8192];
                int n;
                while ((n = in.read(b)) != -1) out.write(b, 0, n);
            }
        }
    }
}
