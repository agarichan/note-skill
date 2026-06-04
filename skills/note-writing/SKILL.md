---
name: note-writing
description: >
  note.com 向けの技術・開発記事を、テーマやメモから「構成設計 → ゼロからの下書き生成 → note記法への整形」まで
  一気通貫で書くためのスキル。成果物は本文の Markdown と、図を入れたい箇所に埋め込む「図メタ情報」。
  Use when ユーザーが note(note.com)に載せる記事・本文を書く / 下書きする / 見出し構成を考える / note向けに整形する
  / 読まれる文章にしたい、といった依頼をしたとき。媒体名を明示しなくても、このリポジトリで外部公開向けの
  解説記事・ブログ本文を書く文脈なら適用する。note の仕様(見出しはH2/H3のみ・表は非対応・数式$$対応 等)に
  合わせた整形もこのスキルで行う。
metadata:
  living: "writing-craft と note-spec は使いながら知見を貯めて育てる前提"
---

# note 記事執筆

> 実体は `~/work/note/skills/note-writing`(グローバルリンク)。追記・修正はそこを編集。盛り込むべき指摘が出たら勝手に書かずユーザーに記載可否を尋ねる。

技術・開発系の note 記事を構成設計から note記法整形まで通して書く。**核は「本文md + 図メタ」まで**(画像の実生成・note投稿は範囲外)。

## 成果物

```
articles/<slug>/
  draft.md      # note記法に整形した本文。図の箇所に図メタブロックを埋め込む
  figures/      # 後で生成画像を置く場所(最初は空でよい)
```
`<slug>` は記事内容を表す英小文字ケバブ(日付は付けない)。
エクスプローラーの並びは `.vscode/settings.json` の `explorer.sortOrder: "modified"` で更新日時降順(最近編集した記事が上)。

## frontmatter(管理用メタデータ)

`draft.md` の冒頭に YAML frontmatter を置く。**これは執筆・管理用**で note は解釈しない
→ note エディタへ貼る時は frontmatter を外す(本文だけ貼る)。`title` は note のタイトル欄、`tags` はハッシュタグに使う。

```yaml
---
title: 記事のタイトル          # note のタイトル欄に入れる
slug: my-article             # ディレクトリ名と一致
status: draft                # draft / ready / published
paid: false                 # 有料記事なら true
price:                       # 有料時のみ円で(例: 500)。無料は空
tags: []                     # note のハッシュタグ(例: [Python, 確率])
image_style:                 # 既定の画像スタイル名 = styles/<名前>.yaml。例: flat-diagram
persona:                     # 書き手の個性名 = personas/<名前>.yaml。無指定なら asagiri。例: asagiri
summary:                     # 一文要約(導入の核・SNS用)
created: 2026-05-30          # 作成日(YYYY-MM-DD)
url:                         # 公開後の note 記事 URL
---
```

## ワークフロー

0. **初期化チェック** — 設計に入る前に、**作業ディレクトリ直下**に `articles/` `styles/` `personas/` があるか確認する。
   いずれかが欠けていれば、**ユーザーに「ここで初期化していいですか?」と確認してから**、本スキルの内蔵テンプレで初期化する。
   ホームディレクトリ等で誤実行すると事故るので、**確認は省略しない**。承認後に次を実行:
   ```sh
   # スキル本体のディレクトリから内蔵 templates を参照(SKILL.md と同じ階層の templates/)
   SKILL_DIR=$(cd "$(dirname "$(readlink -f ~/.claude/skills/note-writing/SKILL.md)")" && pwd)
   mkdir -p articles
   [ ! -d styles ]   && cp -r "$SKILL_DIR/templates/styles"   .
   [ ! -d personas ] && cp -r "$SKILL_DIR/templates/personas" .
   ```
   ユーザーが拒否した場合はそのまま次へ進む(後段の `styles`/`persona` 名前解決で失敗が出る可能性は受け入れる)。
   既に揃っていればスキップ。

1. **設計を詰める** — 読者・狙い・想定の長さ・記事の型、そして **無料 / 有料(有料なら価格と有料ラインの方針)**
   を対話で確定する。質問は AskUserQuestion を使う。記事の型・読まれる構成・有料部分の設計は
   **references/writing-craft.md** を参照(都度ここを読む)。有料記事の仕組みは references/note-spec.md。
   **書き手の声(個性)は frontmatter `persona:` で指定し `personas/<名前>.yaml` を都度読む**(無指定なら asagiri)。仕組みは references/personas.md。
2. **構成・見出し設計 → ここで合意を取る(重要)** — H2/H3 だけで骨子を組み、**記事の芯(一言の主張)と全体構成を
   ユーザーに提示して明示的に合意してから次へ進む**。見出しを並べただけで筋が通るか確認する。
   ⚠️ ここを飛ばして本文を書き出すと、後で「芯がズレている/重みづけが違う(主役にすべきが脇役になっている)」と判明し、
   **全面的な手戻り**になりやすい。芯と構成の合意は本文より先。迷ったら AskUserQuestion で構成案を出して選んでもらう。
