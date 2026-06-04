#!/usr/bin/env node
// note-publish: note.com への投稿プリミティブ(Playwright)。
// usage:
//   node note.mjs login                      # 手動ログイン → storageState 保存
//   node note.mjs draft   --plan <plan.json> # 下書き保存(既定)
//   node note.mjs publish --plan <plan.json> # 公開
//
// ⚠️ SELECTORS は note.com の DOM に対する初期推定。`login` 後に実機(DevTools)で
//    確認して確定すること。UI 変更で壊れたら shots/ を見てここだけ直す。
import { chromium } from 'playwright';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { resolve } from 'node:path';

const STATE_PATH = process.env.NOTE_PUBLISH_STATE || resolve(homedir(), '.note-state.json');
const TIMEOUT = Number(process.env.NOTE_PUBLISH_TIMEOUT || 180000);
const MOD = process.platform === 'darwin' ? 'Meta' : 'Control';

// ⚠️ 実機確認が必要なセレクタ(1 箇所に集約)。
const SELECTORS = {
  loginUrl: 'https://note.com/login',
  // /notes/new は editor.note.com/notes/<id>/edit/ にリダイレクトし、新規下書きを自動作成する。
  newNoteUrl: 'https://note.com/notes/new',
  // --- ↓ 実機確認済み(2026-05-31, editor.note.com)---
  title: 'textarea[placeholder="記事タイトル"]',
  body: 'div.ProseMirror',
  // 本文画像: 空行の「＋」=ブロックメニュー。開いて「画像」を選ぶと即 file chooser(insertImage 参照)。
  blockMenuButton: 'button[aria-label="メニューを開く"]',
  draftSaveButton: 'button:has-text("下書き保存")',
  publishButton: 'button:has-text("公開に進む")',
  // 「公開に進む」後の公開設定ページ(editor.note.com/notes/<id>/publish/)
  tagInput: 'input[placeholder="ハッシュタグを追加する"]',  // 実機確認済み
  publishConfirm: 'button:has-text("投稿する")',           // 実機確認済み(最終確定)
  paidRadio: 'input[name="is_paid"]',                      // 有料/無料ラジオ(best-effort)
  // 見出し画像(アイキャッチ): エディタ上部の領域。実機確認済み(2026-05-31, editor.note.com)。
  //   ① アイキャッチ「画像を追加」をクリック → ② メニュー「画像をアップロード」で file chooser
  //   → ③ setFiles → ④ トリミングダイアログの「保存」で確定。
  // ⚠️ アイキャッチの「画像を追加」は読み込み直後はページ唯一。setThumbnail 側で .first() を使い、
  //    本文入力より前に消費する(本文画像は別フロー=blockMenuButton なので消費後は衝突しない)。
  thumbnailButton: 'button[aria-label="画像を追加"]',       // アイキャッチ(load時の最初の1つ)
  // アイキャッチの「画像を追加」クリックで出るメニューの「画像をアップロード」(アイキャッチ専用)。
  imageUploadMenuItem: 'button:has-text("画像をアップロード")',
};

function parseArgs(argv) {
  const [cmd, ...rest] = argv;
  const opts = {};
  for (let i = 0; i < rest.length; i++) {
    if (rest[i] === '--plan') opts.plan = rest[++i];
  }
  return { cmd, opts };
}

function shotsDir(planPath) {
  const dir = resolve(planPath, '..', 'shots');
  mkdirSync(dir, { recursive: true });
  return dir;
}

function loadPlan(planPath) {
  const plan = JSON.parse(readFileSync(planPath, 'utf8'));
  const body = readFileSync(plan.bodyPath, 'utf8');
  return { plan, body };
}

// 公開/編集 URL から編集 URL を導く。
// 公開URL: https://note.com/<user>/n/<id>  →  編集: https://editor.note.com/notes/<id>/edit/
function toEditUrl(urlOrId) {
  if (/\/edit\/?$/.test(urlOrId)) return urlOrId;
  const m = urlOrId.match(/\/n\/([a-z0-9]+)/i);
  if (m) return `https://editor.note.com/notes/${m[1]}/edit/`;
  return urlOrId;
}

async function openContext(browser) {
  try {
    return await browser.newContext({ storageState: STATE_PATH });
  } catch (e) {
    console.error(`セッションがありません/壊れています(${STATE_PATH})。'node note.mjs login' を実行してください。`);
    await browser.close();
    process.exit(4);
  }
}

