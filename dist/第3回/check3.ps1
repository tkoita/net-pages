# ============================================================================
#  check3.ps1  --  第3回 課題 LineServer.java の自己採点
# ----------------------------------------------------------------------------
#  使い方（LineServer.java と同じフォルダで）:
#
#      powershell -ExecutionPolicy Bypass -File check3.ps1
#
#  ・このスクリプトが、あなたの LineServer を 40001 で起動し、接続して確かめ、
#    終わったら止めます。★ 自分で起動した LineServer は、先に止めておくこと。
#  ・返事を 3 秒待っても来なければ、そのケースは FAIL にします。
#  ・問1（ケース1〜5）と問2（ケース6〜9）の 9 ケースです。
#    9 / 9 passed になってから提出してください。
# ============================================================================
$ErrorActionPreference = "Continue"

$PORT    = 40001
$READ_MS = 3000

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
Say "=== 第3回 LineServer.java 自己採点 ===" "Cyan"
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

if (-not (Test-Path -LiteralPath (Join-Path $HERE "LineServer.java"))) {
    Say "LineServer.java が、このスクリプトと同じフォルダにありません。" "Red"
    exit 1
}

$src = Get-Content -LiteralPath (Join-Path $HERE "LineServer.java") -Raw -Encoding UTF8

if ($src -match '(?m)^\s*package\s+[\w\.]+\s*;') {
    Say "LineServer.java の先頭に package 行があります。消してから実行してください。" "Red"
    Say "  （package があると、このフォルダで java LineServer として起動できません）" "Red"
    exit 1
}

# ---------------------------------------------------------------------------
# 2. ソースの確認（点数には影響しません。警告だけ出します）
# ---------------------------------------------------------------------------
$code = [regex]::Replace($src, '(?s)/\*.*?\*/', '')
$code = [regex]::Replace($code, '//[^\r\n]*', '')
$warn = @()
if ($code -match 'new\s+Thread\b|ExecutorService|Executors\.') { $warn += "スレッドを使っています。今回は使いません（第4回の内容です）" }
if ($code -match 'printStackTrace\s*\(')                     { $warn += "printStackTrace() があります。スタックトレースは標準エラーにも出さないこと（ケース9）。e.getMessage() を1行で出してください" }
if ($code -match 'System\.exit\s*\(')                         { $warn += "System.exit() があります。クライアント1人のことで、サーバ全体を終了させないこと" }
if ($code -match 'newLine\s*\(')                              { $warn += "newLine() を使っています。Windows では 0D 0A の2バイトになります（0A だけを送ること）" }
if ($code -match 'new\s+PrintWriter\s*\(\s*\w+\.getOutputStream\s*\(\s*\)') { $warn += "PrintWriter(OutputStream) は文字コードを指定できません。OutputStreamWriter(..., UTF_8) を使ってください" }
if ($code -match 'getBytes\s*\(\s*\)')                        { $warn += "getBytes() に文字コードを渡していません" }
if ($code -match 'new\s+InputStreamReader\s*\(\s*[^,()]+\([^()]*\)\s*\)') { $warn += "InputStreamReader に文字コードを渡していない可能性があります" }
foreach ($w in $warn) { Say ("警告: " + $w) "Yellow" }
if ($warn.Count -gt 0) { Say "" }

# ---------------------------------------------------------------------------
# 3. コンパイル
# ---------------------------------------------------------------------------
& javac -encoding UTF-8 LineServer.java
if ($LASTEXITCODE -ne 0) {
    Say "COMPILE FAILED  javac -encoding UTF-8 LineServer.java が通りません" "Red"
    exit 1
}

# ---------------------------------------------------------------------------
# 4. 40001 が空いているか（いちばん多い「全部 FAIL」の原因）
# ---------------------------------------------------------------------------
if (Test-Port $PORT) {
    Say "40001 番を、すでに別のプログラムが使っています。" "Red"
    Say "自分で起動した LineServer（や LoopServer）が、まだ動いていませんか。" "Red"
    Say "そのウィンドウで Ctrl + C を押すか、次の3行で止めてから、もう一度実行してください。" "Red"
    Say "  netstat -ano | findstr 40001" "Red"
    Say "  Get-Process -Id <いちばん右の数字>" "Red"
    Say "  Stop-Process -Id <いちばん右の数字>" "Red"
    exit 1
}

