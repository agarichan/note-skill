---
name: note-publish
description: >
  note-writing(本文+図メタ)→ note-figures(画像生成)で仕上げた articles/<slug> を、
  note.com へ自動投稿するスキル(step3)。決定的整形(prepublish.sh)で投稿用 body.md + plan.json を作り、
  Playwright(note.mjs)で note エディタに流し込んで下書き保存(既定)/公開する。
  Use when ユーザーが note に記事を投稿したい / 下書きを作りたい / 既存記事を draft.md の内容で更新したい
  / 「note に上げて」「下書き作って」と言ったとき。note-figures(step2)の次工程。
metadata:
  pipeline: "note-writing(step1) → note-figures(step2) → note-publish(step3: 投稿)"
---

# note-publish: 投稿用整形 → note へ投稿

> 実体は `~/work/note/skills/note-publish`(グローバルリンク)。追記・修正はそこを編集。
> 盛り込むべき指摘が出たら、勝手に書かずユーザーに記載可否を尋ねる。

draft.md + figures を note.com へ投稿する。**決定的な整形はスクリプト、崩れやすい実機操作は agent が
状態を見て調整**(待ち・再試行・セレクタずれ対応・目視確認)する。**既定は下書き保存(save_draft)**。

## 前提

- 初回は `node skills/note-publish/scripts/note.mjs login` で note.com に手動ログイン
  → セッションを `~/.note-state.json`(env `NOTE_PUBLISH_STATE` で変更可)に保存。失効したら再ログイン。
- `node`(mise管理)+ Playwright。`skills/note-publish` で `npm install && npm run install-browser` 済みであること。
- `yq`(mikefarah)が必要(prepublish.sh の YAML 解析)。

## 成果物

- `articles/<slug>/.publish/body.md` … 投稿用本文(frontmatter・図メタ・サムネ参照を除去)
- `articles/<slug>/.publish/plan.json` … 投稿計画(title/tags/thumbnail/images/paywall/paid/target/warnings)
- `articles/<slug>/.publish/shots/` … 投稿時のスクリーンショット(目視確認用)

## 使い方(Agent が実行する手順)

1. **事前点検**: `bash skills/note-publish/scripts/prepublish.sh articles/<slug> --check`
   計画と**警告**(画像未生成 / サムネ無し / 数式・表など崩れやすい要素 / paid:true は価格手動)を
   ユーザーに提示する。画像未生成・サムネ無しなど致命的なら前工程(note-writing / note-figures)へ戻す。
2. **ログイン**(初回 / 失効時のみ): `node skills/note-publish/scripts/note.mjs login`
3. **下書き投稿(既定)**: `node skills/note-publish/scripts/note.mjs draft --plan articles/<slug>/.publish/plan.json`
   投稿中、agent は状態を観察し、待ち・再試行・セレクタずれに**多少の調整**をしてよい(壊れたら shots/ を確認)。
   - タグは下書き段では付かない(公開時に設定)。
   - **新規作成した記事の URL は draft.md の frontmatter `url:` に自動で書き戻される**。以後その記事は
     全置換の再同期対象になり、1記事=1下書きを上書きし続けられる(`/notes/new` を毎回開いて下書きが
     増えることを防ぐ)。**反映には prepublish.sh の再実行が必要**(plan.json の target を更新するため)。
4. **確認 → 報告**: `articles/<slug>/.publish/shots/draft.png` を **Read で目視確認**し、draft.md の意図と照らす。
   気になる点(崩れ・画像ズレ等)を**まとめてユーザーに報告**。
5. **公開**(ユーザー判断後のみ): `node skills/note-publish/scripts/note.mjs publish --plan ...`
   公開後の URL も同様に frontmatter `url:` へ自動書き戻し(以後その記事は **target=全置換の再同期**対象)。

## 既存記事の更新(全置換の再同期)

