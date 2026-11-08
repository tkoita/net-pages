# ============================================================================
#  check4.ps1  --  第4回 課題 ThreadedServer.java と code_note.md の自己採点
# ----------------------------------------------------------------------------
#  使い方（ThreadedServer.java と code_note.md と同じフォルダで）:
#
#      powershell -ExecutionPolicy Bypass -File check4.ps1
#
#  ・このスクリプトが、あなたの ThreadedServer を 40001 で起動し、接続して確かめ、
#    終わったら止めます。★ 自分で起動した ThreadedServer は、先に止めておくこと。
#  ・返事を 3 秒待っても来なければ、そのケースは FAIL にします。
#  ・問1（ケース1〜5）と問2（ケース6）、共通（ケース7）の 7 ケースです。
#    7 / 7 passed になってから提出してください。
#  ・ケース6 は code_note.md が書いてあるかだけを見ます（中身は先生が読みます）。
# ============================================================================
$ErrorActionPreference = "Continue"

$PORT    = 40001
$READ_MS = 3000
$SETTLE  = 400         # 切断をサーバが片付けるのを待つ時間（ミリ秒）
$NOTE_MIN = 30         # code_note.md の各見出しの下に要る文字数

try { if ($env:OS -eq "Windows_NT") { chcp 65001 > $null } } catch {}
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$HERE = $PSScriptRoot
if ([string]::IsNullOrEmpty($HERE)) { $HERE = (Get-Location).Path }
Set-Location -LiteralPath $HERE

$UTF8 = New-Object System.Text.UTF8Encoding($false)

function Say([string]$msg, [string]$color) {
    if ($color) { Write-Host $msg -ForegroundColor $color } else { Write-Host $msg }
}

function Test-Port([int]$port) {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $c.BeginConnect("127.0.0.1", $port, $null, $null)
        $done = $ar.AsyncWaitHandle.WaitOne(500)
        if ($done -and $c.Connected) { return $true }
        return $false
    } catch {
        return $false
    } finally {
        $c.Close()
    }
}

Say ""
Say "=== 第4回 ThreadedServer.java 自己採点 ===" "Cyan"
Say ""

# ---------------------------------------------------------------------------
# 1. 必要なものがそろっているか
# ---------------------------------------------------------------------------
$javaCmd  = Get-Command java  -ErrorAction SilentlyContinue
$javacCmd = Get-Command javac -ErrorAction SilentlyContinue
if (-not $javaCmd -or -not $javacCmd) {
    Say "java / javac が見つかりません。java -version が通るか確認してください。" "Red"
    exit 1
}
$JAVA = $javaCmd.Path

if (-not (Test-Path -LiteralPath (Join-Path $HERE "ThreadedServer.java"))) {
    Say "ThreadedServer.java が、このスクリプトと同じフォルダにありません。" "Red"
    exit 1
}

$src = Get-Content -LiteralPath (Join-Path $HERE "ThreadedServer.java") -Raw -Encoding UTF8

if ($src -match '(?m)^\s*package\s+[\w\.]+\s*;') {
    Say "ThreadedServer.java の先頭に package 行があります。消してから実行してください。" "Red"
    Say "  （package があると、このフォルダで java ThreadedServer として起動できません）" "Red"
    exit 1
}

# ---------------------------------------------------------------------------
# 2. ソースの確認（点数には影響しません。警告だけ出します）
# ---------------------------------------------------------------------------
$code = [regex]::Replace($src, '(?s)/\*.*?\*/', '')
$code = [regex]::Replace($code, '//[^\r\n]*', '')
$warn = @()
if ($code -match 'try\s*\(\s*Socket\s+\w+\s*=\s*\w+\.accept\s*\(')  { $warn += "main で try (Socket s = server.accept()) を使っています。担当者が話す前に閉じてしまいます（演習C）" }
if ($code -notmatch 'new\s+Thread\b')                            { $warn += "new Thread が見つかりません。接続ごとにスレッドを作っていますか（演習A）" }
if ($code -match 'Executors\.|ExecutorService')                  { $warn += "スレッドプールを使っています。今回は new Thread で作ります（スレッドプールは第13回）" }
if ($code -match 'printStackTrace\s*\(')                        { $warn += "printStackTrace() があります。スタックトレースは標準エラーにも出さないこと（ケース7）。e.getMessage() を1行で出してください" }
if ($code -match 'System\.exit\s*\(')                            { $warn += "System.exit() があります。クライアント1人のことで、サーバ全体を終了させないこと" }
if ($code -match 'newLine\s*\(')                                 { $warn += "newLine() を使っています。Windows では 0D 0A の2バイトになります（0A だけを送ること）" }
if ($code -match 'new\s+PrintWriter\s*\(\s*\w+\.getOutputStream\s*\(\s*\)') { $warn += "PrintWriter(OutputStream) は文字コードを指定できません。OutputStreamWriter(..., UTF_8) を使ってください" }
if ($code -match 'new\s+InputStreamReader\s*\(\s*[^,()]+\([^()]*\)\s*\)') { $warn += "InputStreamReader に文字コードを渡していない可能性があります" }
foreach ($w in $warn) { Say ("警告: " + $w) "Yellow" }
if ($warn.Count -gt 0) { Say "" }

