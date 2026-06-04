#!/usr/bin/env bash
# note-publish step3: draft.md → .publish/{body.md, plan.json} + 警告。ブラウザは呼ばない。
# YAML 解析は yq(mikefarah)。
#
# 使い方:
#   prepublish.sh <article-dir>           # .publish/ を生成
#   prepublish.sh <article-dir> --check   # 生成 + 計画/警告を表示(事前点検)
set -u

ARTICLE=""; CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) ARTICLE="$1" ;;
  esac
  shift
done

[ -n "$ARTICLE" ] || { echo "usage: prepublish.sh <article-dir> [--check]" >&2; exit 2; }
command -v yq >/dev/null 2>&1 || { echo "yq (mikefarah) が必要です。mise use -g yq などで。" >&2; exit 2; }
DRAFT="$ARTICLE/draft.md"
[ -f "$DRAFT" ] || { echo "draft not found: $DRAFT" >&2; exit 2; }

OUT="$ARTICLE/.publish"
mkdir -p "$OUT"

# --- body.md 生成 ---
awk '
  # frontmatter 除去
  NR==1 && /^---[ ]*$/ { infm=1; next }
  infm && /^---[ ]*$/ { infm=0; next }
  infm { next }
  # 図メタコメント除去
  /^<!-- figure:/ { infig=1; next }
  infig && /^-->/ { infig=0; next }
  infig { next }
  # paywall マーカー
  /^<!-- paywall:/ { print "@@PAYWALL@@"; next }
  # 引用の出典: <!-- cite: テキスト --> → @@CITE:テキスト@@(直前の引用ブロックの figcaption に入る)
  /^<!-- cite:/ { line=$0; sub(/^<!-- cite:[ ]*/,"",line); sub(/[ ]*-->[ ]*$/,"",line); print "@@CITE:" line "@@"; next }
  # thumbnail インライン参照除去
  /^!\[.*\]\(figures\/thumbnail\.png\)[ ]*$/ { next }
  { print }
' "$DRAFT" > "$OUT/body.md"

# 連続する空行を 1 つに畳む
awk 'NF==0{ if(blank){next} blank=1 } NF>0{blank=0} {print}' "$OUT/body.md" > "$OUT/body.md.tmp" && mv "$OUT/body.md.tmp" "$OUT/body.md"

# --- frontmatter 値の取得 ---
fm="$(awk 'NR==1&&/^---[ ]*$/{d=1;next} d&&/^---[ ]*$/{exit} d{print}' "$DRAFT")"
title="$(printf '%s' "$fm" | yq -r '.title // ""')"
paid="$(printf '%s' "$fm" | yq -r '.paid // false')"
price="$(printf '%s' "$fm" | yq -r '.price // ""')"
url="$(printf '%s' "$fm" | yq -r '.url // ""')"

ABS_ART="$(cd "$ARTICLE" && pwd)"
THUMB_ABS=""
[ -f "$ABS_ART/figures/thumbnail.png" ] && THUMB_ABS="$ABS_ART/figures/thumbnail.png"
BODY_ABS="$ABS_ART/.publish/body.md"

tags_json="$(printf '%s' "$fm" | yq -o=json -I=0 '.tags // []')"

# --- JSON エスケープヘルパー (バックスラッシュ → \\ 、ダブルクォート → \") ---
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

# 本文中の画像参照(draft 基準で全件、thumbnail を除外)をリストとして一度だけ収集 (I3)
image_refs=""
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  [ "$ref" = "figures/thumbnail.png" ] && continue
  image_refs="${image_refs}${image_refs:+$'\n'}${ref}"
done < <(grep -oE '!\[[^]]*\]\(figures/[^)]+\)' "$DRAFT" \
  | sed -E 's/^!\[[^]]*\]\((figures\/[^)]+)\)$/\1/')

# image_refs リストから JSON 配列を組み立てる (C2: ref/absPath を json_escape でエスケープ)
images_acc=""
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  ex=false
  [ -f "$ABS_ART/$ref" ] && ex=true
  esc_ref="$(json_escape "$ref")"
  esc_abs="$(json_escape "$ABS_ART/$ref")"
  obj="{\"ref\":\"${esc_ref}\",\"absPath\":\"${esc_abs}\",\"exists\":$ex}"
  images_acc="${images_acc}${images_acc:+,}${obj}"
done <<< "$image_refs"
images_json="[${images_acc}]"

# paywall 検出
if grep -q '^@@PAYWALL@@$' "$OUT/body.md"; then
  pw_present=true
  pw_line="$(grep -n '^@@PAYWALL@@$' "$OUT/body.md" | head -1 | cut -d: -f1)"
else
  pw_present=false
  pw_line=null
fi

# target
if [ -n "$url" ] && [ "$url" != "null" ]; then
  target_json="url"   # sentinel: use env(YQ_URL) in yq expression
else
  target_json="null"
fi

# --- warnings 収集 ---
warnings_acc=""
add_warn() {
  local msg="$1"
  msg="$(json_escape "$msg")"
  warnings_acc="${warnings_acc}${warnings_acc:+,}\"${msg}\""
}

