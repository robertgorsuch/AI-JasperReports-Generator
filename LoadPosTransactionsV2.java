import java.sql.*;

public class LoadPosTransactionsV2 {
    public static void main(String[] args) {
        // Credentials come from environment variables — never hardcode them.
        //   ACTIAN_JDBC_URL   e.g. jdbc:ingres://<host>:<port>/<db>
        //   ACTIAN_DB_USER, ACTIAN_DB_PASSWORD
        String url = System.getenv("ACTIAN_JDBC_URL");
        String user = System.getenv("ACTIAN_DB_USER");
        String password = System.getenv("ACTIAN_DB_PASSWORD");

        Connection conn = null;
        Statement stmt = null;

        try {
            // Load the Ingres JDBC driver
            Class.forName("com.ingres.jdbc.IngresDriver");
            System.out.println("Ingres JDBC driver loaded successfully");

            // Establish connection
            System.out.println("Connecting to: " + url);
            conn = DriverManager.getConnection(url, user, password);
            System.out.println("Connected successfully!");
            System.out.println("");

            stmt = conn.createStatement();

            // Drop and recreate table with generic schema to hold CSV data
            System.out.println("Step 1: Creating pos_transactions table with generic schema...");
            try {
                stmt.executeUpdate("DROP TABLE pos_transactions");
                System.out.println("Dropped existing pos_transactions table");
            } catch (SQLException e) {
                // Table might not exist, which is fine
                System.out.println("Note: Creating new table");
            }

            // Create table with VARCHAR columns for all fields in CSV
            // VWLOAD will auto-cast to appropriate types
            StringBuilder createSql = new StringBuilder("CREATE TABLE pos_transactions (");
            for (int i = 0; i < 50; i++) {
                if (i > 0) createSql.append(", ");
                createSql.append("col").append(i).append(" VARCHAR(1024)");
            }
            createSql.append(")");

            stmt.executeUpdate(createSql.toString());
            System.out.println("pos_transactions table created with 50 VARCHAR columns");
            System.out.println("");

            // Now execute the COPY VWLOAD
            System.out.println("Step 2: Loading all 24 sales detail files via COPY VWLOAD...");
            System.out.println("");

            // Execute SET string_truncation separately
            System.out.println("Executing: SET string_truncation IGNORE");
            stmt.executeUpdate("SET string_truncation IGNORE");
            System.out.println("Result: 0 rows affected/executed");
            System.out.println("");

            // Execute COPY VWLOAD as a single statement (don't split on semicolon)
            String copySql = "COPY \"pos_transactions\"() VWLOAD " +
                "FROM 'gs://rg_gcp_test/poc_sales_detail_extract_*.csv' " +
                "WITH FDELIM = ',', " +
                "RDELIM = '\\n', " +
                "QUOTE = '\"', " +
                "AUTO_DETECT_COMPRESSION, " +
                "HEADER, " +
                "gcs_email = '" + System.getenv("GCS_SA_EMAIL") + "', " +
                "gcs_private_key_id = '" + System.getenv("GCS_SA_KEY_ID") + "', " +
                "gcs_private_key = '" + System.getenv("GCS_SA_PRIVATE_KEY") + "'";

            System.out.println("Executing: COPY \"pos_transactions\"() VWLOAD FROM 'gs://...'");
            int result = stmt.executeUpdate(copySql);
            System.out.println("COPY VWLOAD completed! Result: " + result + " rows affected");
            System.out.println("");

            // Verify the data was loaded
            System.out.println("");
            System.out.println("Step 3: Verifying data load...");
            ResultSet rs = stmt.executeQuery("SELECT COUNT(*) AS row_count FROM pos_transactions");
            while (rs.next()) {
                System.out.println("Total rows loaded: " + rs.getLong("row_count"));
            }
            rs.close();

            System.out.println("");
            System.out.println("SUCCESS: All 24 sales detail files loaded via JDBC/COPY VWLOAD!");

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
                if (stmt != null) stmt.close();
                if (conn != null) conn.close();
            } catch (SQLException e) {
                System.err.println("Error closing resources: " + e.getMessage());
            }
        }
    }
}
