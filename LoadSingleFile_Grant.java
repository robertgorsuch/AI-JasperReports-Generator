import java.sql.*;

public class LoadSingleFile_Grant {
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

            // Grant all privileges on pos_transactions to public
            String grantSql = "GRANT ALL ON TABLE pos_transactions TO PUBLIC";

            System.out.println("Executing: " + grantSql);
            stmt.executeUpdate(grantSql);
            System.out.println("");
            System.out.println("✓ SUCCESS: All permissions granted on pos_transactions to PUBLIC");

        } catch (ClassNotFoundException e) {
            System.err.println("Error: JDBC driver not found");
            System.err.println(e.getMessage());
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