[ -z "$THUMB_ABS" ] && add_warn "サムネ(figures/thumbnail.png)がありません。note-figures で生成してください。"

# image_refs リストから未生成警告 (I3: grep を再実行しない)
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  [ -f "$ABS_ART/$ref" ] || add_warn "画像が未生成です: $ref"
done <<< "$image_refs"

# figure ブロックに対応するインライン参照がない場合の警告
# image_refs から basename(sans-ext) のセットを作る
ref_ids=""
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  # figures/figX.png → figX
  base="${ref##*/}"          # figX.png
  id="${base%.*}"            # figX
  ref_ids="${ref_ids}${ref_ids:+$'\n'}${id}"
done <<< "$image_refs"

# draft から figure id を収集(thumbnail を除外)して ref_ids と突合
while IFS= read -r fid; do
  [ -n "$fid" ] || continue
  [ "$fid" = "thumbnail" ] && continue
  # ref_ids の中に完全一致する行があるか
  if ! printf '%s\n' $ref_ids | grep -qx "$fid"; then
    add_warn "figure ブロック '$(json_escape "$fid")' に対応する本文の ![]() 参照がありません(画像が投稿に挿入されません)。"
  fi
done < <(grep -oE '^<!-- figure: [^ ]+' "$DRAFT" | sed -E 's/^<!-- figure: //')

# paywall マーカーが複数ある場合の警告 (I1)
pw_count="$(grep -c '^@@PAYWALL@@$' "$OUT/body.md" 2>/dev/null || true)"
[ "${pw_count:-0}" -gt 1 ] && add_warn "paywall マーカーが複数あります。最初の位置を使います。"

# 引用の出典(@@CITE@@)が引用ブロックの直後にない場合の警告(直前行が `>` でない)
cite_misplaced="$(awk 'prev !~ /^>/ && /^@@CITE:/ {c++} {prev=$0} END{print c+0}' "$OUT/body.md")"
[ "${cite_misplaced:-0}" -gt 0 ] && add_warn "出典(<!-- cite: ... -->)が引用(> ...)の直後にない箇所があります。出典は引用ブロックの直後に置いてください。"

grep -q '\$\$' "$OUT/body.md" && add_warn "数式(\$\$)を含みます。note 上で表示を要確認。"
grep -qE '^\|.*\|[ ]*$' "$OUT/body.md" && add_warn "表(Markdown table)を含みます。note は表非対応。画像化を検討。"
if [ "$paid" = "true" ]; then
  add_warn "paid:true です。価格(${price:-未設定})は note 上で手動設定してください。"
fi
warnings_json="[${warnings_acc}]"

# --- plan.json 生成 (C1: スカラーは env() 経由で安全に渡す) ---
export YQ_TITLE="$title"
export YQ_THUMB="$THUMB_ABS"
export YQ_BODY="$BODY_ABS"
export YQ_PRICE="$price"
export YQ_URL="$url"

if [ "$target_json" = "url" ]; then
  yq -n -o=json "
    .title = strenv(YQ_TITLE) |
    .tags = $tags_json |
    .thumbnailPath = strenv(YQ_THUMB) |
    .bodyPath = strenv(YQ_BODY) |
    .images = ${images_json} |
    .paywall.present = $pw_present |
    .paywall.line = $pw_line |
    .paid = $paid |
    .price = strenv(YQ_PRICE) |
    .target = strenv(YQ_URL) |
    .warnings = ${warnings_json}
  " > "$OUT/plan.json" || { echo "plan.json 生成に失敗しました" >&2; exit 1; }
else
  yq -n -o=json "
    .title = strenv(YQ_TITLE) |
    .tags = $tags_json |
    .thumbnailPath = strenv(YQ_THUMB) |
    .bodyPath = strenv(YQ_BODY) |
    .images = ${images_json} |
    .paywall.present = $pw_present |
    .paywall.line = $pw_line |
    .paid = $paid |
    .price = strenv(YQ_PRICE) |
    .target = null |
    .warnings = ${warnings_json}
  " > "$OUT/plan.json" || { echo "plan.json 生成に失敗しました" >&2; exit 1; }
fi

# --- --check 表示 ---
if [ "$CHECK" -eq 1 ]; then
  echo "== 投稿計画: $ARTICLE =="
  echo "title : $title"
  echo "tags  : $tags_json"
  echo "thumb : ${THUMB_ABS:-(なし)}"
  echo "images: $(yq -r '.images | length' "$OUT/plan.json") 件"
  echo "paywall: $pw_present (line=$pw_line)"
  echo "paid  : $paid  price: ${price:-(空)}"
  echo "target: $(printf '%s' "$target_json")  (非nullなら全置換の再同期)"
  if [ "$(yq -r '.warnings | length' "$OUT/plan.json")" -gt 0 ]; then
    echo "-- 警告 --"
    yq -r '.warnings[]' "$OUT/plan.json" | sed 's/^/  ! /'
  else
    echo "警告なし"
  fi
fi

exit 0