frontmatter `url` が入っている記事(初回の draft/publish 後は自動で入る)は、`draft`/`publish` 時に
その記事をエディタで開き、**本文を全選択削除してから流し込み直す**(全置換)。部分修正(変更箇所だけの
編集)は非対応。note 上で軽微に直したい場合は note 側で直接編集する。
- 再同期では**カバー画像(見出し画像)は据え置き**(本文だけ差し替え)。サムネを作り直しても更新されない
  ため、その場合は note 上で手動で差し替える(`setThumbnail` は既存カバーありだと best-effort で無害にスキップ)。

## 有料記事

実機確認の結果、note の有料エリア(「ここから先は有料」)はエディタ内インライン区切りでは
安定して自動化できなかった。現状の挙動:
- `<!-- paywall -->`(body の `@@PAYWALL@@`)位置では**本文に何も挿入せず警告だけ**(literal 残りなし)。
- `paid: true` でも公開フローでは**無料のまま投稿**し、「有料/価格/有料エリアは手動」と警告する。

有料記事は **note 上で 有料/価格/有料エリアを手動設定**するのが前提。

## エディタ投入の仕様(note.mjs / 実機確認 2026-05-31)

note の ProseMirror エディタには癖があり、`typeBody` はこれに合わせて Markdown を再現する。詳細は
`note.mjs` のコメントに集約。要点だけ:

- **ブロック分割は Enter が2回必要**。1回だと段落が融合し、見出し/リストの変換も起きない。そのため
  Markdown のブロック間空行は捨て、**直前ブロックの種別で Enter 回数を変える**(空段落を作らない):
  段落/リスト終端/コード終端=×2、見出し=×1、HR=×0(直後の自動空段落に書く)、リスト項目どうし=×1。
- **コードフェンス**は ` ``` `(言語識別子は中身に混入するので**除去**)で入り、行内は Enter×1、閉じ
  ` ``` ` は打たず次ブロックの区切りで抜ける。
- **本文画像**は空行の「＋(メニューを開く)」→「画像」で**即 file chooser**(中間メニュー・トリミング無し)。
  挿入は **前=Enter×0(直前ブロック末尾でそのまま)/後=Enter×1(キャプション欄から下の新ブロックへ抜ける)**
  にしないと、図の上下に空段落が残る・後続テキストがキャプションに吸われる。
- **見出し画像(アイキャッチ)**は本文画像と別フロー: 上部「画像を追加」→ メニュー「画像をアップロード」→
  file chooser →**トリミング「保存」で確定**。新規作成時のみ設定し、見つからなければ best-effort でスキップ。
- **引用(`> `)**は `<figure class=blockquote>`。複数行は継続行を Enter×1 + 本文(`> ` を打たない)で1ブロックに。
  **出典**は `<!-- cite: ... -->`(prepublish が `@@CITE:...@@` に変換)→ 引用直後のみ、ArrowDown で出典欄
  (figcaption)へ記入し、Enter×2 で抜ける。引用直後でない `@@CITE@@` は無視(prepublish が警告)。

## 注意 / 既知のリスク

- **下書きは「下書き保存」を押さない限り残らない**。`note.mjs draft/publish` は最後に必ず `下書き保存`
  (または公開)を踏むので保存されるが、調査・プローブ等で `/notes/new` を開いて打ち込んだだけ・
  保存せずブラウザを閉じたものは note 側に残らない。野良下書きの掃除を心配しなくてよい。
- note.com は公開 API が無く、`note.mjs` は DOM セレクタに依存する。UI 変更で壊れたら shots/ を見て
  `note.mjs` の `SELECTORS` を調整する(セレクタは 1 箇所に集約)。
- markdown オートコンバートの癖(数式 `$$`・区切り線・微妙な太字)は再現しきれない → 警告 + 人の最終確認で許容。
- 全置換の再同期は画像が再アップロードされ、公開済み記事では再公開になる。

## テスト

`bash skills/note-publish/tests/test_prepublish.sh`(ブラウザを呼ばない整形ロジック=除去・plan.json・警告・冪等)。
`note.mjs` は実 note 依存のため自動テスト対象外(手動確認)。