# ---------------------------------------------------------------------------
# 3. コンパイル
# ---------------------------------------------------------------------------
& javac -encoding UTF-8 ThreadedServer.java
if ($LASTEXITCODE -ne 0) {
    Say "COMPILE FAILED  javac -encoding UTF-8 ThreadedServer.java が通りません" "Red"
    exit 1
}

# ---------------------------------------------------------------------------
# 4. 40001 が空いているか（いちばん多い「全部 FAIL」の原因）
# ---------------------------------------------------------------------------
if (Test-Port $PORT) {
    Say "40001 番を、すでに別のプログラムが使っています。" "Red"
    Say "自分で起動した ThreadedServer（や LineServer）が、まだ動いていませんか。" "Red"
    Say "そのウィンドウで Ctrl + C を押すか、次の3行で止めてから、もう一度実行してください。" "Red"
    Say "  netstat -ano | findstr 40001" "Red"
    Say "  Get-Process -Id <いちばん右の数字>" "Red"
    Say "  Stop-Process -Id <いちばん右の数字>" "Red"
    exit 1
}

# ---------------------------------------------------------------------------
# 5. 接続して1行送り、1行受け取る道具（第3回の check3.ps1 と同じ）
# ---------------------------------------------------------------------------
function Open-Conn {
    $c = New-Object System.Net.Sockets.TcpClient
    $ar = $c.BeginConnect("127.0.0.1", $PORT, $null, $null)
    if (-not $ar.AsyncWaitHandle.WaitOne(2000)) {
        $c.Close()
        throw "2 秒以内に接続できませんでした"
    }
    $c.EndConnect($ar)
    $c.NoDelay = $true
    $s = $c.GetStream()
    $s.ReadTimeout = $READ_MS
    return @{ C = $c; S = $s }
}

function Close-Conn($k) {
    try { $k.C.Close() } catch {}
}

function Send-Raw($k, [byte[]]$bytes) {
    $k.S.Write($bytes, 0, $bytes.Length)
    $k.S.Flush()
}

function Send-Line($k, [string]$text) {
    Send-Raw $k ($UTF8.GetBytes($text + "`n"))
}

# 改行 0A まで読む。St は OK / EOF（相手が閉じた）/ TIMEOUT / RESET
function Read-Reply($k) {
    $ms = New-Object System.IO.MemoryStream
    try {
        while ($true) {
            $b = $k.S.ReadByte()
            if ($b -lt 0) { return @{ St = "EOF"; Bytes = $ms.ToArray() } }
            $ms.WriteByte([byte]$b)
            if ($b -eq 10) { return @{ St = "OK"; Bytes = $ms.ToArray() } }
        }
    } catch {
        $ex = $_.Exception
        while ($ex -and -not ($ex -is [System.Net.Sockets.SocketException])) { $ex = $ex.InnerException }
        if ($ex -and $ex.SocketErrorCode -eq [System.Net.Sockets.SocketError]::TimedOut) {
            return @{ St = "TIMEOUT"; Bytes = $ms.ToArray() }
        }
        return @{ St = "RESET"; Bytes = $ms.ToArray() }
    }
}

