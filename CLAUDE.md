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

- `skills/note-writing/templates/styles/` — 画像スタイルの汎用見本(note-writing が初期化時に使う)。
- `skills/note-writing/templates/personas/` — 書き手の個性(声・人格)の汎用見本。同上。

実物の `styles/<名>.yaml` / `personas/<名>.yaml` は **コンテンツリポ(作業ディレクトリ直下)**に置く。
スキルは作業ディレクトリ直下を名前解決する。未初期化のディレクトリで note-writing が起動した場合、
**確認の上で内蔵 templates から自動初期化**する(SKILL.md ワークフロー手順0)。

## 改善ループの向け先(重要)

スキル本体(SKILL.md / references / templates)は **機能する枠組み・普遍原則だけ**を置き、配布物として安定させる。
リビング(育つ部分)は **コンテンツ側の persona / style** に集約する。

- editor の findings で繰り返し出る粗 → persona の `避ける言い回し` / `編集観点` / `画像審美` か該当 style YAML に反映する提案を出す。
- **スキル本体への反映は、書き手・記事ジャンルが変わっても効く普遍と確信できる場合のみ**、ユーザーに「スキルに記載しますか?」と確認してから編集する。
- 個人の好み・特定ジャンルでだけ効くもの・記事ごとに揺れる感じ方はスキル本体に入れず persona / style へ。
