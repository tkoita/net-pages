import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;

// 第5回：サーバに、たくさんの接続を同時に送り込むクライアント（演習B・中間レポート 課題1）
//   1. まず1本つないで TOTAL を聞く（いまの累計）
//   2. N 本（ふつうは 50）を一斉につなぎ、それぞれ PING を送って PONG を待つ
//   3. 最後に1本つないで、もう一度 TOTAL を聞く
//   → サーバの total が「N 増えたか」を表示する。これを R 回くり返す。
//
//   javac -encoding UTF-8 Storm.java
//   java Storm 50        （50本を1回）
//   java Storm 50 5      （50本を5回くり返す。中間レポートの測定はこちら）
//
//   ★ サーバに TOTAL コマンド（起動以来の累計接続数を返す）が必要です（演習A）。
//   ★ サーバを起動し直さなくても、何回でもくり返せます（差だけを見ているため）。
//   ★ 1本目と3本目の TOTAL を聞く接続も、サーバは1本と数えます。だから
//      「増えた数」は (後の TOTAL) − (前の TOTAL) − 1 で計算しています。
public class Storm {
  static final int PORT = 40001;

  public static void main(String[] args) throws Exception {
    int n = (args.length > 0) ? Integer.parseInt(args[0]) : 50;
    int rounds = (args.length > 1) ? Integer.parseInt(args[1]) : 1;

    int bad = 0;
    for (int k = 1; k <= rounds; k++) {
      if (rounds > 1) System.out.println("---- " + k + " 回目 ----");
      int r = once(n);
      if (r < 0) return;                 // サーバにつながらない・TOTAL がない
      if (r > 0) bad++;
    }
    if (rounds > 1) {
      System.out.println("==== " + rounds + " 回のうち、合わなかったのは " + bad + " 回 ====");
    }
    System.out.println("CPU のコア数   " + Runtime.getRuntime().availableProcessors());
  }

  // 1回ぶん。戻り値は「減った数」（合っていれば 0、つながらなければ -1）
  static int once(int n) throws InterruptedException {
    long before = askTotal();
    if (before < 0) return -1;

    Thread[] ts = new Thread[n];
    int[] ng = new int[1];
    for (int i = 0; i < n; i++) {
      ts[i] = new Thread(() -> {
        try (Socket s = new Socket("localhost", PORT)) {
          Writer out = new OutputStreamWriter(s.getOutputStream(), StandardCharsets.UTF_8);
          BufferedReader in = new BufferedReader(
              new InputStreamReader(s.getInputStream(), StandardCharsets.UTF_8));
          out.write("PING\n");
          out.flush();
          in.readLine();
        } catch (IOException e) {
          synchronized (ng) { ng[0]++; }
          System.err.println("NG " + e.getMessage());
        }
      });
    }
    for (Thread t : ts) t.start();     // 一斉にスタート
    for (Thread t : ts) t.join();      // 全部終わるまで待つ

    long after = askTotal();
    if (after < 0) return -1;
    long grew = after - before - 1;
    long want = n - ng[0];

    System.out.println("つないだ本数   " + n + "（失敗 " + ng[0] + "）");
    System.out.println("total の増え方 " + grew + "（" + want + " 増えるはず）");
    System.out.println(grew == want ? "→ 合っている" : "→ ★ 合っていない（" + (want - grew) + " 減った）");
    return (int) Math.max(0, want - grew);
  }

  // 1本つないで TOTAL を聞く。答えが数でなければ -1
  static long askTotal() {
    try (Socket s = new Socket("localhost", PORT)) {
      Writer out = new OutputStreamWriter(s.getOutputStream(), StandardCharsets.UTF_8);
      BufferedReader in = new BufferedReader(
          new InputStreamReader(s.getInputStream(), StandardCharsets.UTF_8));
      out.write("TOTAL\n");
      out.flush();
      String r = in.readLine();
      try {
        return Long.parseLong(r.trim());
      } catch (RuntimeException e) {
        System.out.println("TOTAL の返事が数ではありません: [" + r + "]");
        System.out.println("サーバに TOTAL の1行を足してください（演習A の A-1 ③）");
        return -1;
      }
    } catch (ConnectException e) {
      System.out.println("REFUSED  サーバが 40001 で待っていません。先にサーバを起動してください");
      return -1;
    } catch (IOException e) {
      System.out.println("ERROR " + e.getMessage());
      return -1;
    }
  }
}
