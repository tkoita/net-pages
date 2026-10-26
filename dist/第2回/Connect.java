import java.net.*;

public class Connect {
  public static void main(String[] args) {
    String host = args[0];
    int port = Integer.parseInt(args[1]);

    long start = System.currentTimeMillis();
    try (Socket socket = new Socket()) {
      socket.connect(new InetSocketAddress(host, port), 2000);
      System.out.println("CONNECTED");
    } catch (UnknownHostException e) {
      System.out.println("UNKNOWN_HOST");
    } catch (SocketTimeoutException e) {
      System.out.println("TIMEOUT");
    } catch (ConnectException e) {
      System.out.println("REFUSED");
    } catch (Exception e) {
      System.out.println("ERROR: " + e.getClass().getSimpleName());
    }
    System.out.println("ELAPSED_MS=" + (System.currentTimeMillis() - start));
  }
}
