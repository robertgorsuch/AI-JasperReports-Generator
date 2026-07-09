import java.sql.*;

public class LoadSingleFile {
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

            // Drop existing table
            System.out.println("Step 1: Preparing pos_transactions table...");
            try {
                stmt.executeUpdate("DROP TABLE pos_transactions");
                System.out.println("Dropped existing pos_transactions table");
            } catch (SQLException e) {
                System.out.println("Table didn't exist (that's okay)");
            }

            // Create table with 32 VARCHAR columns (matching CSV field count)
            StringBuilder createSql = new StringBuilder("CREATE TABLE pos_transactions (");
            for (int i = 0; i < 32; i++) {
                if (i > 0) createSql.append(", ");
                createSql.append("col").append(i).append(" VARCHAR(1024)");
            }
            createSql.append(")");

            stmt.executeUpdate(createSql.toString());
            System.out.println("pos_transactions table created with 32 VARCHAR columns");
            System.out.println("");

            // Load the single CSV file
            System.out.println("Step 2: Loading poc_sales_detail_extract_201901.csv from GCS...");
            System.out.println("");

            String copySql = "COPY \"pos_transactions\"() VWLOAD " +
                "FROM 'gs://rg_gcp_test/poc_sales_detail_extract_201901.csv' " +
                "WITH FDELIM = ',', " +
                "RDELIM = '\\n', " +
                "QUOTE = '\"', " +
                "AUTO_DETECT_COMPRESSION, " +
                "HEADER, " +
                "gcs_email = '" + System.getenv("GCS_SA_EMAIL") + "', " +
                "gcs_private_key_id = '" + System.getenv("GCS_SA_KEY_ID") + "', " +
                "gcs_private_key = '" + System.getenv("GCS_SA_PRIVATE_KEY") + "'";

            System.out.println("Executing COPY VWLOAD for January 2019 file...");
            long startTime = System.currentTimeMillis();

            int result = stmt.executeUpdate(copySql);

            long endTime = System.currentTimeMillis();
            long duration = (endTime - startTime) / 1000;

            System.out.println("✓ COPY VWLOAD completed successfully!");
            System.out.println("  Result: " + result + " rows affected");
            System.out.println("  Duration: " + duration + " seconds");
            System.out.println("");

            // Verify the data
            System.out.println("Step 3: Verifying data load...");
            System.out.println("");

            ResultSet rs = stmt.executeQuery("SELECT COUNT(*) AS row_count FROM pos_transactions");
            long rowCount = 0;
            while (rs.next()) {
                rowCount = rs.getLong("row_count");
                System.out.println("✓ Total rows loaded: " + rowCount);
            }
            rs.close();

            // Show sample data
            System.out.println("");
            System.out.println("Sample data (first 5 rows, first 5 columns):");
            System.out.println("");

            rs = stmt.executeQuery("SELECT col0, col1, col2, col3, col4 FROM pos_transactions FETCH FIRST 5 ROWS ONLY");
            int rowNum = 0;
            while (rs.next() && rowNum < 5) {
                rowNum++;
                System.out.print("Row " + rowNum + ": ");
                for (int i = 1; i <= 5; i++) {
                    String val = rs.getString(i);
                    if (val != null && val.length() > 30) {
                        val = val.substring(0, 27) + "...";
                    }
                    System.out.print(val + " | ");
                }
                System.out.println();
            }
            rs.close();

            System.out.println("");
            System.out.println("✓ SUCCESS: poc_sales_detail_extract_201901.csv loaded via JDBC/COPY VWLOAD!");
            System.out.println("  File: gs://rg_gcp_test/poc_sales_detail_extract_201901.csv");
            System.out.println("  Total rows: " + rowCount);

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
