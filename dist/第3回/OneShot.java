import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;

// 第3回 演習A：1回だけ受け付けるサーバ
//   4つの動詞（bind / listen / accept / close）が1つずつ見えるように、
//   あえて try-with-resources を使わずに書いてある（演習Bで直す）。
//
//   javac -encoding UTF-8 OneShot.java
//   java OneShot 40001
public class OneShot {
  public static void main(String[] args) throws IOException {
    int port = Integer.parseInt(args[0]);

    ServerSocket server = new ServerSocket(port);      // ① bind + listen
    System.out.println("LISTENING port=" + port);

    Socket s = server.accept();                        // ② ここで止まる
    System.err.println("ACCEPTED " + s.getRemoteSocketAddress());

    BufferedReader in = new BufferedReader(
        new InputStreamReader(s.getInputStream(), StandardCharsets.UTF_8));
    BufferedWriter out = new BufferedWriter(
        new OutputStreamWriter(s.getOutputStream(), StandardCharsets.UTF_8));

    String line = in.readLine();                       // ③ 1行だけ読む
    System.err.println("RECEIVED " + line);
    out.write(line);
    out.write("\n");                                   // 改行は自分で1バイト
    out.flush();                                       // 第2回の教訓

    s.close();                                         // ④ この1本を閉じる
    server.close();                                    //    受付も閉じる
  }
}
