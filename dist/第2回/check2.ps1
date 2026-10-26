# ============================================================================
#  check2.ps1  --  第2回 課題 EchoClient.java の自己採点
# ----------------------------------------------------------------------------
#  使い方（EchoClient.java と EchoServer.jar と同じフォルダで）:
#
#      powershell -ExecutionPolicy Bypass -File check2.ps1
#
#  ・EchoServer が 40001 で起動していなければ、このスクリプトが自分で起動し、
#    終わったら止めます。起動済みなら、それをそのまま使います。
#  ・1ケース 8 秒たっても終わらない場合は、打ち切って FAIL にします。
#  ・4 / 4 passed になってから提出してください。
# ============================================================================
$ErrorActionPreference = "Continue"

$PORT       = 40001
$CLOSED     = 40099
$TIMEOUT_MS = 8000

try { if ($env:OS -eq "Windows_NT") { chcp 65001 > $null } } catch {}
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$HERE = $PSScriptRoot
if ([string]::IsNullOrEmpty($HERE)) { $HERE = (Get-Location).Path }
Set-Location $HERE

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
Say "=== 第2回 EchoClient.java 自己採点 ===" "Cyan"
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

if (-not (Test-Path (Join-Path $HERE "EchoClient.java"))) {
    Say "EchoClient.java が、このスクリプトと同じフォルダにありません。" "Red"
    exit 1
}

$src = Get-Content (Join-Path $HERE "EchoClient.java") -Raw -Encoding UTF8

# package 行があると「java EchoClient」で起動できない
if ($src -match '(?m)^\s*package\s+[\w\.]+\s*;') {
    Say "EchoClient.java の先頭に package 行があります。消してから実行してください。" "Red"
    Say "  （package があると、このフォルダで java EchoClient として起動できません）" "Red"
    exit 1
}

# ---------------------------------------------------------------------------
# 2. ソースの確認（点数には影響しません。警告だけ出します）
# ---------------------------------------------------------------------------
$code = [regex]::Replace($src, '(?s)/\*.*?\*/', '')
$code = [regex]::Replace($code, '//[^\r\n]*', '')
$warn = @()
if ($code -match 'newLine\s*\(')                         { $warn += "newLine() を使っています。Windows では 0D 0A の2バイトになります（0A だけを送ること）" }
if ($code -match 'getBytes\s*\(\s*\)')                   { $warn += "getBytes() に文字コードを渡していません" }
if ($code -match 'new\s+String\s*\(\s*\w+\s*\)')          { $warn += "new String(byte[]) に文字コードを渡していない可能性があります" }
if ($code -match 'new\s+InputStreamReader\s*\(\s*[^,()]+\)') { $warn += "InputStreamReader に文字コードを渡していません" }
if ($code -match 'catch\s*\(\s*Exception\s+\w+\s*\)')    { $warn += "catch (Exception e) があります。例外は3種類に分けてください" }
foreach ($w in $warn) { Say ("警告: " + $w) "Yellow" }
if ($warn.Count -gt 0) { Say "" }

# ---------------------------------------------------------------------------
# 3. コンパイル
# ---------------------------------------------------------------------------
& javac -encoding UTF-8 EchoClient.java
if ($LASTEXITCODE -ne 0) {
    Say "COMPILE FAILED  javac -encoding UTF-8 EchoClient.java が通りません" "Red"
    exit 1
}

# ---------------------------------------------------------------------------
# 4. EchoServer の用意
# ---------------------------------------------------------------------------
$srv = $null
$srvOut = Join-Path ([System.IO.Path]::GetTempPath()) ("check2_srv_out_{0}.txt" -f $PID)
$srvErr = Join-Path ([System.IO.Path]::GetTempPath()) ("check2_srv_err_{0}.txt" -f $PID)

function Run-Client([string[]]$argList) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $JAVA
    $psi.Arguments = "-cp . EchoClient " + ($argList -join " ")
    $psi.WorkingDirectory = $HERE
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $p = [System.Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync()
    $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TIMEOUT_MS)) {
        try { $p.Kill() } catch {}
        return @{ TimedOut = $true }
    }
    $p.WaitForExit()

    $t = $o.Result -replace "`r`n", "`n"
    if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    $lines = @()
    if ($t.Length -gt 0) { $lines = $t.Split("`n") }
    return @{ TimedOut = $false; Lines = $lines; Err = $e.Result; ExitCode = $p.ExitCode }
}

