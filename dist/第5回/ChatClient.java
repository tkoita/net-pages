import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;

// 第4回・第5回：キーボードから打った行をサーバに送り、サーバから届いた行を「すぐ」表示するクライアント
//   第3回の Talk と同じ使い方。違いは、自分が打っていなくても届いた行を表示すること（第5回の演習C で使う）。
//
//   javac -encoding UTF-8 ChatClient.java
//   java ChatClient localhost 40001
//
//   ★ このクライアントも、スレッドを2本使っています。
//      main      ：キーボードから1行読んで、サーバへ送る（打つ係）
//      Thread-0  ：サーバから届いた行を、届いたそばから表示する（聞く係）
//     Talk は「送ったら返事を1行待つ」だったので、頼んでいない MSG を受け取れませんでした。
//   ★ 入力は半角英数字にすること（日本語は端末の文字コードの影響を受ける）。
//   終わるときは Ctrl + C。
public class ChatClient {
  public static void main(String[] args) {
    if (args.length < 2) {
      System.out.println("使い方: java ChatClient <ホスト> <ポート番号>");
      return;
    }
    String host = args[0];
    int port = Integer.parseInt(args[1]);

    try (Socket s = new Socket()) {
      s.connect(new InetSocketAddress(host, port), 2000);   // 第1回と同じ形
      System.out.println("CONNECTED to " + s.getRemoteSocketAddress());

      BufferedReader in = new BufferedReader(
          new InputStreamReader(s.getInputStream(), StandardCharsets.UTF_8));
      Writer out = new OutputStreamWriter(s.getOutputStream(), StandardCharsets.UTF_8);

      // 聞く係：届いた行を、届いたそばから表示する
      Thread listener = new Thread(() -> {
        try {
          String line;
          while ((line = in.readLine()) != null) {
            System.out.println("< " + line);
          }
          System.out.println("CLOSED by server");
        } catch (IOException e) {
          System.out.println("CLOSED " + e.getMessage());
        }
        System.exit(0);                    // サーバが閉じたら、打つ係も終わらせる
      });
      listener.setDaemon(true);
      listener.start();

      // 打つ係：キーボードから1行読んで送る
      BufferedReader key = new BufferedReader(
          new InputStreamReader(System.in, StandardCharsets.UTF_8));
      String text;
      while ((text = key.readLine()) != null) {
        out.write(text);
        out.write("\n");                   // 0x0A を1バイト
        out.flush();
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