# 受け取った返事を、期待する1行と比べる。合っていれば $null、違えば理由を返す
function Judge-Reply($r, [string]$sent, [string]$want) {
    $b = $r.Bytes
    if ($r.St -eq "TIMEOUT") {
        if ($b.Length -gt 0) {
            return ("[{0}] への返事に改行 0A が付いていません（{1} 秒待ちました）" -f $sent, ($READ_MS / 1000))
        }
        return ("[{0}] への返事が {1} 秒待っても来ません。flush() を呼んでいるか確認してください" -f $sent, ($READ_MS / 1000))
    }
    if ($r.St -eq "RESET") {
        return ("[{0}] を送ったら、接続が切られました（サーバが落ちていませんか）" -f $sent)
    }
    if ($r.St -eq "EOF") {
        if ($b.Length -eq 0) {
            return ("[{0}] への返事の前に、サーバが接続を閉じました" -f $sent)
        }
        return ("[{0}] への返事に改行 0A が付かないまま、接続が閉じられました" -f $sent)
    }
    $n = $b.Length - 1
    if ($n -ge 1 -and $b[$n - 1] -eq 13) {
        return ("[{0}] への返事の改行が 0D 0A（2バイト）です。newLine() ではなく write(""\n"") を使ってください" -f $sent)
    }
    $got = $UTF8.GetString($b, 0, $n)
    if ($got -cne $want) {
        return ("[{0}] への返事: expected=[{1}] got=[{2}]" -f $sent, $want, $got)
    }
    return $null
}

# 1本の接続で、行を順に送って、それぞれの返事を確かめる
function Ask-Lines($pairs) {
    $bad = New-Object System.Collections.ArrayList
    $k = Open-Conn
    try {
        foreach ($p in $pairs) {
            try {
                Send-Line $k $p[0]
            } catch {
                [void]$bad.Add(("[{0}] を送れませんでした。サーバがこの接続を閉じています" -f $p[0]))
                break
            }
            $m = Judge-Reply (Read-Reply $k) $p[0] $p[1]
            if ($m) { [void]$bad.Add($m); break }
        }
    } finally {
        Close-Conn $k
    }
    return ,$bad
}


# 1本の接続で1行送り、返事を1行受け取って文字列で返す。だめなら例外を投げる
function Ask-One($k, [string]$line) {
    Send-Line $k $line
    $r = Read-Reply $k
    if ($r.St -ne "OK") {
        $m = Judge-Reply $r $line ""
        throw $m
    }
    $b = $r.Bytes
    $n = $b.Length - 1
    if ($n -ge 1 -and $b[$n - 1] -eq 13) {
        throw ("[{0}] への返事の改行が 0D 0A（2バイト）です。newLine() ではなく write(""\n"") を使ってください" -f $line)
    }
    return $UTF8.GetString($b, 0, $n)
}

# 新しく1本つないで1行だけ聞く
function Ask-New([string]$line) {
    $k = Open-Conn
    try { return (Ask-One $k $line) } finally { Close-Conn $k }
}

function Is-Int([string]$s) { return ($s -match '^\d+$') }

# 相手が送ってくる1行を待つ（自分からは送らない）
function Wait-Line($k, [string]$what) {
    $r = Read-Reply $k
    if ($r.St -eq "TIMEOUT") { throw ("{0} が {1} 秒待っても届きません" -f $what, ($READ_MS / 1000)) }
    if ($r.St -ne "OK") { throw ("{0} を待っている間に、接続が閉じられました" -f $what) }
    $b = $r.Bytes
    return $UTF8.GetString($b, 0, $b.Length - 1)
}

# ---------------------------------------------------------------------------
# 6. ケース
# ---------------------------------------------------------------------------
$ERRMSG = "ERR unknown command"

# 1本目をつないだまま黙らせ、2本目・3本目にすぐ答えるか
function Case-Silent {
    $bad = New-Object System.Collections.ArrayList
    $a = $null; $b = $null; $c = $null
    try {
        $a = Open-Conn
        Start-Sleep -Milliseconds 200
        foreach ($n in @("2", "3")) {
            $k = Open-Conn
            if ($n -eq "2") { $b = $k } else { $c = $k }
            Send-Line $k "PING"
            $r = Read-Reply $k
            if ($r.St -eq "TIMEOUT") {
                [void]$bad.Add(("1本目をつないだまま、{0}本目の [PING] への返事が {1} 秒待っても来ません" -f $n, ($READ_MS / 1000)))
                [void]$bad.Add("1人目と話しているあいだ、次の accept() に戻れていません。接続ごとに new Thread(...).start() しているか確かめてください")
                break
            }
            $m = Judge-Reply $r "PING" "PONG"
            if ($m) { [void]$bad.Add(("{0}本目: {1}" -f $n, $m)); break }
        }
        if ($bad.Count -eq 0) {
            $g = Ask-One $a "PING"
            if ($g -cne "PONG") { [void]$bad.Add(("黙っていた1本目が、あとで PING を送ると: expected=[PONG] got=[{0}]" -f $g)) }
        }
    } catch {
        [void]$bad.Add($_.Exception.Message)
    } finally {
        foreach ($k in @($a, $b, $c)) { if ($k) { Close-Conn $k } }
    }
    return ,$bad
}

