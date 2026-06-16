package com.jasperwizard;

/**
 * Minimal JSON output helpers. The wizard never parses JSON in Java -- it proxies
 * raw JSON from JasperReports Server straight to the browser and lets JS parse it
 * -- so all we need here is safe string building for our own status responses.
 */
public final class Json {
    private Json() {}

    /** Escape a string for embedding inside a JSON double-quoted literal. */
    public static String esc(String s) {
        if (s == null) return "";
        StringBuilder b = new StringBuilder(s.length() + 16);
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"':  b.append("\\\""); break;
                case '\\': b.append("\\\\"); break;
                case '\n': b.append("\\n");  break;
                case '\r': b.append("\\r");  break;
                case '\t': b.append("\\t");  break;
                default:
                    if (c < 0x20) b.append(String.format("\\u%04x", (int) c));
                    else b.append(c);
            }
        }
        return b.toString();
    }

    /** A JSON string literal (quoted + escaped). */
    public static String str(String s) {
        return "\"" + esc(s) + "\"";
    }
}
