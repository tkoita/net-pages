import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;

// 第3回：キーボードから打った行を、サーバに送り続ける対話クライアント
//   1行打つ → サーバへ送る → 返事を1行待って表示する、をくり返す。
//   終わるときは Ctrl + C。
//
//   javac -encoding UTF-8 Talk.java
//   java Talk localhost 40001
//
//   接続できなかったときは、第1回と同じ分け方で理由を出す。
//   ★ 入力は半角英数字にすること（日本語は端末の文字コードの影響を受ける）。
public class Talk {
  public static void main(String[] args) {
    if (args.length < 2) {
      System.out.println("使い方: java Talk <ホスト> <ポート番号>");
      return;
    }
    String host = args[0];
    int port = Integer.parseInt(args[1]);

    try (Socket s = new Socket()) {
      s.connect(new InetSocketAddress(host, port), 2000);   // 第1回と同じ形
      System.out.println("CONNECTED to " + s.getRemoteSocketAddress());

      BufferedReader in = new BufferedReader(
          new InputStreamReader(s.getInputStream(), StandardCharsets.UTF_8));
      BufferedWriter out = new BufferedWriter(
          new OutputStreamWriter(s.getOutputStream(), StandardCharsets.UTF_8));
      BufferedReader key = new BufferedReader(
          new InputStreamReader(System.in, StandardCharsets.UTF_8));

      String text;
      while ((text = key.readLine()) != null) {             // キーボードから1行
        out.write(text);
        out.write("\n");
        out.flush();
        String reply = in.readLine();                        // 返事を待つ
        if (reply == null) {
          System.out.println("CLOSED by server");            // サーバが線を切った
          return;
        }
        System.out.println("REPLY: " + reply);
      }
    } catch (UnknownHostException e) {
      System.out.println("UNKNOWN_HOST");
    } catch (ConnectException e) {
      System.out.println("REFUSED");
    } catch (SocketTimeoutException e) {
      System.out.println("TIMEOUT");
    } catch (IOException e) {
      System.out.println("ERROR " + e.getMessage());
    }
  }
}
