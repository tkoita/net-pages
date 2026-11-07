import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;

// ============================================================================
//  第3回 課題 LineServer.java の解答例（第4回の 0-2 で使う）
// ----------------------------------------------------------------------------
//  第4回は、このサーバをコピーして、接続ごとにスレッドを作る形に直します。
//  自分の LineServer.java が動くなら、そちらを使ってください。
//  コンパイル：javac -encoding UTF-8 LineServer.java
//  実行      ：java LineServer 40001（40001 は省略できる）
// ============================================================================
public class LineServer {
  public static void main(String[] args) throws IOException {
    int port = (args.length > 0) ? Integer.parseInt(args[0]) : 40001;   // 省略したら 40001

    try (ServerSocket server = new ServerSocket(port)) {
      System.out.println("LISTENING port=" + port);

      while (true) {
        try (Socket s = server.accept()) {
          System.err.println("ACCEPTED " + s.getRemoteSocketAddress());
          handle(s);
          System.err.println("CLOSED " + s.getRemoteSocketAddress());
        } catch (IOException e) {
          // クライアント1人のエラーで、サーバ全体を止めない
          System.err.println("client error: " + e.getMessage());
        }
      }
    }
  }

  // 1本の接続を最後まで相手する。QUIT か切断で戻る。
  static void handle(Socket s) throws IOException {
    BufferedReader in = new BufferedReader(
        new InputStreamReader(s.getInputStream(), StandardCharsets.UTF_8));
    BufferedWriter out = new BufferedWriter(
        new OutputStreamWriter(s.getOutputStream(), StandardCharsets.UTF_8));

    String line;
    while ((line = in.readLine()) != null) {
      System.err.println("RECEIVED " + line);
      if (line.equals("QUIT")) {
        send(out, "BYE");
        return;                         // この接続だけを閉じる（サーバは続ける）
      }
      send(out, reply(line));
    }
  }

  static String reply(String line) {
    if (line.equals("PING")) {
      return "PONG";
    }
    int sp = line.indexOf(' ');
    if (sp > 0) {
      String cmd = line.substring(0, sp);
      String arg = line.substring(sp + 1);   // 最初の半角スペースより後ろ、全部
      if (!arg.isEmpty()) {
        if (cmd.equals("ECHO")) {
          return arg;                        // trim しない
        }
        if (cmd.equals("LEN")) {
          return String.valueOf(arg.getBytes(StandardCharsets.UTF_8).length);
        }
      }
    }
    return "ERR unknown command";
  }

  static void send(BufferedWriter out, String text) throws IOException {
    out.write(text);
    out.write("\n");                     // 0x0A を1バイト。newLine() は使わない
    out.flush();
  }
}