# 3本を開けたまま、3本目 → 2本目 → 1本目の順に PING
function Case-Reverse {
    $bad = New-Object System.Collections.ArrayList
    $ks = @()
    try {
        for ($i = 0; $i -lt 3; $i++) { $ks += ,(Open-Conn) }
        Start-Sleep -Milliseconds 200
        foreach ($i in @(2, 1, 0)) {
            Send-Line $ks[$i] "PING"
            $r = Read-Reply $ks[$i]
            if ($r.St -eq "TIMEOUT" -and $r.Bytes.Length -eq 0) {
                [void]$bad.Add(("3本を開けたまま、{0}本目の [PING] への返事が {1} 秒待っても来ません" -f ($i + 1), ($READ_MS / 1000)))
                [void]$bad.Add("先につないだ人と話しているあいだ、次の accept() に戻れていません。接続ごとに new Thread(...).start() しているか確かめてください")
                break
            }
            $m = Judge-Reply $r "PING" "PONG"
            if ($m) { [void]$bad.Add(("{0}本目: {1}" -f ($i + 1), $m)); break }
        }
    } catch {
        [void]$bad.Add($_.Exception.Message)
    } finally {
        foreach ($k in $ks) { Close-Conn $k }
    }
    return ,$bad
}

function Case-Misc {
    $bad = New-Object System.Collections.ArrayList
    try {
        foreach ($p in @(@("ECHO a", "a"), @("LEN こんにちは", "15"), @("ping", $ERRMSG))) {
            $g = Ask-New $p[0]
            if ($g -cne $p[1]) { [void]$bad.Add(("[{0}] への返事: expected=[{1}] got=[{2}]（第3回と同じに答えること）" -f $p[0], $p[1], $g)) }
        }
        $k = Open-Conn
        try {
            $g = Ask-One $k "QUIT"
            if ($g -cne "BYE") { [void]$bad.Add(("[QUIT] への返事: expected=[BYE] got=[{0}]" -f $g)) }
            elseif ((Read-Reply $k).St -ne "EOF") { [void]$bad.Add("BYE を返したあと、その接続を閉じていません") }
        } finally { Close-Conn $k }
        Start-Sleep -Milliseconds 300
        $g = Ask-New "PING"
        if ($g -cne "PONG") { [void]$bad.Add(("QUIT のあと接続し直して PING: expected=[PONG] got=[{0}]" -f $g)) }
    } catch {
        [void]$bad.Add($_.Exception.Message)
        [void]$bad.Add("QUIT で閉じるのは、その接続1本だけです（サーバは待ち受けを続ける）")
    }
    return ,$bad
}

function Case-Rude {
    $bad = New-Object System.Collections.ArrayList
    $step = ""
    try {
        $step = "何も送らずに切断する"
        $k = Open-Conn; Close-Conn $k

        $step = "改行なしで「PI」だけ送って切断する"
        $k = Open-Conn; Send-Raw $k ($UTF8.GetBytes("PI")); Close-Conn $k

        $step = "PING を送り、返事を読まずに切断する"
        $k = Open-Conn; Send-Line $k "PING"; Close-Conn $k

        $step = "いきなり強制切断（RST）する"
        $k = Open-Conn
        # TcpClient.Close() だと先に FIN が出てしまうので、ソケットを直接閉じて RST だけを送る
        $k.C.Client.LingerState = New-Object System.Net.Sockets.LingerOption($true, 0)
        $k.C.Client.Close()
        Close-Conn $k

        Start-Sleep -Milliseconds 500
        $step = "そのあと、普通に PING を送る"
        $more = Ask-Lines @(, @("PING", "PONG"))
        foreach ($m in $more) { [void]$bad.Add("乱暴な切断のあと: " + $m) }
    } catch {
        [void]$bad.Add(("「{0}」のところで、接続できなくなりました。サーバが落ちていませんか" -f $step))
        [void]$bad.Add("catch (IOException e) が while (true) の内側にあるか確認してください")
    }
    return ,$bad
}

