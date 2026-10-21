// Opt-in live verification. Requires Playwright, a built Web shell, and a local HTTP server.
const fs = require('node:fs');
const { chromium } = require(process.env.RSTONE_PLAYWRIGHT_MODULE || 'playwright');
const config = JSON.parse(fs.readFileSync('assets/data_sync_config.json', 'utf8'));
const executablePath = process.env.CHROME_EXECUTABLE;
const webUrl = process.env.RSTONE_WEB_URL || 'http://127.0.0.1:8691/';
const inventory = fs.readFileSync('build/web/rstone_offline_worker.js', 'utf8').match(/^const FILES = (.+);$/m);
if (!inventory) throw new Error('Prepare the offline worker before verification');
const expectedResources = Object.keys(JSON.parse(inventory[1])).length;
(async () => {
  const browser = await chromium.launch({ executablePath, headless: true, args: ['--no-sandbox', '--enable-unsafe-swiftshader'] });
  const context = await browser.newContext({ viewport: { width: 400, height: 800 } });
  const page = await context.newPage();
  const errors = [], requests = [];
  page.on('pageerror', e => { errors.push(String(e)); console.error('Page error', String(e)); });
  page.on('request', r => requests.push(r.url()));
  try {
    await page.goto(webUrl, { timeout: 120000 });
    let ready = false;
    const deadline = Date.now() + 240000;
    while (!ready && Date.now() < deadline) {
      ready = await page.evaluate(async () => {
      if (!(await indexedDB.databases()).some(d => d.name === 'rstone-data-v1')) return false;
      return new Promise(resolve => {
        const q = indexedDB.open('rstone-data-v1');
        q.onsuccess = () => {
          const db = q.result;
          if (!db.objectStoreNames.contains('data')) { db.close(); resolve(false); return; }
          const tx = db.transaction('data');
          const get = tx.objectStore('data').get('official/active');
          get.onsuccess = () => resolve(!!get.result);
          tx.oncomplete = () => db.close();
        };
        q.onerror = () => resolve(false);
      });
      });
      if (!ready) await new Promise(r => setTimeout(r, 500));
    }
    if (!ready) throw new Error('Production commit timed out');
    console.log('Flutter Web production commit completed');
    const installed = await page.evaluate(() => new Promise((resolve, reject) => {
      const q = indexedDB.open('rstone-data-v1');
      q.onsuccess = () => {
        const db = q.result, tx = db.transaction('data'), store = tx.objectStore('data');
        const get = store.get('official/active');
        get.onsuccess = () => {
          try {
            const active = JSON.parse(new TextDecoder().decode(new Uint8Array(get.result)));
            const manifest = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(active.active.manifest), c => c.charCodeAt(0))));
            resolve({ sequence: manifest.sequence, dataVersion: manifest.dataVersion, files: manifest.files.length, lastLog: active.lastLog, lastSuccess: active.lastSuccess });
          } catch (e) { reject(new Error(String(e) + '; stored=' + String(JSON.stringify(get.result)).slice(0, 400))); }
        };
        get.onerror = () => reject(get.error);
        tx.oncomplete = () => db.close();
      };
      q.onerror = () => reject(q.error);
    }));
    const firstObjectRequests = requests.filter(u => u.includes('/objects/')).length;
    await page.evaluate(() => navigator.serviceWorker.ready);
    requests.length = 0;
    await page.reload({ waitUntil: 'load' });
    let repeated = false;
    const repeatDeadline = Date.now() + 60000;
    while (!repeated && Date.now() < repeatDeadline) {
      repeated = await page.evaluate(previous => new Promise((resolve, reject) => {
        const q = indexedDB.open('rstone-data-v1');
        q.onsuccess = () => {
          const db = q.result, tx = db.transaction('data'), get = tx.objectStore('data').get('official/active');
          get.onsuccess = () => {
            try { resolve(JSON.parse(new TextDecoder().decode(new Uint8Array(get.result))).lastSuccess !== previous); }
            catch (e) { reject(e); }
          };
          tx.oncomplete = () => db.close();
        };
        q.onerror = () => reject(q.error);
      }), installed.lastSuccess);
      if (!repeated) await new Promise(r => setTimeout(r, 500));
    }
    if (!repeated) throw new Error('Repeated synchronization timed out');
    const repeatObjectRequests = requests.filter(u => u.includes('/objects/')).length;
    if (repeatObjectRequests !== 0) throw new Error('Repeated Web sync downloaded objects');
    const cors = await page.evaluate(async config => {
      const bytes = async url => {
        const r = await fetch(url, { credentials: 'omit', redirect: 'error', cache: 'no-store' });
        if (!r.ok) throw new Error(url + ': ' + r.status);
        return new Uint8Array(await r.arrayBuffer());
      };
      const hex = async b => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', b))).map(x => x.toString(16).padStart(2, '0')).join('');
      const reports = [];
      for (const source of config.sources) {
        const latest = JSON.parse(new TextDecoder().decode(await bytes(source.url + 'latest.json?rstone_check=' + Date.now())));
        const name = String(latest.sequence).padStart(6, '0');
        const raw = await bytes(source.url + 'manifests/' + name + '.json');
        if (await hex(raw) !== latest.manifestSha256) throw new Error('Manifest hash mismatch');
        const sigText = new TextDecoder().decode(await bytes(source.url + 'manifests/' + name + '.sig'));
        const decode64 = s => Uint8Array.from(atob(s), c => c.charCodeAt(0));
        const key = await crypto.subtle.importKey('raw', decode64(config.keys[latest.keyId]), 'Ed25519', false, ['verify']);
        if (!await crypto.subtle.verify('Ed25519', key, decode64(sigText.trim()), raw)) throw new Error('Invalid signature');
        const manifest = JSON.parse(new TextDecoder().decode(raw));
        if (manifest.sequence !== latest.sequence || manifest.keyId !== latest.keyId || manifest.dataVersion !== latest.dataVersion) throw new Error('Latest binding mismatch');
        let objectBytes = 0;
        for (let i = 0; i < manifest.files.length; i += 6) {
          await Promise.all(manifest.files.slice(i, i + 6).map(async f => {
            const b = await bytes(source.url + 'objects/' + f.sha256);
            if (b.length !== f.size || await hex(b) !== f.sha256) throw new Error('Corrupt object ' + f.path);
            objectBytes += b.length;
          }));
        }
        reports.push({ source: source.name, files: manifest.files.length, objectBytes, signatureVerified: true });
      }
      return reports;
    }, config);
    console.log('CORS and all objects verified for both sources', cors);
    await page.evaluate(() => navigator.serviceWorker.ready);
    const cacheFiles = await page.evaluate(async () => {
      const names = (await caches.keys()).filter(n => n.startsWith('rstone-shell:'));
      return names.length ? (await (await caches.open(names[0])).keys()).length : 0;
    });
    if (cacheFiles !== expectedResources) throw new Error('Incomplete shell cache: ' + cacheFiles);
    await page.evaluate(() => new Promise((resolve, reject) => {
      const q = indexedDB.open('rstone-data-v1');
      q.onsuccess = () => {
        const db = q.result, tx = db.transaction('data', 'readwrite'), store = tx.objectStore('data');
        store.put(Array.from(new TextEncoder().encode('# 个人离线验证\n\n标签: #个人')), 'user/产品列表/RS-LIVE-WEB.md');
        store.put(Array.from(new TextEncoder().encode(JSON.stringify({ autoUpdate: false, preferredSource: null }))), 'settings/sync');
        tx.oncomplete = () => { db.close(); resolve(); };
        tx.onerror = () => reject(tx.error);
      };
    }));
    await context.setOffline(true);
    await page.reload({ waitUntil: 'load', timeout: 60000 });
    await page.locator('flt-semantics-placeholder').dispatchEvent('click', {}, { timeout: 30000 });
    console.log((await page.locator('body').innerText()).slice(0, 1600));
    const search = page.getByRole('textbox');
    await search.click({ timeout: 30000 });
    await search.pressSequentially('RS-LIVE-WEB', { delay: 60 });
    await page.getByText('RS-LIVE-WEB', { exact: true }).waitFor({ timeout: 30000 });
    await page.screenshot({ path: 'build/production-web-offline.png' });
    if (errors.length) throw new Error(errors.join('\n'));
    const report = { installed, firstObjectRequests, repeatObjectRequests, cors, shellCacheFiles: cacheFiles, offlineColdReload: true, personalVisible: 'RS-LIVE-WEB', versionHttpRequests: requests.filter(u => /\/version\.json/.test(u)).length, pageErrors: errors };
    fs.writeFileSync('build/production-web-verification.json', JSON.stringify(report, null, 2));
    console.log(JSON.stringify(report, null, 2));
  } finally {
    await page.screenshot({ path: 'build/production-web-last-state.png' }).catch(() => {});
    fs.writeFileSync('build/production-web-last-state.txt', await page.locator('body').innerText().catch(() => 'unavailable'));
    await context.close();
    await browser.close();
  }
})().catch(e => { console.error(e); process.exitCode = 1; });