// 本文を 1 行ずつ ProseMirror にタイプ。Markdown 記法は note のオートコンバートに任せる。
// 画像参照行 ![..](path) と @@PAYWALL@@ は特殊行として onSpecial に委譲。
// note エディタのブロック分割の癖(実機確認 2026-05-31)。Markdown のブロック間空行は捨て、
// 「直前のブロック種別」に応じて区切りの Enter 回数を変えることで、空段落を作らず正しく変換させる:
//   - 段落 / リスト終端 / コード終端 → 次ブロックまで Enter ×2(×1 だと段落が融合し変換も起きない)
//   - 見出し → ×1(見出しは Enter1回で次段落へ抜ける)
//   - HR(`---`) → ×0(直後に空段落が自動生成されるので、そこへ直接書く)
//   - 画像(figure) → 前は ×0(直前ブロックの末尾でそのまま挿入。Enter を打つと図の上に空段落が残る)、
//     後は ×1(挿入直後はキャプション欄にカーソル。×1 で図の下の新ブロックへ抜ける。×0/×2 だと
//     キャプション吸い込みや空段落が出る)
//   - リスト項目どうし → ×1(note が自動継続。2項目目以降はマーカーを打たない)
//   - コードフェンス → ``` (言語識別子は中身に漏れるので除去) + Enter で入り、行内は Enter ×1、
//     閉じ ``` は打たず、次ブロックの区切り(prev='code' なので ×2)で抜ける
//   - 引用(`> `) → note では <figure class=blockquote><blockquote/><figcaption(=出典)/></figure>。
//     1行目は `> 本文`(変換トリガ)、継続行は Enter ×1 + 本文(`> ` を打たない)。
//   - 出典(@@CITE:...@@、prepublish が `<!-- cite: ... -->` から変換)→ 直前が引用のときだけ、
//     ArrowDown で figcaption(出典欄)へ入って記入。figcaption からは Enter ×2 で次ブロックへ抜ける。
async function typeBody(page, body, onSpecial) {
  const lines = body.split('\n');
  await page.click(SELECTORS.body);
  let prev = 'none'; // none|para|heading|hr|list|code|image|quote|cite
  const sep = (curIsList) => {
    if (prev === 'none') return 0;
    if (prev === 'list' && curIsList) return 1; // リスト継続
    if (prev === 'heading') return 1;
    if (prev === 'hr') return 0; // HR 直後の自動空段落に書く
    if (prev === 'image') return 1; // 図のキャプションから下の新ブロックへ抜ける
    return 2; // para / list-exit / code-exit / quote-exit / cite(figcaption)-exit
  };
  const press = async (n) => { for (let k = 0; k < n; k++) await page.keyboard.press('Enter'); };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (line.trim() === '') continue; // フェンス外の空行は捨てる(ブロック区切りは sep で付ける)

    // コードフェンスはユニットで処理(開始 ``` から閉じ ``` まで)
    if (/^```/.test(line.trim())) {
      await press(sep(false));
      await page.keyboard.type('```'); // 言語識別子は除去(中身に混入するため)
      for (i++; i < lines.length && !/^```/.test(lines[i].trim()); i++) {
        await page.keyboard.press('Enter'); // コード行内は Enter ×1
        await page.keyboard.type(lines[i]);
      }
      prev = 'code'; // 閉じ ``` 行は i がそこを指して continue で読み飛ばす
      continue;
    }

    const img = line.match(/^!\[[^\]]*\]\(([^)]+)\)\s*$/);
    const listItem = line.match(/^(\s*)([-*]|\d+\.)\s+(.*)$/);
    const cite = line.match(/^@@CITE:(.*)@@$/);
    const quote = line.match(/^>\s?(.*)$/);
    if (line.trim() === '@@PAYWALL@@') {
      await press(sep(false));
      await onSpecial({ type: 'paywall' });
      prev = 'para';
    } else if (cite) {
      // 直前が引用ブロックのときだけ、出典欄(figcaption)へ ArrowDown して記入。
      // 引用直後でない @@CITE@@ は無視(prepublish が警告済み)。
      if (prev === 'quote') {
        await page.keyboard.press('ArrowDown');
        await page.keyboard.type(cite[1]);
        prev = 'cite';
      }
    } else if (img) {
      // 画像の前は Enter を打たず、直前ブロックの末尾でそのまま挿入(空段落を残さない)。
      await onSpecial({ type: 'image', ref: img[1] });
      prev = 'image';
    } else if (quote) {
      if (prev === 'quote') {
        await page.keyboard.press('Enter'); // 引用内の継続行(note が自動継続)
        await page.keyboard.type(quote[1]); // `> ` は打たない(literal で残るため)
      } else {
        await press(sep(false));
        await page.keyboard.type(line); // 1行目は `> 本文`(変換トリガ)
      }
      prev = 'quote';
    } else if (listItem) {
      const cont = prev === 'list';
      await press(sep(true));
      await page.keyboard.type(cont ? listItem[3] : line); // 1項目目はマーカー込み、以降は本文のみ
      prev = 'list';
    } else {
      await press(sep(false));
      await page.keyboard.type(line);
      if (/^#{1,3}\s/.test(line)) prev = 'heading';
      else if (/^---+\s*$/.test(line.trim())) prev = 'hr';
      else prev = 'para';
    }
  }
}