$KEYS9 = @("HOST","PORT","CHARSET","SEND_CHARS","SEND_BYTES","SEND_HEX","RECV_BYTES","RECV_HEX","MATCH")
$KEYS4 = @("HOST","PORT","CHARSET","ERROR")

$cases = @(
    @{ n = "ケース1  ASCII を UTF-8 で";      a = @("localhost", "$PORT",   "ASCII", "UTF-8");     keys = $KEYS9;
       e = [ordered]@{ HOST = "localhost"; PORT = "$PORT"; CHARSET = "UTF-8";
                       SEND_CHARS = "5"; SEND_BYTES = "6"; SEND_HEX = "48 45 4C 4C 4F 0A";
                       RECV_BYTES = "6"; RECV_HEX = "48 45 4C 4C 4F 0A"; MATCH = "true" } },
    @{ n = "ケース2  日本語を UTF-8 で";      a = @("localhost", "$PORT",   "JP",    "UTF-8");     keys = $KEYS9;
       e = [ordered]@{ HOST = "localhost"; PORT = "$PORT"; CHARSET = "UTF-8";
                       SEND_CHARS = "5"; SEND_BYTES = "16";
                       SEND_HEX = "E3 81 93 E3 82 93 E3 81 AB E3 81 A1 E3 81 AF 0A";
                       RECV_BYTES = "16";
                       RECV_HEX = "E3 81 93 E3 82 93 E3 81 AB E3 81 A1 E3 81 AF 0A"; MATCH = "true" } },
    @{ n = "ケース3  日本語を Shift_JIS で";  a = @("localhost", "$PORT",   "JP",    "Shift_JIS"); keys = $KEYS9;
       e = [ordered]@{ HOST = "localhost"; PORT = "$PORT"; CHARSET = "Shift_JIS";
                       SEND_CHARS = "5"; SEND_BYTES = "11";
                       SEND_HEX = "82 B1 82 F1 82 C9 82 BF 82 CD 0A"; MATCH = "false" } },
    @{ n = "ケース4  誰も待っていないポート"; a = @("localhost", "$CLOSED", "ASCII", "UTF-8");     keys = $KEYS4;
       e = [ordered]@{ HOST = "localhost"; PORT = "$CLOSED"; CHARSET = "UTF-8"; ERROR = "REFUSED" } }
)

