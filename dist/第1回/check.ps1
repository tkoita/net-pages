# =====================================================================
#  ネットワーク応用  第1回 課題  自己採点スクリプト （Windows / PowerShell）
#
#  使い方
#    1. 別ウィンドウで EchoServer を起動したままにする
#         java -jar EchoServer.jar 40001
#    2. NetProbe.java と同じフォルダで、このスクリプトを実行する
#         powershell -ExecutionPolicy Bypass -File check.ps1
#
#  4 / 4 passed になったら提出してください。
# =====================================================================

param(
    [int]$OpenPort   = 40001,   # EchoServer を起動しているポート
    [int]$ClosedPort = 40099,   # 誰も待っていないポート
    [string]$DeadHost = "10.255.255.1"
)

$ErrorActionPreference = "Continue"
$RESULTS = @("CONNECTED", "UNKNOWN_HOST", "REFUSED", "TIMEOUT")

function Write-Head($t) { Write-Host ""; Write-Host $t -Foreground Cyan }

# ---------------------------------------------------------------- 0. 事前確認
if (-not (Test-Path "NetProbe.java")) {
    Write-Host "NetProbe.java が見つかりません。" -Foreground Red
    Write-Host "このスクリプトを NetProbe.java と同じフォルダに置いて実行してください。"
    exit 1
}

Write-Head "[1/3] コンパイル"
javac -encoding UTF-8 NetProbe.java
if ($LASTEXITCODE -ne 0) {
    Write-Host "COMPILE FAILED  —  まずコンパイルエラーを直してください。" -Foreground Red
    exit 1
}
Write-Host "OK" -Foreground Green

# EchoServer が動いているか
Write-Head "[2/3] EchoServer の確認"
$alive = $false
try {
    $c = New-Object Net.Sockets.TcpClient
    $c.Connect("localhost", $OpenPort)
    $alive = $true
    $c.Close()
} catch { }

if (-not $alive) {
    Write-Host "localhost:$OpenPort で EchoServer が待っていません。" -Foreground Red
    Write-Host ""
    Write-Host "  別のウィンドウを開いて、次を実行したままにしてください："
    Write-Host "    java -jar EchoServer.jar $OpenPort" -Foreground Yellow
    Write-Host ""
    Write-Host "  （このウィンドウで起動すると、固まったように見えて採点できません）"
    exit 1
}
Write-Host "OK  localhost:$OpenPort は待ち受け中" -Foreground Green

# ---------------------------------------------------------------- 1. 採点
$cases = @(
    @{ No=1; H="localhost";            P=$OpenPort;   R="CONNECTED";    Addr=$null; Note="EchoServer 起動中" },
    @{ No=2; H="localhost";            P=$ClosedPort; R="REFUSED";      Addr=$null; Note="誰もいないポート" },
    @{ No=3; H="no-such-host.invalid"; P=$OpenPort;   R="UNKNOWN_HOST"; Addr="-";   Note="ADDR=- になること" },
    @{ No=4; H=$DeadHost;              P=$OpenPort;   R="TIMEOUT";      Addr=$null; Note="環境により変わります" }
)

Write-Head "[3/3] 4ケースの採点"
$pass = 0
$case4Note = $false

foreach ($c in $cases) {
    $raw   = java NetProbe $c.H $c.P 2>&1
    $lines = @($raw | ForEach-Object { "$_" })
    $n     = $lines.Count
    $get   = { param($k) ($lines | Where-Object { $_ -like "$k=*" } | Select-Object -First 1) -replace "^$k=", "" }

    $result = (& $get "RESULT").Trim()
    $addr   = (& $get "ADDR").Trim()
    $host_  = (& $get "HOST").Trim()
    $port_  = (& $get "PORT").Trim()

    $ng = @()
    if ($n -ne 5)                        { $ng += "出力が $n 行（5行ちょうどにする）" }
    if ($result -ne $c.R)                { $ng += "RESULT=$result（期待 $($c.R)）" }
    if ($result -and ($RESULTS -notcontains $result)) { $ng += "RESULT に規定外の値" }
    if ($c.Addr -and $addr -ne $c.Addr)  { $ng += "ADDR=$addr（期待 $($c.Addr)）" }
    if ($host_ -ne "$($c.H)")            { $ng += "HOST=$host_（引数をそのまま出す）" }
    if ($port_ -ne "$($c.P)")            { $ng += "PORT=$port_（引数をそのまま出す）" }
    if ($raw -match "Exception in thread|\sat [\w\.]+\(") { $ng += "スタックトレースが出ている" }

    $label = "ケース$($c.No)  $($c.H):$($c.P)"
    if ($ng.Count -eq 0) {
        Write-Host ("PASS  {0,-38} -> {1}" -f $label, $c.R) -Foreground Green
        $pass++
    } else {
        Write-Host ("FAIL  {0,-38} -> {1}" -f $label, $c.Note) -Foreground Red
        foreach ($m in $ng) { Write-Host "        - $m" -Foreground DarkYellow }
        if ($c.No -eq 4) { $case4Note = $true }
    }
}

# ---------------------------------------------------------------- 2. 結果
Write-Host ""
if ($pass -eq 4) {
    Write-Host "$pass / 4 passed" -Foreground Green
    Write-Host ""
    Write-Host "提出前に、もう一度だけ確認してください："
    Write-Host "  - prompt_log.md にプロンプトを3件、原文のまま書いた"
    Write-Host "  - 提出は NetProbe.java と prompt_log.md の2ファイルだけ（ZIP不可・.class を含めない）"
    Write-Host "  - 自分の NetProbe.java を上から下まで読み直した"
    exit 0
} else {
    Write-Host "$pass / 4 passed" -Foreground Red
    if ($case4Note) {
        Write-Host ""
        Write-Host "ケース4 は、ネットワーク環境によって TIMEOUT にならないことがあります。" -Foreground Yellow
        Write-Host "その場合は、実際に出た結果と実行環境（自宅Wi-Fi／大学など）を"      -Foreground Yellow
        Write-Host "prompt_log.md の末尾に書いてください。そのケースは減点しません。"   -Foreground Yellow
        Write-Host "合わせるために RESULT を決め打ちで返すほうが減点対象です。"          -Foreground Yellow
    }
    exit 1
}
