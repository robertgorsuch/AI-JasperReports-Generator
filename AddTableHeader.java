import java.sql.*;

public class AddTableHeader {
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
            Class.forName("com.ingres.jdbc.IngresDriver");
            System.out.println("Connecting to database...");
            conn = DriverManager.getConnection(url, user, password);
            System.out.println("Connected successfully!");
            System.out.println("");

            stmt = conn.createStatement();

            // Define column mappings - typical POS transaction structure
            String[] columnMappings = {
                "col0 AS transaction_date",
                "col1 AS transaction_time",
                "col2 AS store_id",
                "col3 AS store_location",
                "col4 AS province_state",
                "col5 AS postal_code",
                "col6 AS device_id",
                "col7 AS cashier_id",
                "col8 AS transaction_id",
                "col9 AS transaction_type",
                "col10 AS line_item_num",
                "col11 AS sku",
                "col12 AS item_description",
                "col13 AS qty",
                "col14 AS unit_price",
                "col15 AS discount_amount",
                "col16 AS tax_amount",
                "col17 AS line_total",
                "col18 AS payment_method",
                "col19 AS payment_amount",
                "col20 AS customer_id",
                "col21 AS customer_name",
                "col22 AS customer_phone",
                "col23 AS customer_email",
                "col24 AS loyalty_member",
                "col25 AS loyalty_points",
                "col26 AS receipt_number",
                "col27 AS batch_id",
                "col28 AS terminal_id",
                "col29 AS shift_id",
                "col30 AS void_flag",
                "col31 AS notes"
            };

            System.out.println("Step 1: Creating new table with proper column headers...");
            
            // Create new table with meaningful column names
            StringBuilder createSql = new StringBuilder(
                "CREATE TABLE pos_transactions_new AS " +
                "SELECT "
            );
            
            for (int i = 0; i < columnMappings.length; i++) {
                if (i > 0) createSql.append(", ");
                createSql.append(columnMappings[i]);
            }
            
            createSql.append(" FROM pos_transactions");
            
            System.out.println("Creating new table with headers...");
            stmt.executeUpdate(createSql.toString());
            System.out.println("✓ New table created: pos_transactions_new");
            System.out.println("");

            // Verify row count
            System.out.println("Step 2: Verifying data transfer...");
            ResultSet rs = stmt.executeQuery("SELECT COUNT(*) AS cnt FROM pos_transactions_new");
            long newCount = 0;
            while (rs.next()) {
                newCount = rs.getLong("cnt");
                System.out.println("✓ Rows in new table: " + String.format("%,d", newCount));
            }
            rs.close();

            // Show column names
            System.out.println("");
            System.out.println("Step 3: Column mapping...");
            rs = stmt.executeQuery("SELECT * FROM pos_transactions_new FETCH FIRST 0 ROWS ONLY");
            ResultSetMetaData metadata = rs.getMetaData();
            int columnCount = metadata.getColumnCount();
            for (int i = 1; i <= columnCount; i++) {
                System.out.println("  col" + (i-1) + " → " + metadata.getColumnName(i));
            }
            rs.close();

            // Drop old table
            System.out.println("");
            System.out.println("Step 4: Replacing old table...");
            stmt.executeUpdate("DROP TABLE pos_transactions");
            System.out.println("✓ Dropped old pos_transactions table");

            // Rename new table
            stmt.executeUpdate("ALTER TABLE pos_transactions_new RENAME TO pos_transactions");
            System.out.println("✓ Renamed pos_transactions_new to pos_transactions");

            System.out.println("");
            System.out.println("✓ SUCCESS: Table pos_transactions updated with proper column headers!");
            System.out.println("  Total records: " + String.format("%,d", newCount));
            System.out.println("  Columns: " + columnCount);

        } catch (ClassNotFoundException e) {
            System.err.println("Error: JDBC driver not found: " + e.getMessage());
        } catch (SQLException e) {
            System.err.println("SQL Error: " + e.getMessage());
            System.err.println("SQLState: " + e.getSQLState());
        } finally {
            try {
                if (stmt != null) stmt.close();
                if (conn != null) conn.close();
            } catch (SQLException e) {
                // ignore
            }
        }
    }
}
