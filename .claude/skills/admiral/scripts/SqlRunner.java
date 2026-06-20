// SqlRunner.java — minimal generic JDBC SQL runner for the Actian Ingres driver.
//
// Used by sql.ps1 as the JDBC engine. It executes a batch of ;-separated SQL
// statements against an Avalanche warehouse and emits the results as a single
// JSON array on stdout, so the PowerShell side never has to parse a result grid.
//
//   java -cp "<iijdbc.jar>;<thisDir>" SqlRunner <connFile> <sqlFile> [maxRows]
//
//   connFile : 3 lines — jdbcUrl / user / password   (kept out of the process args)
//   sqlFile  : UTF-8 SQL text, one or more ;-separated statements
//   maxRows  : per-statement row cap (default 1000)
//
// Output (stdout) is a JSON array, one element per statement:
//   {"type":"query","columns":[...],"rows":[[...]],"rowCount":N}
//   {"type":"update","updateCount":N}
//   {"type":"error","message":"...","sqlState":"...","errorCode":N}
//
// No third-party libraries — a tiny hand-rolled JSON writer keeps this driver-only.

import java.sql.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

public class SqlRunner {

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("usage: SqlRunner <connFile> <sqlFile> [maxRows]");
            System.exit(2);
        }
        int maxRows = args.length > 2 ? Integer.parseInt(args[2]) : 1000;

        List<String> cl = Files.readAllLines(Paths.get(args[0]), StandardCharsets.UTF_8);
        if (cl.size() < 3) { System.err.println("connFile must have url/user/password lines"); System.exit(2); }
        String url = cl.get(0), user = cl.get(1), pass = cl.get(2);
        String batch = new String(Files.readAllBytes(Paths.get(args[1])), StandardCharsets.UTF_8);
        List<String> stmts = splitStatements(batch);

        try {
            Class.forName("com.ingres.jdbc.IngresDriver");
        } catch (ClassNotFoundException e) {
            System.out.println("[{\"type\":\"error\",\"message\":" + jsonStr(
                "Ingres JDBC driver not on classpath (iijdbc.jar): " + e.getMessage())
                + ",\"sqlState\":null,\"errorCode\":0}]");
            return;
        }

        StringBuilder out = new StringBuilder("[");
        boolean first = true;
        try (Connection conn = DriverManager.getConnection(url, user, pass);
             Statement st = conn.createStatement()) {
            st.setMaxRows(maxRows);
            for (String sql : stmts) {
                if (sql.trim().isEmpty()) continue;
                if (!first) out.append(",");
                first = false;
                try {
                    boolean hasRs = st.execute(sql);
                    if (hasRs) {
                        try (ResultSet rs = st.getResultSet()) { out.append(resultToJson(rs)); }
                    } else {
                        out.append("{\"type\":\"update\",\"updateCount\":").append(st.getUpdateCount()).append("}");
                    }
                } catch (SQLException e) {
                    out.append("{\"type\":\"error\",\"message\":").append(jsonStr(e.getMessage()))
                       .append(",\"sqlState\":").append(jsonStr(e.getSQLState()))
                       .append(",\"errorCode\":").append(e.getErrorCode()).append("}");
                }
            }
        } catch (SQLException e) {
            // Connection-level failure: emit a single error element so the caller can render it.
            String pre = first ? "" : ",";
            out.append(pre).append("{\"type\":\"error\",\"message\":").append(jsonStr(e.getMessage()))
               .append(",\"sqlState\":").append(jsonStr(e.getSQLState()))
               .append(",\"errorCode\":").append(e.getErrorCode()).append("}");
        }
        out.append("]");
        System.out.println(out.toString());
    }

    // Split on top-level ';' — ignoring semicolons inside '...' string literals and
    // "..." quoted identifiers. Adequate for the SQL this skill generates (incl. VWLOAD
    // clauses whose PEM keys contain no semicolons).
    static List<String> splitStatements(String s) {
        List<String> out = new ArrayList<>();
        StringBuilder cur = new StringBuilder();
        boolean inS = false, inD = false;
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '\'' && !inD) inS = !inS;
            else if (c == '"' && !inS) inD = !inD;
            if (c == ';' && !inS && !inD) { out.add(cur.toString()); cur.setLength(0); }
            else cur.append(c);
        }
        if (cur.toString().trim().length() > 0) out.add(cur.toString());
        return out;
    }

    static String resultToJson(ResultSet rs) throws SQLException {
        ResultSetMetaData m = rs.getMetaData();
        int n = m.getColumnCount();
        StringBuilder sb = new StringBuilder("{\"type\":\"query\",\"columns\":[");
        for (int i = 1; i <= n; i++) { if (i > 1) sb.append(","); sb.append(jsonStr(m.getColumnLabel(i))); }
        sb.append("],\"rows\":[");
        int rc = 0; boolean fr = true;
        while (rs.next()) {
            if (!fr) sb.append(","); fr = false;
            sb.append("[");
            for (int i = 1; i <= n; i++) {
                if (i > 1) sb.append(",");
                Object v = rs.getObject(i);
                if (rs.wasNull() || v == null) sb.append("null");
                else sb.append(jsonStr(v.toString()));
            }
            sb.append("]"); rc++;
        }
        sb.append("],\"rowCount\":").append(rc).append("}");
        return sb.toString();
    }

    static String jsonStr(String s) {
        if (s == null) return "null";
        StringBuilder b = new StringBuilder("\"");
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
        return b.append("\"").toString();
    }
}
