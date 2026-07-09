import java.sql.*;

public class CreateDashboardViews {
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
            System.out.println("Creating dashboard aggregation views...");
            conn = DriverManager.getConnection(url, user, password);
            stmt = conn.createStatement();

            // Drop existing tables
            String[] tablesToDrop = {
                "dashboard_daily_sales",
                "dashboard_store_performance",
                "dashboard_product_performance",
                "dashboard_payment_methods",
                "dashboard_hourly_sales",
                "dashboard_top_locations",
                "dashboard_customer_payment"
            };

            for (String table : tablesToDrop) {
                try {
                    stmt.executeUpdate("DROP TABLE " + table);
                    System.out.println("  Dropped: " + table);
                } catch (SQLException e) {
                    // Table might not exist, that's ok
                }
            }

            System.out.println("");
            System.out.println("Creating new dashboard tables...");

            // 1. Daily Sales Summary
            stmt.executeUpdate(
                "CREATE TABLE dashboard_daily_sales AS " +
                "SELECT transaction_date, COUNT(*) AS transaction_count, " +
                "  COUNT(DISTINCT store_id) AS store_count, " +
                "  COUNT(DISTINCT customer_id) AS customer_count " +
                "FROM pos_transactions GROUP BY transaction_date");
            System.out.println("✓ dashboard_daily_sales");

            // 2. Store Performance
            stmt.executeUpdate(
                "CREATE TABLE dashboard_store_performance AS " +
                "SELECT store_id, store_location, province_state, " +
                "  COUNT(*) AS transaction_count " +
                "FROM pos_transactions " +
                "GROUP BY store_id, store_location, province_state");
            System.out.println("✓ dashboard_store_performance");

            // 3. Product Performance
            stmt.executeUpdate(
                "CREATE TABLE dashboard_product_performance AS " +
                "SELECT sku, item_description, COUNT(*) AS units_sold " +
                "FROM pos_transactions WHERE sku IS NOT NULL " +
                "GROUP BY sku, item_description");
            System.out.println("✓ dashboard_product_performance");

            // 4. Payment Methods
            stmt.executeUpdate(
                "CREATE TABLE dashboard_payment_methods AS " +
                "SELECT payment_method, COUNT(*) AS transaction_count " +
                "FROM pos_transactions WHERE payment_method IS NOT NULL " +
                "GROUP BY payment_method");
            System.out.println("✓ dashboard_payment_methods");

            // 5. Hourly Sales
            stmt.executeUpdate(
                "CREATE TABLE dashboard_hourly_sales AS " +
                "SELECT SUBSTR(transaction_time, 1, 2) AS hour, " +
                "  COUNT(*) AS transaction_count " +
                "FROM pos_transactions " +
                "GROUP BY SUBSTR(transaction_time, 1, 2)");
            System.out.println("✓ dashboard_hourly_sales");

            // 6. Top Locations
            stmt.executeUpdate(
                "CREATE TABLE dashboard_top_locations AS " +
                "SELECT store_location, province_state, COUNT(*) AS transaction_count " +
                "FROM pos_transactions " +
                "GROUP BY store_location, province_state " +
                "ORDER BY transaction_count DESC");
            System.out.println("✓ dashboard_top_locations");

            // 7. Customer Payment
            stmt.executeUpdate(
                "CREATE TABLE dashboard_customer_payment AS " +
                "SELECT customer_id, payment_method, COUNT(*) AS usage_count " +
                "FROM pos_transactions WHERE customer_id IS NOT NULL " +
                "GROUP BY customer_id, payment_method");
            System.out.println("✓ dashboard_customer_payment");

            System.out.println("");
            System.out.println("Dashboard Summary:");
            ResultSet rs = stmt.executeQuery(
                "SELECT COUNT(*) AS total_trans, COUNT(DISTINCT store_id) AS stores, " +
                "  COUNT(DISTINCT customer_id) AS customers " +
                "FROM pos_transactions");
            
            while (rs.next()) {
                System.out.println("  Total Transactions: " + String.format("%,d", rs.getLong("total_trans")));
                System.out.println("  Stores: " + rs.getLong("stores"));
                System.out.println("  Unique Customers: " + rs.getLong("customers"));
            }
            rs.close();

            System.out.println("");
            System.out.println("✓ Dashboard data views created successfully!");

        } catch (Exception e) {
            System.err.println("Error: " + e.getMessage());
            e.printStackTrace();
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
