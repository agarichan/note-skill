# note-editor findings ログ

editor がレビューで出した指摘を1行ずつ追記する。category キーで横断集計し、昇格/降格/蒸留の判定元にする。

- **追記形式**: `| YYYY-MM-DD | <slug> | <category> | <severity> | <一言> |`
- category キーは `references/editor-rubric.md` の一覧から選ぶ(新規は慎重に)。
- severity は `重大` / `中` / `軽`。
- **昇格候補**: 同一 category が異なる3記事以上 かつ 最大 severity ≥ 中 → writing-craft.md へ端的なルールを追加/強化(提案)。
- **降格候補**: writing-craft.md のあるルールが直近5記事で1度も指摘の主題にならない → editor-rubric.md へ移動(削除しない)(提案)。
- **蒸留候補**: writing 側に重複・冗長があれば短い言い回しに統合(提案)。
- 適用はすべて**提案 → 承認**。スキル本体は勝手に書き換えない。

| 日付 | slug | category | severity | 一言 |
|---|---|---|---|---|
| 2026-05-31 | portless-dev-real-cert | reader-mismatch | 中 | 前提(portless/Tailscale/Caddy)が冒頭で説明されず、読者の知識差で離脱 |
| 2026-05-31 | portless-dev-real-cert | spec-violation | 中 | 環境ブロックの引用 > が複数行で、URL風文字列やコード語が引用内に混在 |
| 2026-05-31 | portless-dev-real-cert | long-sentence | 中 | Caddy節・X-Forwarded-Host節に一文が長く修飾の多い文が複数 |
| 2026-05-31 | portless-dev-real-cert | should-be-image | 中 | portlessとは何かの初出説明が文章のみで、未知ツール前提の図がない |
| 2026-05-31 | portless-dev-real-cert | weak-ending | 軽 | まとめが箇条書き再掲中心で、二段構えの思想の余韻が薄い |
| 2026-05-31 | portless-dev-real-cert | title-vague | 軽 | タイトルが長く要素過多で一覧で頭に入りにくい |
| 2026-05-31 | portless-dev-real-cert | bold-missing | 軽 | ハマりどころ早見表の前後で太字のキーワード化が一部薄い |