function Check-Case($c, $res) {
    $bad = New-Object System.Collections.ArrayList
    if ($res.TimedOut) {
        [void]$bad.Add(("{0} 秒たっても終わりませんでした（固まっています）" -f ($TIMEOUT_MS / 1000)))
        [void]$bad.Add("flush() を呼んでいるか、送信の最後に改行 0A を付けているか確認してください")
        return ,$bad
    }

    $lines = $res.Lines
    $want  = $c.keys.Count
    if ($lines.Count -gt $want) {
        [void]$bad.Add(("lines={0}（{1}行であること。余計な println が残っていませんか）" -f $lines.Count, $want))
    } elseif ($lines.Count -lt $want) {
        [void]$bad.Add(("lines={0}（{1}行であること。途中で止まったか、出していない行があります）" -f $lines.Count, $want))
    }

    foreach ($l in $lines) {
        if ($l -match '[^\x20-\x7E]') {
            [void]$bad.Add("ASCII 以外の文字が出ています（出力に日本語を含めないこと）: " + $l)
            break
        }
    }

    $map = @{}
    $order = @()
    foreach ($l in $lines) {
        $i = $l.IndexOf("=")
        if ($i -gt 0) {
            $k = $l.Substring(0, $i)
            $map[$k] = $l.Substring($i + 1)
            $order += $k
        }
    }

    $expOrder = $c.keys -join ","
    $gotOrder = $order -join ","
    if ($lines.Count -eq $want -and $gotOrder -ne $expOrder) {
        [void]$bad.Add("行の順番が違います: expected=" + $expOrder)
        [void]$bad.Add("                         got=" + $gotOrder)
    }

    foreach ($k in $c.e.Keys) {
        $got = $map[$k]
        if ($got -cne $c.e[$k]) {
            if ($null -eq $got) { $got = "(なし)" }
            [void]$bad.Add(("{0}: expected={1} got={2}" -f $k, $c.e[$k], $got))
        }
    }

    foreach ($pair in @(@("SEND_HEX", "SEND_BYTES"), @("RECV_HEX", "RECV_BYTES"))) {
        $hk = $pair[0]; $bk = $pair[1]
        if ($map.ContainsKey($hk)) {
            $h = $map[$hk]
            if ($h -cnotmatch '^[0-9A-F]{2}( [0-9A-F]{2})*$') {
                [void]$bad.Add(("{0} の形式が違います（大文字2桁・半角スペース1つ区切り・末尾スペースなし）: [{1}]" -f $hk, $h))
            } elseif ($map.ContainsKey($bk)) {
                $cnt = ($h -split ' ').Count
                if ("$cnt" -ne $map[$bk]) {
                    [void]$bad.Add(("{0} は {1} バイトぶんなのに {2}={3} です" -f $hk, $cnt, $bk, $map[$bk]))
                }
            }
        }
    }

    if ($res.Err -match '(?m)^\s+at\s') {
        [void]$bad.Add("スタックトレースが出ています（例外を捕まえていません）")
    }
    if ($res.ExitCode -ne 0) {
        [void]$bad.Add(("終了コードが {0} です（正常終了 0 で終わること）" -f $res.ExitCode))
    }
    return ,$bad
}

$pass = 0
try {
    if (Test-Port $PORT) {
        Say ("EchoServer が {0} で起動済みです。それを使います。" -f $PORT)
    } else {
        if (-not (Test-Path (Join-Path $HERE "EchoServer.jar"))) {
            Say "40001 で EchoServer が起動しておらず、EchoServer.jar も同じフォルダにありません。" "Red"
            exit 1
        }
        Say ("EchoServer を {0} で起動します（終わったら止めます）。" -f $PORT)
        $srv = Start-Process -FilePath $JAVA -ArgumentList @("-jar", "EchoServer.jar", "$PORT") `
                             -WorkingDirectory $HERE -NoNewWindow -PassThru `
                             -RedirectStandardOutput $srvOut -RedirectStandardError $srvErr
        $ok = $false
        for ($i = 0; $i -lt 24; $i++) {
            Start-Sleep -Milliseconds 250
            if (Test-Port $PORT) { $ok = $true; break }
        }
        if (-not $ok) {
            Say "EchoServer を起動できませんでした。40001 を別のプログラムが使っていないか確認してください。" "Red"
            Say "  netstat -ano | findstr 40001" "Red"
            exit 1
        }
    }

    if (Test-Port $CLOSED) {
        Say ("注意: {0} で何かが待ち受けています。ケース4 が正しく判定できません。" -f $CLOSED) "Yellow"
    }
    Say ""

    foreach ($c in $cases) {
        $res = Run-Client $c.a
        $bad = Check-Case $c $res
        if ($bad.Count -eq 0) {
            Say ("PASS  {0}" -f $c.n) "Green"
            $pass++
        } else {
            Say ("FAIL  {0}" -f $c.n) "Red"
            Say ("        java EchoClient {0}" -f ($c.a -join " ")) "DarkGray"
            foreach ($b in $bad) { Say ("        " + $b) "Red" }
        }
    }
} finally {
    if ($srv) {
        try { Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue } catch {}
        Start-Sleep -Milliseconds 300
    }
    Remove-Item $srvOut, $srvErr -ErrorAction SilentlyContinue
}

Say ""
if ($pass -eq $cases.Count) {
    Say ("{0} / {1} passed" -f $pass, $cases.Count) "Green"
    Say "提出前に、prompt_log.md の3件とケース3の考察も確認してください。"
    exit 0
} else {
    Say ("{0} / {1} passed" -f $pass, $cases.Count) "Red"
    Say "赤い FAIL は故障ではありません。expected と got を見比べて、1つずつ直してください。"
    exit 1
}
