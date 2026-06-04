#!/usr/bin/env bash
# note-figures の render.sh テスト(依存なし)。
# 実行: bash skills/note-figures/tests/test_render.sh
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
RENDER="$DIR/../scripts/render.sh"
ARTICLE="$DIR/fixtures/articles/sample"
STYLES="$DIR/fixtures/styles"

pass=0; fail=0
TAB=$'\t'

check() { # check <name> <expected> <actual>
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "PASS: $name"; pass=$((pass + 1))
  else echo "FAIL: $name"; printf '  expected:\n%s\n  actual:\n%s\n' "$expected" "$actual"; fail=$((fail + 1)); fi
}
contains() { # contains <name> <haystack> <needle...>
  local name="$1" hay="$2"; shift 2
  local ok=1 n
  for n in "$@"; do printf '%s' "$hay" | grep -qF "$n" || ok=0; done
  if [ "$ok" -eq 1 ]; then echo "PASS: $name"; pass=$((pass + 1))
  else echo "FAIL: $name (missing one of: $*)"; printf '  got:\n%s\n' "$hay"; fail=$((fail + 1)); fi
}

# --- Test: --list は全figureを id<TAB>相対パス<TAB>解決スタイル名 で出す ---
expected="thumbnail${TAB}figures/thumbnail.png${TAB}thumbnail-bold
fig1${TAB}figures/fig1.png${TAB}flat-diagram"
actual="$(bash "$RENDER" "$ARTICLE" --list --styles-dir "$STYLES" 2>/dev/null)"
check "list shows id/path/resolved-style for all figures" "$expected" "$actual"

# --- Test: 存在しないスタイル名はエラー(非0終了) ---
BAD="$DIR/fixtures/articles/badstyle"
err="$(bash "$RENDER" "$BAD" --list --styles-dir "$STYLES" 2>&1 >/dev/null)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$err" | grep -q "nonexistent"; then
  echo "PASS: unknown style name errors out"; pass=$((pass + 1))
else echo "FAIL: unknown style name errors out (rc=$rc)"; fail=$((fail + 1)); fi

# --- Test: --prompt <id> は構造化プロンプト(figure構造+スタイル構造+保存先)を出す ---
out="$(bash "$RENDER" "$ARTICLE" --prompt fig1 --styles-dir "$STYLES" 2>/dev/null)"
contains "prompt is structured (figure + style fields + path)" "$out" \
  '$imagegen' 'kind: 概念図' 'intent: 仕組みを示す' 'AからBへの変換フロー' \
  'トーン: ミニマル' '#2563EB' 'サイズ:' 'figures/fig1.png'

# --- Test: 後処理禁止(画像生成のみ)の指示が必ず入る ---
contains "prompt forbids post-processing (image-gen only)" "$out" \
  '画像生成' '後処理' 'SVG' 'PNG変換' 'ファイル編集'

# --- Test: --prompt は複数行 prompt を平坦化せず保つ ---
out="$(bash "$RENDER" "$ARTICLE" --prompt thumbnail --styles-dir "$STYLES" 2>/dev/null)"
contains "prompt keeps multi-line figure content" "$out" \
  '確率分布のグラフを抽象化したサムネ' '数式をうっすら背景に'

# --- 計画(plan)の準備 ---
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
setup_article() { local d="$TMP/art-$1"; rm -rf "$d"; mkdir -p "$d"; cp "$ARTICLE/draft.md" "$d/draft.md"; echo "$d"; }

# --- Test: plan(既定)は未生成 figure だけを id<TAB>絶対パス で出す ---
art="$(setup_article skip)"; mkdir -p "$art/figures"; : > "$art/figures/thumbnail.png"
ids="$(bash "$RENDER" "$art" --styles-dir "$STYLES" 2>/dev/null | cut -f1)"
check "plan lists only missing figures" "fig1" "$ids"
line="$(bash "$RENDER" "$art" --styles-dir "$STYLES" 2>/dev/null)"
contains "plan includes absolute image path" "$line" "$art/figures/fig1.png"

# --- Test: --force は全 figure を計画 ---
art="$(setup_article force)"; mkdir -p "$art/figures"; : > "$art/figures/thumbnail.png"
ids="$(bash "$RENDER" "$art" --force --styles-dir "$STYLES" 2>/dev/null | cut -f1)"
check "--force plans all figures" "thumbnail
fig1" "$ids"

echo "---"; echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