# code_note.md：2つの見出しと、それぞれの下の文字数、決まった語
function Case-Note {
    $bad = New-Object System.Collections.ArrayList
    $path = Join-Path $HERE "code_note.md"
    if (-not (Test-Path -LiteralPath $path)) {
        [void]$bad.Add("code_note.md が、このスクリプトと同じフォルダにありません（問2）")
        return ,$bad
    }
    $t = (Get-Content -LiteralPath $path -Raw -Encoding UTF8) -replace "`r`n", "`n"
    $heads = @(
        @{ h = "## 1 accept の行"; must = "main" },
        @{ h = "## 2 new Thread の行"; must = "main" }
    )
    $pos = @()
    foreach ($x in $heads) {
        $i = $t.IndexOf($x.h)
        if ($i -lt 0) { [void]$bad.Add(("見出し「{0}」がありません。資料の問2 の2つの見出しを、そのまま使ってください" -f $x.h)) }
        $pos += $i
    }
    if ($bad.Count -gt 0) { return ,$bad }
    for ($j = 0; $j -lt $heads.Count; $j++) {
        $from = $pos[$j] + $heads[$j].h.Length
        $to = $t.Length
        if ($j -lt $heads.Count - 1) { $to = $pos[$j + 1] }
        if ($to -lt $from) { [void]$bad.Add("2つの見出しは、1 → 2 の順に並べてください"); break }
        $body = $t.Substring($from, $to - $from)
        $chars = ($body -replace '\s', '').Length
        if ($chars -lt $NOTE_MIN) {
            [void]$bad.Add(("「{0}」の下が {1} 文字です（{2} 文字以上。1〜2文で書く）" -f $heads[$j].h, $chars, $NOTE_MIN))
        }
        if ($body -notmatch [regex]::Escape($heads[$j].must)) {
            [void]$bad.Add(("「{0}」の下に「{1}」の語がありません（どのスレッドが実行するかを書く）" -f $heads[$j].h, $heads[$j].must))
        }
    }
    return ,$bad
}

$cases = @(
    @{ q = 1; n = "ケース1  PING";                                       f = { Ask-Lines @(, @("PING", "PONG")) } },
    @{ q = 1; n = "ケース2  1本目が黙っていても、2本目・3本目にすぐ答える"; f = { Case-Silent } },
    @{ q = 1; n = "ケース3  3本を開けたまま、逆の順に答える";             f = { Case-Reverse } },
    @{ q = 1; n = "ケース4  第3回のコマンドと QUIT";                      f = { Case-Misc } },
    @{ q = 1; n = "ケース5  乱暴な切断に耐える";                          f = { Case-Rude } },
    @{ q = 2; n = "ケース6  code_note.md に2か所を書いた";                f = { Case-Note } }
)

# ---------------------------------------------------------------------------
# 7. ThreadedServer を起動して、順に確かめる
# ---------------------------------------------------------------------------
$tmp    = [System.IO.Path]::GetTempPath()
$srvOut = Join-Path $tmp ("check4_srv_out_{0}.txt" -f $PID)
$srvErr = Join-Path $tmp ("check4_srv_err_{0}.txt" -f $PID)
$srv = $null
$pass = 0
$total = $cases.Count + 1

