# note-skill 正式仕様

note.com 向け技術・開発記事の執筆 〜 投稿パイプラインを実現する Agent Skill 群の仕様。
このドキュメント1枚で全体像を述べる。実装の細部は各スキル(`skills/<名>/`)の SKILL.md と
references を参照すること。

最終更新: 2026-06-04(分離初版)。

## 1. 目的とパイプライン

ユーザーの「テーマ・メモ」から、note.com で読まれる記事に至るまでを 3 工程 + 品質ループで実現する。

```
[step1] note-writing  構成設計 → 下書き → note記法整形(本文 md + 図メタ)
   ├─ ループ: note-editor で辛口レビュー(重大・中ゼロまで、上限3周)
[step2] note-figures  図メタ → 画像生成(Codex / gpt-image-2)・サムネ
[step3] note-publish  draft.md + figures → note.com 投稿(下書き/公開)
```

- step1 の成果物は `articles/<slug>/draft.md`(frontmatter 付き)+ `articles/<slug>/figures/`(空でよい)。
- editor は writing からサブエージェントとして起動され、独立コンテキストで動く。

## 2. 記事ディレクトリ規約

```
articles/<slug>/
  draft.md      # note記法に整形した本文 + frontmatter(管理用)
  figures/      # 生成画像置き場
```

`<slug>` は記事内容を表す英小文字ケバブ(日付は付けない)。

### frontmatter(管理用)

draft.md 冒頭に YAML frontmatter を置く。note は解釈しない(投稿時に剥がす)。

```yaml
---
title: 記事のタイトル          # note のタイトル欄
slug: my-article             # ディレクトリ名と一致
status: draft                # draft / ready / published
paid: false                  # 有料記事なら true
price:                       # 有料時のみ円で(例: 500)
tags: []                     # note のハッシュタグ
image_style:                 # 既定の画像スタイル名 = styles/<名>.yaml
persona:                     # 書き手の個性名 = personas/<名>.yaml。無指定なら既定 persona
summary:                     # 一文要約(導入の核・SNS用)
created: YYYY-MM-DD          # 作成日
url:                         # 公開後の note 記事 URL
---
```

### 図メタブロック

本文中に HTML コメントで図の意図を埋め込む(下流の note-figures が機械的に拾う)。

```
<!-- figure: fig1
kind: 概念図
intent: 何を一目で伝える図か(1行)
prompt: |
  画像生成へ渡す説明(日本語・ツール非依存)
style: example-flat          # 任意。styles/<名>。無指定なら frontmatter の image_style
alt:  代替テキスト
-->
![代替テキスト](figures/fig1.png)
```

`-->` の直後に `![alt](figures/<id>.png)` を必ず置く(VSCode md プレビュー用)。サムネ
(`figure: thumbnail`)は全記事必須で、本文先頭に置く(note 投稿時に note-publish が剥がして
note の「見出し画像」として設定する)。

## 3. 横断資産

スキルは**作業ディレクトリ直下**の `styles/<名>.yaml` / `personas/<名>.yaml` を名前解決する。
未初期化の作業ディレクトリで note-writing を起動すると、**確認の上で**内蔵テンプレ
(`skills/note-writing/templates/{styles,personas}/`)から `articles/`・`styles/`・`personas/` を自動生成する
(SKILL.md ワークフロー手順0)。

### 3.1 persona(書き手の個性)

`personas/<名>.yaml` は**書き手の声・人格**を定義する。frontmatter `persona:` で名前参照。
note-writing(執筆)と note-editor(レビュー)が**同じファイルを源泉に**参照する(単一源泉)。
無指定なら既定 persona(プロジェクト側で命名。本リポの見本は `example`)。

線引き:

> **persona** = "どう聞こえるか"(声・調子・温度・人称・敬体・好む/避ける言い回し・時制スタンス・距離感)
> **一般原則** = "機能するか"(芯・構造・読者設計・スマホ・視覚設計・図・note仕様)

AIっぽさ回避は、**狩る手順・機構は editor-rubric.md** に、**何がクサい/canned か・温度の好みは persona** に
置く(機構は誰でも同じ、中身は人それぞれ)。スキーマと育て方の詳細は
`skills/note-writing/references/personas.md`。

persona は声だけでなく **画像審美**(避ける画風・逃げ場・方向)も持つ。文章の声と同様、「何が AI っぽく感じるか」は
書き手の主観なので persona 側に置く。image-styles.md(機能する画像原則)とは別の源泉として、note-figures が
プロンプト方針に反映する。

### 3.2 image_style(画像スタイル)