3. **ゼロ下書き** — 合意した構成に沿って各節を本文化。導入(掴み)と締め(次の行動)を特に丁寧に。writing-craft の原則に従う。
4. **note記法へ整形** — **references/note-spec.md** の制約に合わせる(見出し階層・太字の落とし穴・表の代替・数式など)。
   - **インラインコード(`` `code` ``)は使用禁止**(note 非対応。バッククォートが literal で残る)。
     コードはコードブロック(` ``` `)にまとめ、文中で短く示したい語はそのままのテキスト/「」で表す。
5. **図メタ付与** — まず本文先頭に **サムネ(`figure: thumbnail`)を必ず置く**(必須)。続けて図が要る位置に figure ブロックを埋め込む。
6. **有料ライン**(有料記事のみ) — 有料開始位置に `<!-- paywall: ここから有料 -->` を1行で置く(note でここに有料ライン設定。無料部分で購入動機が立つか確認)。
7. **保存** — `articles/<slug>/draft.md` に書き出す。冒頭に frontmatter(上記)を付け、`title`/`paid`/`price`/`tags` 等を埋める。
8. **品質レビュー(note-editor)** — 保存済み draft.md を **note-editor スキルにサブエージェントとして渡し**
   (`articles/<slug>/draft.md` のパスを明示)、辛口レビューさせる。**重大・中の指摘を直して保存し直し → 再レビュー**を
   重大・中ゼロまで(上限3周)。残った軽微指摘はユーザーに報告。note-editor が出す**昇格/降格/蒸留の提案**も伝える
   (適用は承認後)。細かい文章テクニックは writing 側に持たず、この**レビューループで底上げ**する。

各ステップ後に方向を確認し、勝手に全部進めない。下書きは一気に出すより、構成合意 → 本文の順で進める。

## 図メタブロック(ツール非依存)

図を入れたい位置に、本文中へ HTML コメントで埋め込む。下流の画像生成・投稿が機械的に拾える形:

```
<!-- figure: fig1
kind: 概念図            # 図解 / グラフ / スクショ / 概念図 / シーケンス など
intent: 何を一目で伝える図か(1行)
prompt: |              # 画像生成に渡す説明(日本語・ツール非依存)。複数行で詳細に書いてよい
  AからBへの変換フロー…
style: flat-diagram     # 任意。styles/<名前>。無指定なら frontmatter の image_style を使う
alt:  代替テキスト
-->

![代替テキスト](figures/fig1.png)
```

`-->` の直後に **`![alt](figures/<id>.png)` を必ず置く**(VSCode md プレビュー用)。**サムネ(`thumbnail`)も含め全 figure で置く**。未生成のうちは壊れ画像=「ここに図」の目印。有無に関わらず置く。

- `fig1` のような一意IDを振る。生成画像は `figures/fig1.png` に対応させる想定。
- `style` は名前付きスタイル= **リポ直下 `styles/<名前>.yaml`**(仕組みは references/image-styles.md)。無指定なら
  frontmatter の `image_style` が既定。サムネと本文図を同名にすると統一感。`prompt断片` は figure の `prompt` に連結。
- コードで描ける図(構造図・フロー)は `prompt` の代わりに `mermaid:`/`plantuml:` を持たせてもよい(note では最終的に画像化が要る旨を intent に残す)。
- 表は note ネイティブ非対応。表を出したい時もこの figure ブロックで「画像化」を選ぶのが基本(代替は note-spec.md)。
- **サムネ(見出し画像)は全記事で必須**。frontmatter 直後・本文の先頭に `figure: thumbnail`(`kind: 見出し画像`)を
  必ず1つ置き、**その直後に `![alt](figures/thumbnail.png)` も置く**(本文トップに表示され VSCode プレビューで見やすい)。
  この本文トップのサムネ参照は **note-publish(step3)が投稿時に自動で剥がし、note の見出し画像として設定する**ので、
  本文に二重で挿入されることはない。推奨サイズ等は note-spec.md。省略不可 — サムネ無しで記事を完成扱いにしない。
- **note投稿時の整理**: 図メタ(HTMLコメント)とローカル画像参照 `![]()` は外し、画像を note にアップロードして
  該当位置に挿入する。サムネ(`figures/thumbnail.png`)は本文ではなく note の**見出し画像**として設定する。

## 参照ファイル

- **references/note-spec.md** — note の仕様。執筆に効く要点だけ。整形時に必ず参照。
- **references/writing-craft.md** — 読まれる記事の構成・文章術。**使いながら育てるリビング文書**。
  良い/悪いと感じた書き方の知見が出たら、ここに追記してスキルを伸ばす。
- **references/image-styles.md** — 名前付き画像スタイルの仕組み・スキーマ・AIっぽさ回避・育て方のガイド。
  スタイル実体は **リポ直下 `styles/<名前>.yaml`**(`style` / `image_style` の参照先。増やして育てる)。
- **references/personas.md** — 書き手の個性(声・人格)の仕組み・スキーマ・育て方のガイド。
  個性の実体は **リポ直下 `personas/<名前>.yaml`**(`persona` の参照先。無指定は asagiri)。一般原則(writing-craft)と分離して扱う。
