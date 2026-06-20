// S3Lister.java — list S3 bucket objects using AWS SigV4 signing.
//
// Used by sql.ps1 -Action list-s3. Authenticates with an AWS access/secret key pair
// and AWS Signature Version 4 request signing. No third-party libraries needed.
//
//   java -cp "<thisDir>" S3Lister <access-key> <secret-key> <region> <bucket> [prefix]
//
// Output (stdout): one "key\tsize" line per object.
// Errors: written to stderr; exit code 1.

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.text.*;
import java.util.*;
import javax.crypto.*;
import javax.crypto.spec.*;

public class S3Lister {
    public static void main(String[] args) throws Exception {
        if (args.length < 4) {
            System.err.println("Usage: S3Lister <access-key> <secret-key> <region> <bucket> [prefix]");
            System.exit(1);
        }
        String accessKey = args[0];
        String secretKey = args[1];
        String region    = args[2];
        String bucket    = args[3];
        String prefix    = args.length > 4 ? args[4] : "";

        // Virtual-hosted-style endpoint: https://<bucket>.s3.<region>.amazonaws.com/
        String host = bucket + ".s3." + region + ".amazonaws.com";
        String path = "/";

        String contToken = "";
        do {
            // Build sorted query parameters (SigV4 requires canonical ordering)
            TreeMap<String, String> qp = new TreeMap<>();
            qp.put("list-type", "2");
            qp.put("max-keys",  "1000");
            if (!prefix.isEmpty())    qp.put("prefix",             prefix);
            if (!contToken.isEmpty()) qp.put("continuation-token", contToken);

            StringBuilder canonicalQuery = new StringBuilder();
            for (Map.Entry<String, String> e : qp.entrySet()) {
                if (canonicalQuery.length() > 0) canonicalQuery.append('&');
                canonicalQuery.append(uriEncode(e.getKey())).append('=').append(uriEncode(e.getValue()));
            }
            String cq = canonicalQuery.toString();

            // Timestamp (UTC)
            SimpleDateFormat dateFmt     = new SimpleDateFormat("yyyyMMdd");
            SimpleDateFormat datetimeFmt = new SimpleDateFormat("yyyyMMdd'T'HHmmss'Z'");
            dateFmt.setTimeZone(TimeZone.getTimeZone("UTC"));
            datetimeFmt.setTimeZone(TimeZone.getTimeZone("UTC"));
            Date now      = new Date();
            String date   = dateFmt.format(now);
            String dt     = datetimeFmt.format(now);

            // Canonical request
            String payloadHash      = sha256hex("");
            String canonicalHeaders = "host:" + host + "\nx-amz-date:" + dt + "\n";
            String signedHeaders    = "host;x-amz-date";
            String canonicalReq     = "GET\n" + path + "\n" + cq + "\n"
                                    + canonicalHeaders + "\n" + signedHeaders + "\n" + payloadHash;

            // String to sign
            String scope        = date + "/" + region + "/s3/aws4_request";
            String stringToSign = "AWS4-HMAC-SHA256\n" + dt + "\n" + scope + "\n" + sha256hex(canonicalReq);

            // Signing key: HMAC(HMAC(HMAC(HMAC("AWS4"+secret, date), region), "s3"), "aws4_request")
            byte[] signingKey = hmac(hmac(hmac(hmac(
                ("AWS4" + secretKey).getBytes(StandardCharsets.UTF_8), date), region), "s3"), "aws4_request");
            String signature = hex(hmac(signingKey, stringToSign));

            // Authorization header
            String auth = "AWS4-HMAC-SHA256 Credential=" + accessKey + "/" + scope
                        + ", SignedHeaders=" + signedHeaders + ", Signature=" + signature;

            URL url = new URL("https://" + host + path + "?" + cq);
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setConnectTimeout(30000);
            conn.setReadTimeout(60000);
            conn.setRequestProperty("Host",          host);
            conn.setRequestProperty("x-amz-date",   dt);
            conn.setRequestProperty("Authorization", auth);

            int code = conn.getResponseCode();
            if (code != 200) {
                InputStream es = conn.getErrorStream();
                System.err.println("S3 error " + code + ": " + (es != null ? readStream(es) : "(no body)"));
                System.exit(1);
            }
            String resp = readStream(conn.getInputStream());

            // Parse ListObjectsV2 XML: iterate <Contents> blocks
            int pos = 0;
            while (true) {
                int cs = resp.indexOf("<Contents>", pos);
                if (cs < 0) break;
                int ce = resp.indexOf("</Contents>", cs);
                if (ce < 0) break;
                String block = resp.substring(cs, ce + 11);
                String key  = xmlText(block, "Key");
                String size = xmlText(block, "Size");
                if (key != null) System.out.println(key + "\t" + (size != null ? size : "0"));
                pos = ce + 11;
            }

            String nextToken = xmlText(resp, "NextContinuationToken");
            contToken = nextToken != null ? nextToken : "";
        } while (!contToken.isEmpty());
    }

    static String xmlText(String xml, String tag) {
        int s = xml.indexOf("<" + tag + ">");
        if (s < 0) return null;
        s += tag.length() + 2;
        int e = xml.indexOf("</" + tag + ">", s);
        return e < 0 ? null : xml.substring(s, e);
    }

    // RFC 3986 unreserved characters only; percent-encode everything else.
    static String uriEncode(String s) {
        StringBuilder out = new StringBuilder();
        for (byte b : s.getBytes(StandardCharsets.UTF_8)) {
            int v = b & 0xFF;
            char c = (char) v;
            if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
                    || c == '-' || c == '_' || c == '.' || c == '~') {
                out.append(c);
            } else {
                out.append(String.format("%%%02X", v));
            }
        }
        return out.toString();
    }

    static String sha256hex(String data) throws Exception {
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        return hex(md.digest(data.getBytes(StandardCharsets.UTF_8)));
    }

    static byte[] hmac(byte[] key, String data) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(key, "HmacSHA256"));
        return mac.doFinal(data.getBytes(StandardCharsets.UTF_8));
    }

    static String hex(byte[] bytes) {
        StringBuilder sb = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) sb.append(String.format("%02x", b & 0xFF));
        return sb.toString();
    }

    static String readStream(InputStream is) throws Exception {
        if (is == null) return "";
        ByteArrayOutputStream buf = new ByteArrayOutputStream();
        byte[] b = new byte[8192]; int n;
        while ((n = is.read(b)) >= 0) buf.write(b, 0, n);
        return buf.toString("UTF-8");
    }
}
