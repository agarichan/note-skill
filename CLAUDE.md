# このリポジトリについて

note.com 向け執筆〜投稿パイプラインの Agent Skill 一式。
**ここはスキル開発リポ**。記事コンテンツは別リポ(`~/work/note`)に置く。

## スキル

`~/.claude/skills/` から各スキルへシンボリックリンクを貼って利用する(セットアップは README.md)。

工程(詳細は `docs/SPEC.md`):

1. **note-writing**(step1) — 構成設計 → 下書き → note記法整形。本文 md + 図メタを作る。
   仕上げに note-editor で品質レビューループ(重大・中ゼロまで)。
2. **note-editor** — 独立コンテキスト(サブエージェント)で記事を辛口レビュー。指摘を重要度つきで
   `findings-log.md` に蓄積し、頻発分を note-writing へ昇格(提案)。
3. **note-figures**(step2) — 図メタ → 画像生成(Codex / gpt-image-2)。サムネも。
4. **note-publish**(step3) — draft.md + figures を note.com へ投稿(下書き保存/公開)。

## 横断資産

- `templates/styles/` — 画像スタイルの汎用見本。新規プロジェクトはここからコピー。
- `templates/personas/` — 書き手の個性(声・人格)の汎用見本。同上。

実物の `styles/<名>.yaml` / `personas/<名>.yaml` は **コンテンツリポ(作業ディレクトリ直下)**に置く。
スキルは作業ディレクトリ直下を名前解決する。

## スキルへの反映ルール

作業中に得た指摘・修正・知見で、関連スキル(SKILL.md / references / templates 等)に
**恒久的に盛り込むべきだと感じたら、勝手に書かず、まず「スキルに記載しますか?」とユーザーに尋ねる**。
ユーザーが可とした場合のみ編集する。