async function insertImage(page, absPath) {
  // 本文画像挿入(実機確認 2026-05-31)。空行で「＋(メニューを開く)」→ ブロックメニューの「画像」。
  // 「画像」クリックで即 file chooser が開く(中間メニューもトリミング確定も無い。アイキャッチとは別フロー)。
  await page.click(SELECTORS.blockMenuButton); // 空行の「＋」でブロックメニューを開く
  const chooserP = page.waitForEvent('filechooser');
  chooserP.catch(() => {}); // 未ハンドル reject 抑止(await 側で捕捉)
  await page.getByRole('button', { name: '画像', exact: true }).click(); // 「画像」で file chooser
  const chooser = await chooserP;
  await chooser.setFiles(absPath);
  await page.waitForTimeout(2500); // アップロード待ち(本文画像はトリミング確定不要)
}

async function setThumbnail(page, absPath) {
  if (!absPath) return;
  // 見出し画像(アイキャッチ): ①「画像を追加」→ ②「画像をアップロード」→ ③ setFiles → ④ トリミング「保存」。
  // 見つからなければ best-effort で諦め、draft フローは止めない(メニュー/ダイアログを閉じてから戻る)。
  try {
    // 読み込み直後はアイキャッチが唯一の「画像を追加」。本文側の同名ボタンと衝突しないよう first。
    await page.locator(SELECTORS.thumbnailButton).first().click({ timeout: 8000 });
    // ② メニューの「画像をアップロード」で file chooser を開く。
    const chooserP = page.waitForEvent('filechooser', { timeout: 8000 });
    chooserP.catch(() => {}); // 未ハンドル reject でプロセスを落とさない(await 側で捕捉する)
    await page.click(SELECTORS.imageUploadMenuItem, { timeout: 8000 });
    const chooser = await chooserP;
    await chooser.setFiles(absPath);
    // ④ トリミングダイアログの「保存」で確定(「下書き保存」と区別するため exact)。
    await page.getByRole('button', { name: '保存', exact: true }).click({ timeout: 10000 });
    await page.waitForTimeout(1500);
    console.error('見出し画像を設定しました。');
  } catch (e) {
    console.error('見出し画像の自動設定に失敗(note 上で手動設定してください): ' + e.message);
    await page.keyboard.press('Escape').catch(() => {}); // 開きっぱなしのメニュー/ダイアログを閉じる
  }
}

// eslint-disable-next-line no-unused-vars
async function insertPaywall(_page) {
  // note の有料エリア(ここから先は有料)はエディタ内のインライン区切りでは確定できておらず、
  // 公開設定での 有料/価格 と合わせて手動設定が現実的。マーカー位置では本文に何も打たず、
  // 警告だけ出す(@@PAYWALL@@ は body に literal で残らない)。
  console.error('⚠️ 有料ライン(@@PAYWALL@@ の位置)は自動挿入していません。note 上で「ここから先を有料」を手動設定してください。');
}

// 新規作成した note の URL を、ソース draft.md の frontmatter url: に書き戻す。
// 以後その記事は target(=全置換の再同期)対象になり、1記事=1下書きを上書きし続けられる。
// 既存記事の再同期(plan.target あり)では何もしない。次回反映には prepublish.sh の再実行が必要。
function writeBackUrl(plan, url) {
  if (plan.target) return; // 既存記事の再同期時は不要
  try {
    // bodyPath は <slug>/.publish/body.md。2つ上が記事ディレクトリで、その直下が draft.md。
    const draftPath = resolve(plan.bodyPath, '..', '..', 'draft.md');
    let md = readFileSync(draftPath, 'utf8');
    const fm = md.match(/^---\n([\s\S]*?)\n---/);
    if (!fm) { console.error(`frontmatter が見つからず url 書き戻しをスキップ: ${draftPath}`); return; }
    const updated = /^url:.*$/m.test(fm[1])
      ? fm[1].replace(/^url:.*$/m, `url: ${url}`)       // 既存 url: 行を置換
      : `${fm[1]}\nurl: ${url}`;                         // 無ければ frontmatter 末尾に追加
    writeFileSync(draftPath, md.replace(fm[0], `---\n${updated}\n---`));
    console.error(`draft.md に url を書き戻しました(次回 prepublish 以降は全置換で使い回し): ${url}`);
  } catch (e) {
    console.error('url 書き戻しに失敗(手動で frontmatter url を設定してください): ' + e.message);
  }
}

