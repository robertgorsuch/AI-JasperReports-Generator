import java.sql.*;

public class LoadAllFiles {
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

            // Check current row count
            System.out.println("Step 1: Checking current data...");
            ResultSet rs = stmt.executeQuery("SELECT COUNT(*) AS row_count FROM pos_transactions");
            long currentRows = 0;
            while (rs.next()) {
                currentRows = rs.getLong("row_count");
                System.out.println("Current rows in pos_transactions: " + String.format("%,d", currentRows));
            }
            rs.close();
            System.out.println("");

            // Load ALL 24 files using wildcard pattern
            System.out.println("Step 2: Loading all 24 sales detail files from GCS...");
            System.out.println("Source: gs://rg_gcp_test/poc_sales_detail_extract_*.csv");
            System.out.println("");

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

            System.out.println("Executing COPY VWLOAD for all 24 files...");
            long startTime = System.currentTimeMillis();

            int result = stmt.executeUpdate(copySql);

            long endTime = System.currentTimeMillis();
            long duration = (endTime - startTime) / 1000;

            System.out.println("✓ COPY VWLOAD completed!");
            System.out.println("  Rows affected in this load: " + String.format("%,d", result));
            System.out.println("  Duration: " + duration + " seconds");
            System.out.println("");

            // Verify final row count
            System.out.println("Step 3: Verifying final data...");
            rs = stmt.executeQuery("SELECT COUNT(*) AS row_count FROM pos_transactions");
            long finalRows = 0;
            while (rs.next()) {
                finalRows = rs.getLong("row_count");
                System.out.println("Final rows in pos_transactions: " + String.format("%,d", finalRows));
            }
            rs.close();

            long newRows = finalRows - currentRows;
            System.out.println("New rows added this load: " + String.format("%,d", newRows));
            System.out.println("");

            // Show data distribution by date
            System.out.println("Step 4: Data distribution by month...");
            rs = stmt.executeQuery(
                "SELECT SUBSTR(col0, 1, 7) AS month, COUNT(*) AS count " +
                "FROM pos_transactions " +
                "GROUP BY SUBSTR(col0, 1, 7) " +
                "ORDER BY month"
            );
            while (rs.next()) {
                System.out.println("  " + rs.getString("month") + ": " + String.format("%,d", rs.getLong("count")) + " rows");
            }
            rs.close();

            System.out.println("");
            System.out.println("✓ SUCCESS: All 24 sales detail files loaded!");
            System.out.println("  Total records: " + String.format("%,d", finalRows));

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
