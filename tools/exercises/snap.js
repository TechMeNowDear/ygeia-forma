// node snap.js <side|front|both> [ids] [out] → out/snap.png
const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch(); const pg = await b.newPage({ viewport: { width: 1200, height: 800 }, deviceScaleFactor: 1 });
  const errs = []; pg.on('pageerror', e => errs.push(e.message)); pg.on('console', m => { if (m.type() === 'error') errs.push(m.text()); });
  const mode = process.argv[2] || 'side', ids = process.argv[3] || '';
  await pg.goto('file://' + __dirname + '/out/preview.html?snap=' + mode + (ids ? '&ex=' + ids : ''));
  try { await pg.waitForFunction(() => document.title === 'ready', null, { timeout: 8000 }); } catch (e) { console.log('ERR', errs); }
  await pg.screenshot({ path: __dirname + '/out/' + (process.argv[4] || 'snap') + '.png', fullPage: true });
  if (errs.length) console.log(errs.join('\n'));
  await b.close();
})();
