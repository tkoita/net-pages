# ============================================================================
#  check5.ps1  --  第5回 課題 ChatServer.java の自己採点
# ----------------------------------------------------------------------------
#  使い方（ChatServer.java と同じフォルダで）:
#
#      powershell -ExecutionPolicy Bypass -File check5.ps1
#
#  ・このスクリプトが、あなたの ChatServer を 40001 で起動し、接続して確かめ、
#    終わったら止めます。★ 自分で起動した ChatServer は、先に止めておくこと。
#  ・返事を 3 秒待っても来なければ、そのケースは FAIL にします。
#  ・問1（ケース1〜5）と問2（ケース6〜8）の 8 ケースです。
#    8 / 8 passed になってから提出してください。
#  ・ケース4（50本を同時に接続）は、中で3回くり返します。1回でも合わなければ FAIL です。
# ============================================================================
$ErrorActionPreference = "Continue"

$PORT    = 40001
$READ_MS = 3000
$STORM   = 50          # ケース4で同時につなぐ本数
$ROUNDS  = 3           # ケース4をくり返す回数
$SETTLE  = 400         # 切断をサーバが片付けるのを待つ時間（ミリ秒）

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
Say "=== 第5回 ChatServer.java 自己採点 ===" "Cyan"
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

if (-not (Test-Path -LiteralPath (Join-Path $HERE "ChatServer.java"))) {
    Say "ChatServer.java が、このスクリプトと同じフォルダにありません。" "Red"
    exit 1
}

$src = Get-Content -LiteralPath (Join-Path $HERE "ChatServer.java") -Raw -Encoding UTF8

if ($src -match '(?m)^\s*package\s+[\w\.]+\s*;') {
    Say "ChatServer.java の先頭に package 行があります。消してから実行してください。" "Red"
    Say "  （package があると、このフォルダで java ChatServer として起動できません）" "Red"
    exit 1
}

# ---------------------------------------------------------------------------
# 2. ソースの確認（点数には影響しません。警告だけ出します）
# ---------------------------------------------------------------------------
$code = [regex]::Replace($src, '(?s)/\*.*?\*/', '')
$code = [regex]::Replace($code, '//[^\r\n]*', '')
$warn = @()
if ($code -match 'Thread\.sleep\s*\(')                        { $warn += "Thread.sleep が残っています。演習B用の細工なので、消してください（ケース4が落ちる原因になります）" }
if ($code -match 'static\s+(volatile\s+)?(int|long)\s+\w+' -and $code -match '\w+\s*\+\+|\+\+\s*\w+' -and $code -notmatch 'Atomic(Integer|Long)' -and $code -notmatch 'synchronized') {
    $warn += "共有の数を int / long で ++ しているのに、AtomicInteger も synchronized も見当たりません（演習B）" }
if ($code -match 'new\s+ArrayList\s*<' -and $code -notmatch 'CopyOnWriteArrayList' -and $code -notmatch 'synchronized') {
    $warn += "ArrayList を守らずに使っている可能性があります。接続の一覧なら CopyOnWriteArrayList に（演習C）" }
if ($code -match 'Executors\.|ExecutorService')               { $warn += "スレッドプールを使っています。今回の課題は new Thread のまま提出します（スレッドプールは第10回）" }
if ($code -match '\.wait\s*\(\s*\)|\.notify(All)?\s*\(')      { $warn += "wait / notify があります。今回は使いません" }
if ($code -match 'printStackTrace\s*\(')                     { $warn += "printStackTrace() があります。スタックトレースは標準エラーにも出さないこと（ケース8）。e.getMessage() を1行で出してください" }
if ($code -match 'System\.exit\s*\(')                         { $warn += "System.exit() があります。クライアント1人のことで、サーバ全体を終了させないこと" }
if ($code -match 'newLine\s*\(')                              { $warn += "newLine() を使っています。Windows では 0D 0A の2バイトになります（0A だけを送ること）" }
if ($code -match 'new\s+PrintWriter\s*\(\s*\w+\.getOutputStream\s*\(\s*\)') { $warn += "PrintWriter(OutputStream) は文字コードを指定できません。OutputStreamWriter(..., UTF_8) を使ってください" }
if ($code -match 'new\s+InputStreamReader\s*\(\s*[^,()]+\([^()]*\)\s*\)') { $warn += "InputStreamReader に文字コードを渡していない可能性があります" }
foreach ($w in $warn) { Say ("警告: " + $w) "Yellow" }
if ($warn.Count -gt 0) { Say "" }