try {
    Say ("ThreadedServer を {0} で起動します（終わったら止めます）。" -f $PORT)
    $srv = Start-Process -FilePath $JAVA -ArgumentList @("-Dstdout.encoding=UTF-8", "-Dstderr.encoding=UTF-8", "-cp", ".", "ThreadedServer", "$PORT") `
                         -WorkingDirectory $HERE -NoNewWindow -PassThru `
                         -RedirectStandardOutput $srvOut -RedirectStandardError $srvErr
    $ok = $false
    for ($i = 0; $i -lt 32; $i++) {
        Start-Sleep -Milliseconds 250
        if ($srv.HasExited) { break }
        if (Test-Port $PORT) { $ok = $true; break }
    }
    if (-not $ok) {
        Say "ThreadedServer が 40001 で待ち受けを始めませんでした。" "Red"
        if ($srv.HasExited) {
            Say "ThreadedServer がすぐに終了しています。標準エラーの先頭:" "Red"
            Start-Sleep -Milliseconds 200
            Get-Content $srvErr -Encoding UTF8 -TotalCount 6 -ErrorAction SilentlyContinue |
                ForEach-Object { Say ("  " + $_) "Red" }
        }
        exit 1
    }
    Start-Sleep -Milliseconds 300
    if ($srv.HasExited) {
        Say "接続して何も送らずに切断しただけで、ThreadedServer が終了しました。" "Red"
        Say "readLine() が null を返したときの処理を確認してください（null は切断の合図です）。" "Red"
        exit 1
    }
    Say ""

    $lastQ = 0
    foreach ($c in $cases) {
        if ($c.q -ne $lastQ) {
            if ($c.q -eq 1) { Say "--- 問1  何人同時につながっても待たせない ---" "Cyan" }
            else            { Say "--- 問2  code_note.md ---" "Cyan" }
            $lastQ = $c.q
        }
        $bad = $null
        try {
            $bad = & $c.f
        } catch {
            $bad = @("接続できませんでした。サーバが落ちていませんか（" + $_.Exception.Message + "）")
        }
        if ($srv.HasExited -and ($bad.Count -eq 0)) {
            $bad = @("このケースのあと、ThreadedServer が終了しました")
        }
        if ($bad.Count -eq 0) {
            Say ("PASS  {0}" -f $c.n) "Green"
            $pass++
        } else {
            Say ("FAIL  {0}" -f $c.n) "Red"
            foreach ($b in $bad) { Say ("        " + $b) "Red" }
        }
    }

    # ケース7：最後まで生きていて、標準出力は LISTENING の1行だけ
    Say "--- 共通 ---" "Cyan"
    $bad8 = New-Object System.Collections.ArrayList
    if ($srv.HasExited) {
        [void]$bad8.Add("ThreadedServer が途中で終了しています（最後まで待ち受けを続けること）")
    }
    try { Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue } catch {}
    try { $srv.WaitForExit(3000) | Out-Null } catch {}
    Start-Sleep -Milliseconds 300

    $o = ""
    if (Test-Path $srvOut) { $o = [System.IO.File]::ReadAllText($srvOut) }
    $o = $o -replace "`r`n", "`n"
    if ($o.EndsWith("`n")) { $o = $o.Substring(0, $o.Length - 1) }
    $lines = @()
    if ($o.Length -gt 0) { $lines = $o.Split("`n") }
    $want = "LISTENING port=$PORT"
    if ($lines.Count -eq 0) {
        [void]$bad8.Add("標準出力に何も出ていません（expected=[$want]）")
    } elseif ($lines[0] -cne $want) {
        [void]$bad8.Add(("標準出力の1行目: expected=[{0}] got=[{1}]" -f $want, $lines[0]))
    }
    if ($lines.Count -gt 1) {
        [void]$bad8.Add(("標準出力が {0} 行あります。LISTENING の1行だけにして、ログは System.err へ" -f $lines.Count))
        [void]$bad8.Add("  2行目: " + $lines[1])
    }
    $e = ""
    if (Test-Path $srvErr) { $e = [System.IO.File]::ReadAllText($srvErr) }
    if ($e -match '(?m)^\s+at\s') {
        [void]$bad8.Add("標準エラーにスタックトレースが出ています（例外を捕まえていない所があります）")
    }
    if ($bad8.Count -eq 0) {
        Say "PASS  ケース7  最後まで生きていて、標準出力は1行だけ" "Green"
        $pass++
    } else {
        Say "FAIL  ケース7  最後まで生きていて、標準出力は1行だけ" "Red"
        foreach ($b in $bad8) { Say ("        " + $b) "Red" }
    }
} finally {
    if ($srv -and -not $srv.HasExited) {
        try { Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue } catch {}
        Start-Sleep -Milliseconds 300
    }
    Remove-Item $srvOut, $srvErr -ErrorAction SilentlyContinue
}

Say ""
if ($pass -eq $total) {
    Say ("{0} / {1} passed" -f $pass, $total) "Green"
    Say "提出前に、prompt_log.md の1件と、code_note.md が自分の言葉で書けているかも確認してください。"
    exit 0
} else {
    Say ("{0} / {1} passed" -f $pass, $total) "Red"
    Say "赤い FAIL は故障ではありません。FAIL の下の説明（expected と got が出ていれば、その2つ）を見て、1つずつ直してください。"
    exit 1
}
