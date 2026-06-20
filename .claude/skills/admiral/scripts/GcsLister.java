// GcsLister.java — list GCS bucket objects using a service-account JSON key.
//
// Used by sql.ps1 -Action list-gcs. Authenticates via RS256 JWT → Google OAuth2
// access token, then paginates the GCS JSON API. No third-party libraries needed —
// only standard java.security and java.net.
//
//   java -cp "<thisDir>" GcsLister <sa.json> <bucket> [prefix]
//
// Output (stdout): JSON array of {name, size} objects, one per GCS object.
// Errors: written to stderr; exit code 1.

import java.io.*;
import java.net.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.security.spec.*;
import java.util.Base64;

public class GcsLister {
    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("usage: GcsLister <sa.json> <bucket> [prefix]");
            System.exit(2);
        }
        String saJson  = new String(Files.readAllBytes(Paths.get(args[0])), StandardCharsets.UTF_8);
        String bucket  = args[1];
        String prefix  = args.length > 2 ? args[2] : "";

        // Parse SA JSON
        String clientEmail = extractJson(saJson, "client_email");
        String rawKey      = extractJson(saJson, "private_key");
        if (clientEmail == null || rawKey == null) {
            System.err.println("SA JSON missing client_email or private_key");
            System.exit(1);
        }
        // Strip PEM wrapper + whitespace for PKCS8 decode
        String b64Key = rawKey
            .replace("-----BEGIN PRIVATE KEY-----", "")
            .replace("-----END PRIVATE KEY-----",   "")
            .replaceAll("\\s+", "");
        PrivateKey pk = KeyFactory.getInstance("RSA").generatePrivate(
            new PKCS8EncodedKeySpec(Base64.getDecoder().decode(b64Key)));

        // Build RS256 JWT
        long now = System.currentTimeMillis() / 1000;
        String hdr = b64u("{\"alg\":\"RS256\",\"typ\":\"JWT\"}");
        String pay = b64u("{\"iss\":\"" + clientEmail
            + "\",\"scope\":\"https://www.googleapis.com/auth/devstorage.read_only\""
            + ",\"aud\":\"https://oauth2.googleapis.com/token\""
            + ",\"exp\":" + (now + 3600) + ",\"iat\":" + now + "}");
        String sigInput = hdr + "." + pay;
        Signature signer = Signature.getInstance("SHA256withRSA");
        signer.initSign(pk);
        signer.update(sigInput.getBytes(StandardCharsets.UTF_8));
        String jwt = sigInput + "." + Base64.getUrlEncoder().withoutPadding().encodeToString(signer.sign());

        // Exchange JWT for access token
        String tokenResp = httpPost("https://oauth2.googleapis.com/token",
            "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=" + jwt,
            "application/x-www-form-urlencoded", null);
        String token = extractJson(tokenResp, "access_token");
        if (token == null) {
            System.err.println("Failed to get access token: " + tokenResp);
            System.exit(1);
        }

        // Paginate GCS object listing — output one "name\tsize" line per object
        String pageToken = "";
        do {
            String url = "https://storage.googleapis.com/storage/v1/b/"
                + URLEncoder.encode(bucket, "UTF-8") + "/o?maxResults=1000"
                + (prefix.isEmpty()    ? "" : "&prefix="    + URLEncoder.encode(prefix,    "UTF-8"))
                + (pageToken.isEmpty() ? "" : "&pageToken=" + URLEncoder.encode(pageToken, "UTF-8"));
            String resp = httpGet(url, token);

            // Scan within the "items" array for name+size of each object
            int itemsIdx = resp.indexOf("\"items\"");
            if (itemsIdx >= 0) {
                int pos = resp.indexOf('[', itemsIdx) + 1;
                while (pos < resp.length()) {
                    int nameIdx = resp.indexOf("\"name\"", pos);
                    if (nameIdx < 0) break;
                    String name = extractJson(resp.substring(nameIdx), "name");
                    // Bound size search to the current object (before next "name")
                    int nextNameIdx = resp.indexOf("\"name\"", nameIdx + 6);
                    int searchEnd   = (nextNameIdx < 0) ? resp.length() : nextNameIdx;
                    int sizeIdx     = resp.indexOf("\"size\"", nameIdx);
                    String size     = (sizeIdx >= 0 && sizeIdx < searchEnd)
                                      ? extractJson(resp.substring(sizeIdx), "size") : "0";
                    if (name != null) {
                        System.out.println(name + "\t" + size);
                    }
                    pos = nameIdx + 6;
                }
            }
            pageToken = extractJson(resp, "nextPageToken");
            if (pageToken == null) pageToken = "";
        } while (!pageToken.isEmpty());
    }

    static String b64u(String s) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(s.getBytes(StandardCharsets.UTF_8));
    }

    static String httpGet(String url, String token) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        if (token != null) c.setRequestProperty("Authorization", "Bearer " + token);
        return readAll(c);
    }

    static String httpPost(String url, String body, String ct, String token) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setRequestMethod("POST");
        c.setDoOutput(true);
        c.setRequestProperty("Content-Type", ct);
        if (token != null) c.setRequestProperty("Authorization", "Bearer " + token);
        try (OutputStream os = c.getOutputStream()) { os.write(body.getBytes(StandardCharsets.UTF_8)); }
        return readAll(c);
    }

    static String readAll(HttpURLConnection c) throws Exception {
        InputStream is = c.getResponseCode() < 400 ? c.getInputStream() : c.getErrorStream();
        ByteArrayOutputStream buf = new ByteArrayOutputStream();
        byte[] b = new byte[8192]; int n;
        while ((n = is.read(b)) >= 0) buf.write(b, 0, n);
        return buf.toString("UTF-8");
    }

    // Minimal JSON string/number extractor — handles \n, \", etc. in strings.
    static String extractJson(String json, String key) {
        int idx = json.indexOf("\"" + key + "\"");
        if (idx < 0) return null;
        idx = json.indexOf(':', idx) + 1;
        while (idx < json.length() && json.charAt(idx) == ' ') idx++;
        if (idx >= json.length()) return null;
        char first = json.charAt(idx);
        if (first != '"') {
            // Non-string value (number, boolean): read until delimiter
            int end = idx;
            while (end < json.length() && ",}\n\r ".indexOf(json.charAt(end)) < 0) end++;
            return json.substring(idx, end);
        }
        idx++; // skip opening quote
        StringBuilder sb = new StringBuilder();
        while (idx < json.length()) {
            char c = json.charAt(idx);
            if (c == '"') break;
            if (c == '\\' && idx + 1 < json.length()) {
                char e = json.charAt(++idx);
                if      (e == 'n') sb.append('\n');
                else if (e == 'r') sb.append('\r');
                else if (e == 't') sb.append('\t');
                else               sb.append(e);
            } else sb.append(c);
            idx++;
        }
        return sb.toString();
    }

    static String jsonStr(String s) {
        if (s == null) return "null";
        StringBuilder b = new StringBuilder("\"");
        for (char c : s.toCharArray()) {
            if      (c == '"')  b.append("\\\"");
            else if (c == '\\') b.append("\\\\");
            else if (c == '\n') b.append("\\n");
            else if (c == '\r') b.append("\\r");
            else                b.append(c);
        }
        return b.append("\"").toString();
    }
}
