---
name: note-figures
description: >
  note記事の図メタ(draft.md の `<!-- figure: ... -->` ブロック)を、実際の画像 PNG に変換するスキル。
  Codex CLI(gpt-image-2)で生成し、`articles/<slug>/figures/<id>.png` に保存する。サムネ(見出し画像)も生成。
  Use when ユーザーが note記事の図・サムネを画像化したい / 図メタから画像を生成したい / figures を作りたい
  / 「記事の画像を出して」「サムネ作って」と言ったとき。note-writing(本文+図メタ作成)の次工程(step2)。
  名前付きスタイル(リポ直下 styles/)で見た目を揃える。
metadata:
  pipeline: "note-writing(step1) → note-figures(step2: 画像生成) → note-publish(step3: 投稿)"
---

# note-figures: 図メタ → 画像生成

> 実体は `~/work/note/skills/note-figures`(グローバルリンク)。追記・修正はそこを編集。
> このスキルへ盛り込むべき指摘が出たら、勝手に書かずユーザーに記載可否を尋ねる。

note-writing が作った図メタを、Codex CLI(gpt-image-2)で画像化する。**決定的にプロンプトを確定し、codex は生成のみ**担う。

## 前提

- Codex CLI が画像生成可能(gpt-image-2 が既定)。`codex` にログイン済みであること。
- 自動実行には `~/.codex/config.toml` の `approval_policy = "never"` / `sandbox_mode = "danger-full-access"` 推奨
  (承認待ちなしで codex exec が動く)。画像生成は **codex の利用枠を消費**する。
- **`yq`(mikefarah版)が必要**(YAML解析に使用。`mise use -g yq` 等)。図メタ/スタイルの複数行 `prompt`(`|`/`>`)も扱える。

## 成果物

`articles/<slug>/figures/<id>.png` — draft.md の各図メタ `id`(`thumbnail` 含む)に対応。

## 使い方(Agent が実行する手順)

1. **プレビュー(任意)**: 全 figure の解決結果を確認(codex枠を使わない)
   `bash skills/note-figures/scripts/render.sh articles/<slug> --list`
2. **計画を出す**: 未生成 figure を取得(`--force` で全 figure)。各行は `id<TAB>絶対パス<TAB>最終プロンプト`。
   `bash skills/note-figures/scripts/render.sh articles/<slug>`
3. **生成(バックグラウンドで最大8並列)**: 計画の各行について、Agent は codex を **Bash の
   `run_in_background` でバックグラウンド実行**する。**同時に最大8件**まで起動する。
   `codex exec -C <repo> --skip-git-repo-check "$imagegen <最終プロンプト>。生成した画像を <絶対パス> に保存して。既存の他ファイルは変更しない。"`
4. **完了ごとに目視チェック(報告のため・自動修正はしない)**: タスク完了通知ごとに `<絶対パス>` の画像を
   **Read で開いて確認**し、その figure の `intent` / `prompt`(draft.md)と照らして意図通りか見る。
   - 問題なし → OK。残りの計画があれば新たに1件起動(常に最大8件を維持)。
   - 問題ありそう(意図とズレ / 画像なし / 破綻 / **note本文幅(1行=全角約34文字)で文字が読めない=横長で字が潰れている** など)
     → **その id と気になった点を控える**(この場では直さない)。
   - 全件完了後、**問題のありそうな箇所をまとめてユーザーに報告**する。再生成や prompt・スタイル調整は
     ユーザーの判断を待ってから行う(ガチャなので最終判断は人に委ねる)。

- 計画が空なら生成済み。作り直しは `--force`。
- styles の既定は `articles/../../styles`(= リポ直下 `styles/`)。`--styles-dir DIR` で変更可。

## 仕組み(役割分担)

- **render.sh(決定的・codex を呼ばない)**: frontmatter `image_style` と各 figure の `style`/`prompt` を yq で解決し、
  `figure.prompt` + `style.prompt断片` を平坦化して最終プロンプトを確定。未生成分(または `--force` で全部)を**計画**として出力。
- **Agent(スキル実行者)**: 計画を受け取り `codex exec`(`$imagegen`, gpt-image-2)を**バックグラウンドで最大8並列**実行→保存→**完了ごとに目視チェックし、問題のありそうな箇所をまとめてユーザーへ報告**(自動修正はしない)。
- この分離で、プロンプトは再現可能・レビュー可能、生成は並列で高速。codex を呼ぶのは Agent 側に一本化。

## 注意

- スタイル名が `styles/` に無ければ render.sh が**エラー**(誤字検出)。先に `--list` で潰す。
- 並列は**最大8件**まで。増やすと codex のレート制限・1日上限に当たりやすい。
- codex の画像生成は**ガチャ**。気に入らなければ `--force` か、`prompt`/スタイル(styles/)を調整して再生成。
- "AIっぽさ"を避ける指針・スタイルの育て方は note-writing の `references/image-styles.md`。

## テスト

`bash skills/note-figures/tests/test_render.sh`(codex を呼ばない計画ロジック=抽出・スタイル解決・冪等・--force を検証)。
