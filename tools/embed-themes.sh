#!/bin/sh
# 把 themes/ 下的两套假站模板重新压进 sing-box-onekey.sh 的 THEME_*_B64 变量
# 用法: 在仓库根目录执行  sh tools/embed-themes.sh
# 注意: 生成的是单行 base64,所以脚本里那两行会很长 —— 这是有意的(离线可用)
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/sing-box-onekey.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

enc() {  # $1=主题目录
    tar czf "$TMP/t.tar.gz" -C "$1" .
    base64 < "$TMP/t.tar.gz" | tr -d '\n'
}

TECH="$(enc "$ROOT/themes/tech")"
POETRY="$(enc "$ROOT/themes/poetry")"

awk -v tech="$TECH" -v poetry="$POETRY" '
    /^THEME_TECH_B64=/   { print "THEME_TECH_B64=\x27" tech "\x27"; next }
    /^THEME_POETRY_B64=/ { print "THEME_POETRY_B64=\x27" poetry "\x27"; next }
    { print }
' "$SCRIPT" > "$TMP/out.sh"

# 语法自检后再覆盖,避免把脚本改坏
if sh -n "$TMP/out.sh"; then
    mv "$TMP/out.sh" "$SCRIPT"
    echo "OK: 已更新 $SCRIPT"
    echo "    tech   $(printf '%s' "$TECH" | wc -c) 字节 base64"
    echo "    poetry $(printf '%s' "$POETRY" | wc -c) 字节 base64"
else
    echo "FAIL: 生成的脚本语法有问题,未覆盖" >&2
    exit 1
fi
