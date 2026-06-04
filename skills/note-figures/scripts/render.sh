#!/usr/bin/env bash
# note-figures: draft.md の図メタ + styles/ を解決する。codex は呼ばない。
# 画像生成は Agent が `--prompt <id>` の構造化プロンプトを codex exec に渡して行う。
# YAML 解析は yq(mikefarah)。
#
# 使い方:
#   render.sh <article-dir> [--styles-dir DIR]            # plan: 未生成figureを id<TAB>絶対パス で出力
#   render.sh <article-dir> --force [--styles-dir DIR]    # plan: 既存も含め全figure
#   render.sh <article-dir> --list  [--styles-dir DIR]    # 全figureを id<TAB>相対パス<TAB>解決スタイル名 で出力
#   render.sh <article-dir> --prompt <id> [--styles-dir DIR]  # その figure の構造化プロンプト全文を stdout に
set -u

ARTICLE=""; MODE="plan"; FORCE=0; STYLES_DIR=""; PROMPT_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --list) MODE="list" ;;
    --prompt) MODE="prompt"; shift; PROMPT_ID="$1" ;;
    --force) FORCE=1 ;;
    --styles-dir) shift; STYLES_DIR="$1" ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) ARTICLE="$1" ;;
  esac
  shift
done

[ -n "$ARTICLE" ] || { echo "usage: render.sh <article-dir> [--list|--force|--prompt <id>] [--styles-dir DIR]" >&2; exit 2; }
command -v yq >/dev/null 2>&1 || { echo "yq (mikefarah) が必要です。mise use -g yq などで入れてください。" >&2; exit 2; }
DRAFT="$ARTICLE/draft.md"
[ -f "$DRAFT" ] || { echo "draft not found: $DRAFT" >&2; exit 2; }
[ -n "$STYLES_DIR" ] || STYLES_DIR="$(cd "$ARTICLE/../.." && pwd)/styles"

# frontmatter の image_style(既定スタイル)
fm="$(awk '/^---[ ]*$/{d++; next} d==1{print} d>=2{exit}' "$DRAFT")"
default_style="$(printf '%s' "$fm" | yq '.image_style // ""')"

# 図メタブロックを複数doc YAML へ(<!-- figure: id -> id: id、--> 除去、--- 区切り)
ystream="$(awk '
  /^<!-- figure:/ { if (started) print "---"; started=1; inblk=1;
    id=$0; sub(/^<!-- figure:[ ]*/,"",id); sub(/[ ]*$/,"",id); print "id: \"" id "\""; next }
  inblk && /^-->/ { inblk=0; next }
  inblk { print }
' "$DRAFT")"
[ -n "$ystream" ] || exit 0
n=$(printf '%s' "$ystream" | yq 'di' | tail -1)

# figure の style を解決(figure.style > frontmatter.image_style)。styles に無ければエラー。
resolve_style() { # resolve_style <figure-style> <figure-id>
  local s="$1" fid="$2"
  [ -n "$s" ] && [ "$s" != "null" ] || s="$default_style"
  if [ -n "$s" ] && [ ! -f "$STYLES_DIR/$s.yaml" ]; then
    echo "style not found: $s (referenced by figure '$fid'; looked in $STYLES_DIR)" >&2; exit 1
  fi
  printf '%s' "$s"
}

# 構造化プロンプトを stdout へ
emit_prompt() { # emit_prompt <kind> <intent> <prompt> <style> <abs_path>
  local kind="$1" intent="$2" prompt="$3" sname="$4" abs="$5"
  printf '%s\n\n' '$imagegen 次の仕様で画像を1枚だけ生成し、指定の保存先に保存してください。'
  printf '## 図\nkind: %s\nintent: %s\n内容:\n' "$kind" "$intent"
  printf '%s\n' "$prompt" | sed 's/^/  /'
  if [ -n "$sname" ]; then
    printf '\n## スタイル(%s)\n' "$sname"
    yq 'del(.name)' "$STYLES_DIR/$sname.yaml"
  fi
  printf '\n## 出力\n保存先: %s に保存する。\n' "$abs"
  printf '\n## 厳守(画像生成のみ)\n'
  printf '%s\n' '- 行うのは $imagegen による画像生成だけ。生成した画像を保存先に保存したら終了する。'
  printf '%s\n' '- 生成後に、コード作成・SVG作成・PNG変換・画像編集・ファイル編集などの後処理は一切しない。'
  printf '%s\n' '- 既存の他ファイルは変更しない。出力は1枚の画像のみ。'
}

i=0
while [ "$i" -le "$n" ]; do
  doc="$(printf '%s' "$ystream" | yq "select(di == $i)")"; i=$((i + 1))
  id="$(printf '%s' "$doc" | yq '.id')"
  [ -n "$id" ] && [ "$id" != "null" ] || continue
  style="$(printf '%s' "$doc" | yq '.style // ""')"
  s="$(resolve_style "$style" "$id")" || exit 1

  case "$MODE" in
    list)
      printf '%s\t%s\t%s\n' "$id" "figures/$id.png" "$s"
      ;;
    plan)
      abs="$ARTICLE/figures/$id.png"
      { [ -f "$abs" ] && [ "$FORCE" -eq 0 ]; } && continue
      printf '%s\t%s\n' "$id" "$abs"
      ;;
    prompt)
      [ "$id" = "$PROMPT_ID" ] || continue
      kind="$(printf '%s' "$doc" | yq '.kind // ""')"
      intent="$(printf '%s' "$doc" | yq '.intent // ""')"
      prompt="$(printf '%s' "$doc" | yq '.prompt // ""')"
      emit_prompt "$kind" "$intent" "$prompt" "$s" "$ARTICLE/figures/$id.png"
      exit 0
      ;;
  esac
done

[ "$MODE" = "prompt" ] && { echo "figure not found: $PROMPT_ID" >&2; exit 1; }
exit 0
