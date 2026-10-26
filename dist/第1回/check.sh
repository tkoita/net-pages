#!/usr/bin/env bash
# =====================================================================
#  ネットワーク応用  第1回 課題  自己採点スクリプト （macOS / Linux）
#
#  使い方
#    1. 別のターミナルで EchoServer を起動したままにする
#         java -jar EchoServer.jar 40001
#    2. NetProbe.java と同じディレクトリで実行する
#         bash check.sh
#
#  4 / 4 passed になったら提出してください。
# =====================================================================

OPEN_PORT="${OPEN_PORT:-40001}"     # EchoServer を起動しているポート
CLOSED_PORT="${CLOSED_PORT:-40099}" # 誰も待っていないポート
DEAD_HOST="${DEAD_HOST:-10.255.255.1}"

if [ -t 1 ]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; C=$'\033[36m'; N=$'\033[0m'
else
  R=''; G=''; Y=''; C=''; N=''
fi

# ---------------------------------------------------------------- 0. 事前確認
if [ ! -f NetProbe.java ]; then
  echo "${R}NetProbe.java が見つかりません。${N}"
  echo "このスクリプトを NetProbe.java と同じディレクトリに置いて実行してください。"
  exit 1
fi

echo
echo "${C}[1/3] コンパイル${N}"
if ! javac -encoding UTF-8 NetProbe.java; then
  echo "${R}COMPILE FAILED  —  まずコンパイルエラーを直してください。${N}"
  exit 1
fi
echo "${G}OK${N}"

echo
echo "${C}[2/3] EchoServer の確認${N}"
if ! (exec 3<>"/dev/tcp/127.0.0.1/${OPEN_PORT}") 2>/dev/null; then
  echo "${R}localhost:${OPEN_PORT} で EchoServer が待っていません。${N}"
  echo
  echo "  別のターミナルを開いて、次を実行したままにしてください："
  echo "    ${Y}java -jar EchoServer.jar ${OPEN_PORT}${N}"
  echo
  echo "  （同じターミナルで起動すると、固まったように見えて採点できません）"
  exit 1
fi
exec 3<&- 2>/dev/null
echo "${G}OK  localhost:${OPEN_PORT} は待ち受け中${N}"

# ---------------------------------------------------------------- 1. 採点
echo
echo "${C}[3/3] 4ケースの採点${N}"

pass=0
case4_failed=0

field() { printf '%s\n' "$1" | grep "^$2=" | head -n 1 | sed "s/^$2=//" | tr -d '\r'; }

run_case() {
  local no="$1" h="$2" p="$3" want="$4" want_addr="$5" note="$6"
  local out n result addr host_ port_ ng label

  out="$(java NetProbe "$h" "$p" 2>&1)"
  n="$(printf '%s\n' "$out" | grep -c '')"
  result="$(field "$out" RESULT)"
  addr="$(field "$out" ADDR)"
  host_="$(field "$out" HOST)"
  port_="$(field "$out" PORT)"

  ng=()
  [ "$n" -ne 5 ] && ng+=("出力が ${n} 行（5行ちょうどにする）")
  [ "$result" != "$want" ] && ng+=("RESULT=${result}（期待 ${want}）")
  case "$result" in
    CONNECTED|UNKNOWN_HOST|REFUSED|TIMEOUT|"") ;;
    *) ng+=("RESULT に規定外の値") ;;
  esac
  [ -n "$want_addr" ] && [ "$addr" != "$want_addr" ] && ng+=("ADDR=${addr}（期待 ${want_addr}）")
  [ "$host_" != "$h" ] && ng+=("HOST=${host_}（引数をそのまま出す）")
  [ "$port_" != "$p" ] && ng+=("PORT=${port_}（引数をそのまま出す）")
  printf '%s' "$out" | grep -qE 'Exception in thread|^[[:space:]]+at [A-Za-z0-9_.$]+\(' \
    && ng+=("スタックトレースが出ている")

  label="$(printf 'ケース%s  %s:%s' "$no" "$h" "$p")"
  if [ ${#ng[@]} -eq 0 ]; then
    printf "${G}PASS  %-38s -> %s${N}\n" "$label" "$want"
    pass=$((pass + 1))
  else
    printf "${R}FAIL  %-38s -> %s${N}\n" "$label" "$note"
    for m in "${ng[@]}"; do printf "        ${Y}- %s${N}\n" "$m"; done
    [ "$no" = "4" ] && case4_failed=1
  fi
}

run_case 1 "localhost"            "$OPEN_PORT"   "CONNECTED"    ""  "EchoServer 起動中"
run_case 2 "localhost"            "$CLOSED_PORT" "REFUSED"      ""  "誰もいないポート"
run_case 3 "no-such-host.invalid" "$OPEN_PORT"   "UNKNOWN_HOST" "-" "ADDR=- になること"
run_case 4 "$DEAD_HOST"           "$OPEN_PORT"   "TIMEOUT"      ""  "環境により変わります"

# ---------------------------------------------------------------- 2. 結果
echo
if [ "$pass" -eq 4 ]; then
  echo "${G}${pass} / 4 passed${N}"
  echo
  echo "提出前に、もう一度だけ確認してください："
  echo "  - prompt_log.md にプロンプトを3件、原文のまま書いた"
  echo "  - 提出は NetProbe.java と prompt_log.md の2ファイルだけ（ZIP不可・.class を含めない）"
  echo "  - 自分の NetProbe.java を上から下まで読み直した"
  exit 0
else
  echo "${R}${pass} / 4 passed${N}"
  if [ "$case4_failed" = "1" ]; then
    echo
    echo "${Y}ケース4 は、ネットワーク環境によって TIMEOUT にならないことがあります。${N}"
    echo "${Y}その場合は、実際に出た結果と実行環境（自宅Wi-Fi／大学など）を${N}"
    echo "${Y}prompt_log.md の末尾に書いてください。そのケースは減点しません。${N}"
    echo "${Y}合わせるために RESULT を決め打ちで返すほうが減点対象です。${N}"
  fi
  exit 1
fi