async function runEditor(planPath, { publish }) {
  const { plan, body } = loadPlan(planPath);
  const browser = await chromium.launch({ headless: false });
  const ctx = await openContext(browser);
  const page = await ctx.newPage();
  page.setDefaultTimeout(TIMEOUT);

  // target があれば既存記事を全置換で再同期、無ければ新規
  if (plan.target) {
    const editUrl = toEditUrl(plan.target);
    await page.goto(editUrl);
    await page.click(SELECTORS.body);
    await page.keyboard.press(`${MOD}+A`);
    await page.keyboard.press('Delete');
    console.error(`既存記事を全置換で再同期します: ${editUrl}`);
  } else {
    await page.goto(SELECTORS.newNoteUrl);
  }

  // タイトル → 見出し画像 → 本文
  await page.fill(SELECTORS.title, plan.title);
  await setThumbnail(page, plan.thumbnailPath);

  const imgByRef = Object.fromEntries((plan.images || []).map((im) => [im.ref, im]));
  await typeBody(page, body, async (sp) => {
    if (sp.type === 'image') {
      const im = imgByRef[sp.ref];
      if (im && im.exists) await insertImage(page, im.absPath);
      else console.error(`[image missing] ${sp.ref}`);
    } else if (sp.type === 'paywall') {
      await insertPaywall(page);
    }
  });

  await page.waitForTimeout(2000);
  const shots = shotsDir(planPath);
  await page.screenshot({ path: resolve(shots, publish ? 'before-publish.png' : 'draft.png'), fullPage: true });

  if (publish) {
    // 公開フロー: 「公開に進む」→ /publish/ ページ → ハッシュタグ → 投稿する
    await page.click(SELECTORS.publishButton);
    await page.waitForSelector(SELECTORS.tagInput, { timeout: TIMEOUT });
    if (plan.paid) {
      console.error('⚠️ paid:true。有料設定(価格・有料エリア)は note 上で手動設定してください。自動では無料のまま投稿されます。');
    }
    for (const tag of plan.tags || []) {
      await page.fill(SELECTORS.tagInput, tag);
      await page.keyboard.press('Enter');
      await page.waitForTimeout(500);
    }
    await page.screenshot({ path: resolve(shots, 'before-publish.png'), fullPage: true });
    await page.click(SELECTORS.publishConfirm);
    await page.waitForTimeout(3000);
    await page.screenshot({ path: resolve(shots, 'after-publish.png'), fullPage: true });
    console.error(`公開しました: ${page.url()}`);
    writeBackUrl(plan, page.url());
  } else {
    // 明示的に「下書き保存」ボタンを押す(自動保存もあるが確実性のため)。
    try {
      await page.click(SELECTORS.draftSaveButton);
      await page.waitForTimeout(2000);
      console.error(`下書き保存しました: ${page.url()}`);
    } catch (e) {
      console.error('「下書き保存」ボタンが見つからず、note の自動保存に委ねます: ' + e.message);
    }
    writeBackUrl(plan, page.url());
    console.error('shots/draft.png を確認してください。');
  }
  await page.waitForTimeout(1000);
  await browser.close();
}

async function cmdLogin() {
  const browser = await chromium.launch({ headless: false });
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  await page.goto(SELECTORS.loginUrl, { timeout: TIMEOUT });
  console.error('ブラウザで note.com にログインしてください。完了したら、このターミナルで Enter を押してください。');
  await new Promise((res) => process.stdin.once('data', res));
  await ctx.storageState({ path: STATE_PATH });
  console.error(`セッションを保存しました: ${STATE_PATH}`);
  await browser.close();
}

async function main() {
  const { cmd, opts } = parseArgs(process.argv.slice(2));
  switch (cmd) {
    case 'login':
      await cmdLogin();
      break;
    case 'draft':
      if (!opts.plan) { console.error('--plan が必要です'); process.exit(2); }
      await runEditor(opts.plan, { publish: false });
      break;
    case 'publish':
      if (!opts.plan) { console.error('--plan が必要です'); process.exit(2); }
      await runEditor(opts.plan, { publish: true });
      break;
    default:
      console.error('usage: node note.mjs <login|draft|publish> [--plan plan.json]');
      process.exit(2);
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