# ---------------------------------------------------------------------------
# 3. コンパイル
# ---------------------------------------------------------------------------
& javac -encoding UTF-8 ChatServer.java
if ($LASTEXITCODE -ne 0) {
    Say "COMPILE FAILED  javac -encoding UTF-8 ChatServer.java が通りません" "Red"
    exit 1
}

# ---------------------------------------------------------------------------
# 4. 40001 が空いているか（いちばん多い「全部 FAIL」の原因）
# ---------------------------------------------------------------------------
if (Test-Port $PORT) {
    Say "40001 番を、すでに別のプログラムが使っています。" "Red"
    Say "自分で起動した ChatServer（や ThreadedServer）が、まだ動いていませんか。" "Red"
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

function Case-Id {
    $bad = New-Object System.Collections.ArrayList
    $a = Open-Conn; $b = $null
    try {
        $ia = Ask-One $a "ID"
        $b = Open-Conn
        $ib = Ask-One $b "ID"
        if (-not (Is-Int $ia) -or -not (Is-Int $ib)) {
            [void]$bad.Add(("ID の返事が整数ではありません: 1本目=[{0}] 2本目=[{1}]" -f $ia, $ib))
        } elseif ([int]$ib -ne [int]$ia + 1) {
            [void]$bad.Add(("続けてつないだ2本の ID が 1 違いになっていません: 1本目=[{0}] 2本目=[{1}]（accept した順に通し番号）" -f $ia, $ib))
        }
        $again = Ask-One $a "ID"
        if ($again -cne $ia) { [void]$bad.Add(("同じ接続で ID を2回聞くと、違う番号が返りました: [{0}] → [{1}]" -f $ia, $again)) }
    } catch {
        [void]$bad.Add($_.Exception.Message)
    } finally {
        Close-Conn $a; if ($b) { Close-Conn $b }
    }
    return ,$bad
}

function Case-Count {
    $bad = New-Object System.Collections.ArrayList
    Start-Sleep -Milliseconds $SETTLE
    $ks = @()
    try {
        for ($i = 0; $i -lt 3; $i++) { $ks += ,(Open-Conn) }
        Start-Sleep -Milliseconds 200
        foreach ($k in $ks) {
            $c = Ask-One $k "COUNT"
            if ($c -cne "3") { [void]$bad.Add(("3本つないだ状態で COUNT: expected=[3] got=[{0}]" -f $c)); break }
        }
        if ($bad.Count -eq 0) {
            Close-Conn $ks[2]
            Start-Sleep -Milliseconds $SETTLE
            $c = Ask-One $ks[0] "COUNT"
            if ($c -cne "2") {
                [void]$bad.Add(("1本閉じたあとの COUNT: expected=[2] got=[{0}]" -f $c))
                if ($c -eq "3") { [void]$bad.Add("切断した接続を、一覧から外していません（finally で remove すること）") }
            }
        }
    } catch {
        [void]$bad.Add($_.Exception.Message)
    } finally {
        foreach ($k in $ks) { Close-Conn $k }
    }
    return ,$bad
}

function Storm-Once {
    $before = Ask-New "TOTAL"
    if (-not (Is-Int $before)) { throw ("TOTAL の返事が整数ではありません: [{0}]" -f $before) }
    $ks = New-Object System.Collections.ArrayList
    try {
        $ars = @()
        for ($i = 0; $i -lt $STORM; $i++) {
            $c = New-Object System.Net.Sockets.TcpClient
            $ars += ,@($c, $c.BeginConnect("127.0.0.1", $PORT, $null, $null))
        }
        foreach ($p in $ars) {
            if (-not $p[1].AsyncWaitHandle.WaitOne(3000)) { throw "同時接続の途中で、3 秒以内に接続できない接続がありました" }
            $p[0].EndConnect($p[1])
            $p[0].NoDelay = $true
            $s = $p[0].GetStream(); $s.ReadTimeout = $READ_MS
            [void]$ks.Add(@{ C = $p[0]; S = $s })
        }
        foreach ($k in $ks) { Send-Line $k "PING" }
        foreach ($k in $ks) {
            $m = Judge-Reply (Read-Reply $k) "PING" "PONG"
            if ($m) { throw ("同時に {0} 本つないだうちの1本で: {1}" -f $STORM, $m) }
        }
    } finally {
        foreach ($k in $ks) { Close-Conn $k }
    }
    $after = Ask-New "TOTAL"
    if (-not (Is-Int $after)) { throw ("TOTAL の返事が整数ではありません: [{0}]" -f $after) }
    return ([long]$after - [long]$before)
}

function Case-Total {
    $bad = New-Object System.Collections.ArrayList
    $want = $STORM + 1     # 50本 ＋ 最後に TOTAL を聞いた1本
    try {
        for ($r = 1; $r -le $ROUNDS; $r++) {
            $d = Storm-Once
            if ($d -ne $want) {
                [void]$bad.Add(("{0} 回目: {1} 本同時につないだのに、TOTAL は {2} しか増えていません（{3} 増えるはず）" -f $r, $STORM, ($d - 1), $STORM))
            }
        }
        if ($bad.Count -gt 0) {
            [void]$bad.Add("total を AtomicInteger にするか、synchronized で守ってください（演習B）。たまに合うのは、直った証拠ではありません")
        }
    } catch {
        [void]$bad.Add($_.Exception.Message)
    }
    return ,$bad
}

function Case-Misc {
    $bad = New-Object System.Collections.ArrayList
    try {
        foreach ($t in @("ping", "HELLO")) {
            $g = Ask-New $t
            if ($g -cne $ERRMSG) { [void]$bad.Add(("[{0}] への返事: expected=[{1}] got=[{2}]" -f $t, $ERRMSG, $g)) }
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

# A・B・C の順につなぎ、A の ID を聞いておく
function Open-Three {
    Start-Sleep -Milliseconds $SETTLE
    $a = Open-Conn; $b = Open-Conn; $c = Open-Conn
    Start-Sleep -Milliseconds 200
    $ia = Ask-One $a "ID"
    return @{ A = $a; B = $b; C = $c; IdA = $ia }
}

function Case-Say {
    $bad = New-Object System.Collections.ArrayList
    $t = $null
    try {
        $t = Open-Three
        $want = "MSG {0} hello world" -f $t.IdA
        $g = Ask-One $t.A "SAY hello world"
        if ($g -cne "OK") { [void]$bad.Add(("[SAY hello world] を送った本人への返事: expected=[OK] got=[{0}]" -f $g)) }
        foreach ($n in @("B", "C")) {
            $g = Wait-Line $t[$n] ("{0} に届くはずの MSG" -f $n)
            if ($g -cne $want) { [void]$bad.Add(("{0} に届いた行: expected=[{1}] got=[{2}]" -f $n, $want, $g)) }
        }
        $g = Ask-One $t.A "PING"
        if ($g -cne "PONG") {
            [void]$bad.Add(("SAY を送った本人が次に PING を送ると: expected=[PONG] got=[{0}]" -f $g))
            if ($g -like "MSG *") { [void]$bad.Add("送った本人にも MSG が届いています。broadcast で送り主を除くこと") }
        }
    } catch {
        [void]$bad.Add($_.Exception.Message)
    } finally {
        if ($t) { Close-Conn $t.A; Close-Conn $t.B; Close-Conn $t.C }
    }
    return ,$bad
}

function Case-Drop {
    $bad = New-Object System.Collections.ArrayList
    $t = $null
    try {
        $t = Open-Three
        # B だけ、いきなり強制切断（RST）する
        $t.B.C.Client.LingerState = New-Object System.Net.Sockets.LingerOption($true, 0)
        $t.B.C.Client.Close()
        Close-Conn $t.B
        Start-Sleep -Milliseconds $SETTLE
        $want = "MSG {0} again" -f $t.IdA
        $g = Ask-One $t.A "SAY again"
        if ($g -cne "OK") { [void]$bad.Add(("B を切ったあと、A の [SAY again] への返事: expected=[OK] got=[{0}]" -f $g)) }
        $g = Wait-Line $t.C "C に届くはずの MSG"
        if ($g -cne $want) { [void]$bad.Add(("C に届いた行: expected=[{0}] got=[{1}]" -f $want, $g)) }
        $g = Ask-One $t.A "COUNT"
        if ($g -cne "2") { [void]$bad.Add(("B を切ったあとの COUNT: expected=[2] got=[{0}]" -f $g)) }
    } catch {
        [void]$bad.Add($_.Exception.Message)
        [void]$bad.Add("1人が切れても、残りへの送信を止めないこと（broadcast の try-catch は for の内側に）")
    } finally {
        if ($t) { Close-Conn $t.A; Close-Conn $t.C }
    }
    return ,$bad
}

$cases = @(
    @{ q = 1; n = "ケース1  PING";                              f = { Ask-Lines @(, @("PING", "PONG")) } },
    @{ q = 1; n = "ケース2  ID は accept した順の通し番号";     f = { Case-Id } },
    @{ q = 1; n = "ケース3  COUNT が増えて、減る";              f = { Case-Count } },
    @{ q = 1; n = "ケース4  50本を同時につないでも TOTAL が合う（3回）"; f = { Case-Total } },
    @{ q = 1; n = "ケース5  QUIT と、知らないコマンド";         f = { Case-Misc } },
    @{ q = 2; n = "ケース6  SAY が他の全員に届く";              f = { Case-Say } },
    @{ q = 2; n = "ケース7  1人が強制切断しても、残りに届く";   f = { Case-Drop } }
)

# ---------------------------------------------------------------------------
# 7. ChatServer を起動して、順に確かめる
# ---------------------------------------------------------------------------
$tmp    = [System.IO.Path]::GetTempPath()
$srvOut = Join-Path $tmp ("check5_srv_out_{0}.txt" -f $PID)
$srvErr = Join-Path $tmp ("check5_srv_err_{0}.txt" -f $PID)
$srv = $null
$pass = 0
$total = $cases.Count + 1

try {
    Say ("ChatServer を {0} で起動します（終わったら止めます）。" -f $PORT)
    $srv = Start-Process -FilePath $JAVA -ArgumentList @("-Dstdout.encoding=UTF-8", "-Dstderr.encoding=UTF-8", "-cp", ".", "ChatServer", "$PORT") `
                         -WorkingDirectory $HERE -NoNewWindow -PassThru `
                         -RedirectStandardOutput $srvOut -RedirectStandardError $srvErr
    $ok = $false
    for ($i = 0; $i -lt 32; $i++) {
        Start-Sleep -Milliseconds 250
        if ($srv.HasExited) { break }
        if (Test-Port $PORT) { $ok = $true; break }
    }
    if (-not $ok) {
        Say "ChatServer が 40001 で待ち受けを始めませんでした。" "Red"
        if ($srv.HasExited) {
            Say "ChatServer がすぐに終了しています。標準エラーの先頭:" "Red"
            Start-Sleep -Milliseconds 200
            Get-Content $srvErr -Encoding UTF8 -TotalCount 6 -ErrorAction SilentlyContinue |
                ForEach-Object { Say ("  " + $_) "Red" }
        }
        exit 1
    }
    Start-Sleep -Milliseconds 300
    if ($srv.HasExited) {
        Say "接続して何も送らずに切断しただけで、ChatServer が終了しました。" "Red"
        Say "readLine() が null を返したときの処理を確認してください（null は切断の合図です）。" "Red"
        exit 1
    }
    Say ""

    $lastQ = 0
    foreach ($c in $cases) {
        if ($c.q -ne $lastQ) {
            if ($c.q -eq 1) { Say "--- 問1  同時につながっても、数が合う ---" "Cyan" }
            else            { Say "--- 問2  全員に配る。1人が切れても止まらない ---" "Cyan" }
            $lastQ = $c.q
        }
        $bad = $null
        try {
            $bad = & $c.f
        } catch {
            $bad = @("接続できませんでした。サーバが落ちていませんか（" + $_.Exception.Message + "）")
        }
        if ($srv.HasExited -and ($bad.Count -eq 0)) {
            $bad = @("このケースのあと、ChatServer が終了しました")
        }
        if ($bad.Count -eq 0) {
            Say ("PASS  {0}" -f $c.n) "Green"
            $pass++
        } else {
            Say ("FAIL  {0}" -f $c.n) "Red"
            foreach ($b in $bad) { Say ("        " + $b) "Red" }
        }
    }

    # ケース8：最後まで生きていて、標準出力は LISTENING の1行だけ
    $bad8 = New-Object System.Collections.ArrayList
    if ($srv.HasExited) {
        [void]$bad8.Add("ChatServer が途中で終了しています（最後まで待ち受けを続けること）")
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
    if ($e -match 'ConcurrentModificationException') {
        [void]$bad8.Add("標準エラーに ConcurrentModificationException が出ています。接続の一覧を CopyOnWriteArrayList に（演習C）")
    }
    if ($e -match '(?m)^\s+at\s') {
        [void]$bad8.Add("標準エラーにスタックトレースが出ています（例外を捕まえていない所があります）")
    }
    if ($bad8.Count -eq 0) {
        Say "PASS  ケース8  最後まで生きていて、標準出力は1行だけ" "Green"
        $pass++
    } else {
        Say "FAIL  ケース8  最後まで生きていて、標準出力は1行だけ" "Red"
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
    Say "提出前に、prompt_log.md の3件と、追加設問も確認してください。"
    exit 0
} else {
    Say ("{0} / {1} passed" -f $pass, $total) "Red"
    Say "赤い FAIL は故障ではありません。expected と got を見比べて、1つずつ直してください。"
    exit 1
}
