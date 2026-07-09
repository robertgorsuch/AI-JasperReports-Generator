import java.sql.*;

public class LoadPosTransactions {
    public static void main(String[] args) {
        // Credentials come from environment variables — never hardcode them.
        //   ACTIAN_JDBC_URL   e.g. jdbc:ingres://<host>:<port>/<db>
        //   ACTIAN_DB_USER, ACTIAN_DB_PASSWORD
        String url = System.getenv("ACTIAN_JDBC_URL");
        String user = System.getenv("ACTIAN_DB_USER");
        String password = System.getenv("ACTIAN_DB_PASSWORD");

        // The COPY VWLOAD SQL statement
        String copySql = "SET string_truncation IGNORE;\n" +
            "COPY \"pos_transactions\"() VWLOAD\n" +
            "FROM 'gs://rg_gcp_test/poc_sales_detail_extract_*.csv' WITH FDELIM = ',',\n" +
            "    RDELIM = '\\n',\n" +
            "    QUOTE = '\"',\n" +
            "    AUTO_DETECT_COMPRESSION,\n" +
            "    HEADER,\n" +
            "    gcs_email = '" + System.getenv("GCS_SA_EMAIL") + "',\n" +
            "    gcs_private_key_id = '" + System.getenv("GCS_SA_KEY_ID") + "',\n" +
            "    gcs_private_key = '" + System.getenv("GCS_SA_PRIVATE_KEY") + "';\n" +
            "SELECT COUNT(*) AS loaded_rows FROM pos_transactions;";

        Connection conn = null;
        Statement stmt = null;
        ResultSet rs = null;

        try {
            // Load the Ingres JDBC driver
            Class.forName("com.ingres.jdbc.IngresDriver");
            System.out.println("Ingres JDBC driver loaded successfully");

            // Establish connection
            System.out.println("Connecting to: " + url);
            conn = DriverManager.getConnection(url, user, password);
            System.out.println("Connected successfully!");
            System.out.println("");

            // Create statement
            stmt = conn.createStatement();

            // Execute COPY VWLOAD
            System.out.println("Executing COPY VWLOAD to load all 24 files...");
            System.out.println("");

            // Split the SQL into individual statements
            String[] statements = copySql.split(";");

            for (String sql : statements) {
                sql = sql.trim();
                if (!sql.isEmpty()) {
                    System.out.println("Executing: " + sql.substring(0, Math.min(100, sql.length())) + "...");

                    if (sql.toUpperCase().startsWith("SELECT")) {
                        rs = stmt.executeQuery(sql);

                        // Process result set
                        ResultSetMetaData metadata = rs.getMetaData();
                        int columnCount = metadata.getColumnCount();

                        while (rs.next()) {
                            for (int i = 1; i <= columnCount; i++) {
                                System.out.print(metadata.getColumnName(i) + ": " +
                                    rs.getObject(i) + " ");
                            }
                            System.out.println();
                        }
                        rs.close();
                    } else {
                        int result = stmt.executeUpdate(sql);
                        System.out.println("Result: " + result + " rows affected");
                    }
                    System.out.println("");
                }
            }

            System.out.println("COPY VWLOAD completed successfully!");

        } catch (ClassNotFoundException e) {
            System.err.println("Error: Ingres JDBC driver not found");
            System.err.println(e.getMessage());
        } catch (SQLException e) {
            System.err.println("SQL Error: " + e.getMessage());
            System.err.println("SQLState: " + e.getSQLState());
            System.err.println("Error Code: " + e.getErrorCode());
            e.printStackTrace();
        } finally {
            try {
                if (rs != null) rs.close();
                if (stmt != null) stmt.close();
                if (conn != null) conn.close();
            } catch (SQLException e) {
                System.err.println("Error closing resources: " + e.getMessage());
            }
        }
    }
}