# ---------------------------------------------------------------------------
# 5. 接続して1行送り、1行受け取る道具
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

# ---------------------------------------------------------------------------
# 6. ケース
# ---------------------------------------------------------------------------
$ERRMSG = "ERR unknown command"

function Case-Loop {
    $pairs = @(@("PING", "PONG"), @("ECHO a", "a"), @("LEN abc", "3"))
    $bad = Ask-Lines $pairs
    if (($bad -join " ") -match "閉じ|切られ") {
        [void]$bad.Add("1本の接続で、2行目以降も読み続けること（readLine() を while で回す）")
    }
    return ,$bad
}

function Case-Quit {
    $bad = New-Object System.Collections.ArrayList
    $k = Open-Conn
    try {
        Send-Line $k "QUIT"
        $m = Judge-Reply (Read-Reply $k) "QUIT" "BYE"
        if ($m) { [void]$bad.Add($m) }
        else {
            $r = Read-Reply $k
            if ($r.St -ne "EOF") {
                [void]$bad.Add("BYE を返したあと、接続を閉じていません（その接続だけを閉じること）")
            }
        }
    } finally {
        Close-Conn $k
    }
    if ($bad.Count -gt 0) { return ,$bad }
    Start-Sleep -Milliseconds 300
    try {
        $more = Ask-Lines @(, @("PING", "PONG"))
        foreach ($m in $more) { [void]$bad.Add("QUIT のあと接続し直すと: " + $m) }
    } catch {
        [void]$bad.Add("QUIT のあと、接続し直せません。サーバごと終了していませんか（server.close() / System.exit()）")
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

$cases = @(
    @{ q = 1; n = "ケース1  PING";                   f = { Ask-Lines @(, @("PING", "PONG")) } },
    @{ q = 1; n = "ケース2  ECHO hello world";       f = { Ask-Lines @(, @("ECHO hello world", "hello world")) } },
    @{ q = 1; n = "ケース3  ECHO のスペースを残す";  f = { Ask-Lines @(, @("ECHO  a  b ", " a  b ")) } },
    @{ q = 1; n = "ケース4  LEN こんにちは";         f = { Ask-Lines @(, @("LEN こんにちは", "15")) } },
    @{ q = 1; n = "ケース5  知らないコマンド";       f = {
            $b = New-Object System.Collections.ArrayList
            foreach ($t in @("ping", "HELLO", "ECHO")) {
                foreach ($m in (Ask-Lines @(, @($t, $ERRMSG)))) { [void]$b.Add($m) }
            }
            return ,$b } },
    @{ q = 2; n = "ケース6  1本の接続で3行";         f = { Case-Loop } },
    @{ q = 2; n = "ケース7  QUIT で閉じるのは1本だけ"; f = { Case-Quit } },
    @{ q = 2; n = "ケース8  乱暴な切断に耐える";     f = { Case-Rude } }
)

# ---------------------------------------------------------------------------
# 7. LineServer を起動して、順に確かめる
# ---------------------------------------------------------------------------
$tmp    = [System.IO.Path]::GetTempPath()
$srvOut = Join-Path $tmp ("check3_srv_out_{0}.txt" -f $PID)
$srvErr = Join-Path $tmp ("check3_srv_err_{0}.txt" -f $PID)
$srv = $null
$pass = 0
$total = $cases.Count + 1

try {
    Say ("LineServer を {0} で起動します（終わったら止めます）。" -f $PORT)
    $srv = Start-Process -FilePath $JAVA -ArgumentList @("-Dstdout.encoding=UTF-8", "-Dstderr.encoding=UTF-8", "-cp", ".", "LineServer", "$PORT") `
                         -WorkingDirectory $HERE -NoNewWindow -PassThru `
                         -RedirectStandardOutput $srvOut -RedirectStandardError $srvErr
    $ok = $false
    for ($i = 0; $i -lt 32; $i++) {
        Start-Sleep -Milliseconds 250
        if ($srv.HasExited) { break }
        if (Test-Port $PORT) { $ok = $true; break }
    }
    if (-not $ok) {
        Say "LineServer が 40001 で待ち受けを始めませんでした。" "Red"
        if ($srv.HasExited) {
            Say "LineServer がすぐに終了しています。標準エラーの先頭:" "Red"
            Start-Sleep -Milliseconds 200
            Get-Content $srvErr -Encoding UTF8 -TotalCount 6 -ErrorAction SilentlyContinue |
                ForEach-Object { Say ("  " + $_) "Red" }
        }
        exit 1
    }
    # 待ち受けの確認で「つないで何も送らずに切る」を1回しているので、それで落ちていないか
    Start-Sleep -Milliseconds 300
    if ($srv.HasExited) {
        Say "接続して何も送らずに切断しただけで、LineServer が終了しました。" "Red"
        Say "readLine() が null を返したときの処理を確認してください（null は切断の合図です）。" "Red"
        exit 1
    }
    Say ""

    $lastQ = 0
    foreach ($c in $cases) {
        if ($c.q -ne $lastQ) {
            if ($c.q -eq 1) { Say "--- 問1  コマンドに答える ---" "Cyan" }
            else            { Say "--- 問2  何をされても、サーバは死なない ---" "Cyan" }
            $lastQ = $c.q
        }
        $bad = $null
        try {
            $bad = & $c.f
        } catch {
            $bad = @("接続できませんでした。サーバが落ちていませんか（" + $_.Exception.Message + "）")
        }
        if ($srv.HasExited -and ($bad.Count -eq 0)) {
            $bad = @("このケースのあと、LineServer が終了しました")
        }
        if ($bad.Count -eq 0) {
            Say ("PASS  {0}" -f $c.n) "Green"
            $pass++
        } else {
            Say ("FAIL  {0}" -f $c.n) "Red"
            foreach ($b in $bad) { Say ("        " + $b) "Red" }
        }
    }

    # ケース9：最後まで生きていて、標準出力は LISTENING の1行だけ
    $bad9 = New-Object System.Collections.ArrayList
    if ($srv.HasExited) {
        [void]$bad9.Add("LineServer が途中で終了しています（最後まで待ち受けを続けること）")
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
        [void]$bad9.Add("標準出力に何も出ていません（expected=[$want]）")
    } elseif ($lines[0] -cne $want) {
        [void]$bad9.Add(("標準出力の1行目: expected=[{0}] got=[{1}]" -f $want, $lines[0]))
    }
    if ($lines.Count -gt 1) {
        [void]$bad9.Add(("標準出力が {0} 行あります。LISTENING の1行だけにして、ログは System.err へ" -f $lines.Count))
        [void]$bad9.Add("  2行目: " + $lines[1])
    }
    $e = ""
    if (Test-Path $srvErr) { $e = [System.IO.File]::ReadAllText($srvErr) }
    if ($e -match '(?m)^\s+at\s') {
        [void]$bad9.Add("標準エラーにスタックトレースが出ています（例外を捕まえていない所があります）")
    }
    if ($bad9.Count -eq 0) {
        Say "PASS  ケース9  最後まで生きていて、標準出力は1行だけ" "Green"
        $pass++
    } else {
        Say "FAIL  ケース9  最後まで生きていて、標準出力は1行だけ" "Red"
        foreach ($b in $bad9) { Say ("        " + $b) "Red" }
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
    Say "提出前に、prompt_log.md の3件と、演習Cの考察も確認してください。"
    exit 0
} else {
    Say ("{0} / {1} passed" -f $pass, $total) "Red"
    Say "赤い FAIL は故障ではありません。expected と got を見比べて、1つずつ直してください。"
    exit 1
}