`styles/<名>.yaml` は**画像の見た目**を定義する。frontmatter `image_style:` で記事全体の既定を、
figure ごとに `style:` で上書きできる。スキーマ:

```yaml
name:
用途:
トーン:
配色: { ベース, 文字, アクセント }   # hex で明示(放置すると黄ばむ)
タイポ:
形式:                                # フラット/線画/写真 を1つに固定
余白構図:
サイズ:                              # 本文図=縦長〜正方形 / サムネ=横長16:9
prompt断片:
```

詳細(本文幅 620px・サムネ 1280×670・AIっぽさ回避・キャラ画風固定の指針)は
`skills/note-writing/references/image-styles.md`。

## 4. スキル仕様

### 4.1 note-writing(step1)

- **目的**: テーマ/メモから「本文 md + 図メタ」までを一気通貫で作る。
- **入力**: ユーザーのテーマ・要件(対話で確定)・既存記事や知見。
- **出力**: `articles/<slug>/draft.md`(frontmatter 付き)+ 空の `figures/`。
- **ワークフロー**: 設計 → **構成・見出し合意ゲート(重要)** → ゼロ下書き → note記法整形 →
  図メタ付与(サムネ必須)→ 有料ライン(有料記事) → 保存 → editor 品質ループ。
- **依存**: `references/writing-craft.md`(一般原則)・`references/note-spec.md`(note 仕様)・
  `references/personas.md`(個性の仕組み)・`references/image-styles.md`(画像の仕組み)・
  作業ディレクトリ直下の `personas/`・`styles/`。

### 4.2 note-editor

- **目的**: writing の品質ループ。読まれやすさ・構成・タイトル・文体・読者体験・note 仕様順守を点検し、
  指摘を**構造化 findings**(category/severity/箇所/問題/改善案)で返す。
- **入力**: `articles/<slug>/draft.md` のパス(独立コンテキストで起動されるため明示渡し)。
- **出力**: findings(重大/中/軽)+ 総合判定 + `findings-log.md` への1行追記。重大・中ゼロで合格。
- **依存**: `references/editor-rubric.md`(観点11 + category キー + severity 目安)・
  `references/review-output.md`(出力体裁)・対象 draft.md の `persona` を読み込む。
- **重要**: 文体・声の点検は **persona を「守るべき声」の基準**として行う(汎用の良し悪しではない)。

### 4.3 note-figures(step2)

- **目的**: draft.md の `<!-- figure: ... -->` ブロックを実画像 PNG に変換する。サムネも生成。
- **入力**: `articles/<slug>/draft.md`、`styles/<名>.yaml`(名前解決)、Codex CLI(gpt-image-2)。
- **出力**: `articles/<slug>/figures/<id>.png`。
- **依存**: `scripts/render.sh`、作業ディレクトリ直下の `styles/`。

### 4.4 note-publish(step3)

- **目的**: 仕上がった `articles/<slug>` を note.com に投稿(下書き保存 既定 / 公開)。
- **処理**: 決定的整形(`prepublish.sh`)で frontmatter・図メタを剥がして投稿用 `body.md` + `plan.json` を作り、
  Playwright(`note.mjs`)で note エディタへ流し込む。サムネは note の見出し画像として設定。
- **入力**: `articles/<slug>/draft.md` と `figures/`。
- **出力**: note 上の記事(下書き or 公開)。`.publish/` に中間成果物。
- **依存**: Node.js(Playwright)、note.com への対話的認証(初回)。

## 5. note 仕様の要約

- 見出しは H2/H3 のみ。
- 表はネイティブ非対応 → 画像化(figure ブロック)で扱う。
- 数式は `$$...$$`(`$...$` インラインは不可)。
- インラインコード `` `code` `` は使用不可(literal で残る)→ コードブロックで囲み、文中は「」で示す。
- 見出し画像は note 側で別途設定(本文には埋め込まれない)。

完全な仕様は各記事執筆時に `skills/note-writing/references/note-spec.md` を参照する。

## 6. 拡張のしかた

- **新 persona**: `personas/<名>.yaml` を1つ足す。frontmatter `persona: <名>` で参照。
- **新 style**: `styles/<名>.yaml` を1つ足す。frontmatter `image_style: <名>` または figure 単位 `style:`。
- **見本の更新**: `skills/note-writing/templates/` の example.yaml を改修してプロジェクト共通の出発点を育てる。
- **編集ルブリックの育成**: editor で同じ指摘が頻発したら、`editor-rubric.md` を育てて writing 側へ昇格、
  使われなくなれば降格、重複は蒸留(提案 → 承認で適用)。
