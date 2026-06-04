#!/usr/bin/env bash
# prepublish.sh の整形ロジック検証(ブラウザを呼ばない)。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/prepublish.sh"
FX="$HERE/fixtures/basic"
fail=0
check() { # check <desc> <cmd...>  : cmd の終了コード0で pass
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok   - $desc"; else echo "FAIL - $desc"; fail=1; fi
}
# テスト前にクリーン
rm -rf "$FX/.publish"
bash "$SCRIPT" "$FX" --check >/dev/null 2>&1 || { echo "SCRIPT FAILED"; exit 1; }

BODY="$FX/.publish/body.md"

# body.md が生成される
check "body.md generated" test -f "$BODY"
# frontmatter が除去されている(title: 行が body 先頭に無い)
check "frontmatter stripped" bash -c '! grep -q "^title:" "'"$BODY"'"'
# 図メタコメントが除去されている
check "figure comments stripped" bash -c '! grep -q "<!-- figure:" "'"$BODY"'"'
# thumbnail のインライン参照が除去されている
check "thumbnail ref removed" bash -c '! grep -q "figures/thumbnail.png" "'"$BODY"'"'
# 本文の他画像参照は残っている
check "other image ref kept" grep -q "figures/fig1.png" "$BODY"
# 見出しと本文テキストは残っている
check "heading kept" grep -q "^## 見出し1" "$BODY"
check "body text kept" grep -q "締めの段落" "$BODY"

PLAN="$FX/.publish/plan.json"
check "plan.json generated" test -f "$PLAN"
check "plan.title" bash -c '[ "$(yq -r .title "'"$PLAN"'")" = "テスト記事のタイトル" ]'
check "plan.tags has Python" bash -c 'yq -r ".tags[]" "'"$PLAN"'" | grep -qx "Python"'
check "plan.paid false" bash -c '[ "$(yq -r .paid "'"$PLAN"'")" = "false" ]'
check "plan.thumbnail abs path" bash -c 'yq -r .thumbnailPath "'"$PLAN"'" | grep -q "/figures/thumbnail.png$"'
check "plan.body abs path" bash -c 'yq -r .bodyPath "'"$PLAN"'" | grep -q "/.publish/body.md$"'
check "plan.images includes fig1" bash -c 'yq -r ".images[].ref" "'"$PLAN"'" | grep -q "figures/fig1.png"'
check "plan.images exists true" bash -c '[ "$(yq -r ".images[] | select(.ref==\"figures/fig1.png\") | .exists" "'"$PLAN"'")" = "true" ]'
check "plan.target null" bash -c '[ "$(yq -r ".target // \"null\"" "'"$PLAN"'")" = "null" ]'
check "plan.paywall false" bash -c '[ "$(yq -r .paywall.present "'"$PLAN"'")" = "false" ]'

# --- 警告 fixture ---
FXW="$HERE/fixtures/warn"
rm -rf "$FXW/.publish"
bash "$SCRIPT" "$FXW" --check >/dev/null 2>&1 || { echo "SCRIPT FAILED"; exit 1; }
PLANW="$FXW/.publish/plan.json"
check "warn: no thumbnail" bash -c 'yq -r ".warnings[]" "'"$PLANW"'" | grep -q "サムネ"'
check "warn: missing image" bash -c 'yq -r ".warnings[]" "'"$PLANW"'" | grep -q "画像"'
check "warn: math" bash -c 'yq -r ".warnings[]" "'"$PLANW"'" | grep -q "数式"'
check "warn: table" bash -c 'yq -r ".warnings[]" "'"$PLANW"'" | grep -q "表"'
check "warn: paid price" bash -c 'yq -r ".warnings[]" "'"$PLANW"'" | grep -q "価格"'
check "warn: paywall present" bash -c '[ "$(yq -r .paywall.present "'"$PLANW"'")" = "true" ]'

# --- 冪等性 ---
bash "$SCRIPT" "$FX" >/dev/null 2>&1 || { echo "SCRIPT FAILED"; exit 1; }
sum1_body="$(cksum "$FX/.publish/body.md")"
sum1_plan="$(cksum "$FX/.publish/plan.json")"
bash "$SCRIPT" "$FX" >/dev/null 2>&1 || { echo "SCRIPT FAILED"; exit 1; }
sum2_body="$(cksum "$FX/.publish/body.md")"
sum2_plan="$(cksum "$FX/.publish/plan.json")"
check "idempotent body.md" bash -c '[ "'"$sum1_body"'" = "'"$sum2_body"'" ]'
check "idempotent plan.json" bash -c '[ "'"$sum1_plan"'" = "'"$sum2_plan"'" ]'

# --- special-char fixture (C1/C2 回帰テスト) ---
FXS="$HERE/fixtures/special"
rm -rf "$FXS/.publish"
bash "$SCRIPT" "$FXS" >/dev/null 2>&1 || { echo "SCRIPT FAILED"; exit 1; }
PLANS="$FXS/.publish/plan.json"
check "special: script exits 0" test -f "$PLANS"
check "special: title round-trip" bash -c '[ "$(yq -r .title "'"$PLANS"'")" = "彼は\"OK\\テスト\"と言った" ]'

# --- 未参照 figure 警告 fixture ---
FXN="$HERE/fixtures/noref"
rm -rf "$FXN/.publish"
bash "$SCRIPT" "$FXN" --check >/dev/null 2>&1 || { echo "SCRIPT FAILED"; exit 1; }
PLANN="$FXN/.publish/plan.json"
check "noref: figA warned" bash -c 'yq -r ".warnings[]" "'"$PLANN"'" | grep -q "figA"'
check "noref: figB not warned" bash -c '! yq -r ".warnings[]" "'"$PLANN"'" | grep -q "figB"'
check "noref: thumbnail not warned (no unref-figure for thumbnail)" bash -c '! yq -r ".warnings[]" "'"$PLANN"'" | grep -q "thumbnail.*参照"'

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }
