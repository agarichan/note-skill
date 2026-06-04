# note-skill

note.com 向け記事執筆〜投稿パイプラインの Agent Skill 一式。

## 内容

- `skills/note-writing` — 構成設計 → 下書き → note記法整形(step1)
- `skills/note-editor` — 辛口レビュー(writing の品質ループ)
- `skills/note-figures` — 図メタ → 画像生成(step2)
- `skills/note-publish` — note.com への投稿(step3)
- `templates/` — 新規プロジェクトの種(styles/ と personas/ の汎用見本)
- `docs/SPEC.md` — パイプライン全体の正式仕様

## セットアップ

`~/.claude/skills/` から各スキルへシンボリックリンクを貼る:

```sh
ln -s ~/work/note-skill/skills/note-writing  ~/.claude/skills/note-writing
ln -s ~/work/note-skill/skills/note-editor   ~/.claude/skills/note-editor
ln -s ~/work/note-skill/skills/note-figures  ~/.claude/skills/note-figures
ln -s ~/work/note-skill/skills/note-publish  ~/.claude/skills/note-publish
```

## 新規プロジェクトの作り方

任意の作業ディレクトリで:

```sh
mkdir my-notes && cd my-notes
cp -r ~/work/note-skill/templates/styles   .
cp -r ~/work/note-skill/templates/personas .
mkdir articles
```

`personas/example.yaml` を自分の声に書き換え、`styles/` に新スタイルを追加して育てる。
詳しい仕様は `docs/SPEC.md`。
