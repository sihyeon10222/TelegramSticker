import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHandler } from '../src/index.ts';

const token = '123456:SERVER_ONLY_TEST_TOKEN';
const access = 'private-test-access-key-long-enough';
const png = new Uint8Array([137,80,78,71,13,10,26,10,0]); // Proxy sniffs; iOS validates the full decoder payload.
const baseSticker = { file_id: 'telegram-download-id', file_unique_id: 'stable-id',
  width: 512, height: 512, is_animated: false, is_video: false, emoji: '🙂', file_size: png.length };
const pack = { name: 'TestPack', title: 'Test pack', sticker_type: 'regular', stickers: [baseSticker] };
function setup(options = {}) {
  const calls = [], pending = [], stored = new Map();
  const env = { BOT_TOKEN: token, ACCESS_KEY: access,
    PACK_LIMIT: { limit: async () => ({ success: options.allowed !== false }) },
    ASSET_LIMIT: { limit: async () => ({ success: options.allowed !== false }) } };
  const context = { waitUntil(p) { pending.push(p); } };
  const handler = createHandler({
    cache: { async match(key) { return stored.get(key.url)?.clone(); }, async put(key, value) { stored.set(key.url, value.clone()); } },
    fetch: async (url, init) => {
      calls.push({ url: String(url), init });
      if (options.fetch) return options.fetch(String(url), init);
      if (String(url).endsWith('/getStickerSet')) return Response.json({ ok: true, result: options.pack ?? pack });
      if (String(url).endsWith('/getFile')) return Response.json({ ok: true, result: { file_path: options.path ?? 'stickers/file_0.png' } });
      return new Response(options.bytes ?? png, { headers: options.headers ?? {} });
    }
  });
  return { calls, env, pending, async get(path = '/v1/packs/TestPack', authorized = true, method = 'GET') {
    const response = await handler(new Request(`https://service.example${path}`, {
      method, headers: authorized ? { authorization: `Bearer ${access}`, 'cf-connecting-ip': '192.0.2.1' } : {}
    }), env, context);
    await Promise.all(pending);
    return response;
  } };
}
async function assetPath(app, variant = 'original') {
  const meta = await (await app.get()).json();
  return `/v1/packs/testpack/assets/${meta.stickers[0].id}?variant=${variant}`;
}

test('metadata normalizes names and never exposes token, file IDs or Telegram URLs', async () => {
  const app = setup();
  const response = await app.get();
  const text = await response.text();
  for (const value of [token, baseSticker.file_id, 'api.telegram.org']) assert.ok(!text.includes(value));
  const data = JSON.parse(text);
  assert.equal(data.name, 'testpack'); assert.equal(data.stickers[0].id.length, 64);
  await app.get(); assert.equal(app.calls.length, 1);
});
test('authentication and rate limiting run before any cached response', async () => {
  const app = setup(); await app.get();
  assert.equal((await app.get(undefined, false)).status, 401);
  app.env.PACK_LIMIT = { limit: async () => ({ success: false }) };
  const result = await app.get(); assert.equal(result.status, 429); assert.equal(result.headers.get('retry-after'), '60');
  assert.equal(app.calls.length, 1);
});
test('invalid routes, variants and arbitrary file IDs do not contact Telegram', async () => {
  const app = setup();
  for (const path of ['/v1/packs/%54estPack', '/v1/packs/TestPack?url=https://evil.example',
    '/v1/packs/TestPack/assets/arbitrary?variant=original', '/v1/packs/' + 'a'.repeat(65)]) {
    assert.equal((await app.get(path)).status, 400);
  }
  assert.equal((await app.get(undefined, true, 'POST')).status, 405);
  assert.equal(app.calls.length, 0);
});
test('asset must belong to pack; successful files are relayed and cached without redirect', async () => {
  const app = setup(); const path = await assetPath(app);
  const missing = path.replace(/assets\/[a-f0-9]+/, 'assets/' + '0'.repeat(64));
  assert.equal((await app.get(missing)).status, 404);
  const response = await app.get(path);
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), png);
  assert.equal(response.headers.get('location'), null);
  const count = app.calls.length; await app.get(path); assert.equal(app.calls.length, count);
  assert.ok(app.calls.every(c => c.init.redirect === 'manual'));
});
test('non-regular packs cannot download original files', async () => {
  for (const changed of [{ ...pack, sticker_type: 'mask' }, { ...pack, sticker_type: 'custom_emoji' }]) {
    const app = setup({ pack: changed });
    assert.equal((await app.get(await assetPath(app))).status, 415);
  }
});
test('TGS and WebM originals are relayed only with the matching signature and bounded size', async () => {
  for (const [format, bytes, type] of [
    ['animated', new Uint8Array([31,139,8,0]), 'application/x-tgsticker'],
    ['video', new Uint8Array([26,69,223,163,0]), 'video/webm']
  ]) {
    const changed = { ...pack, stickers: [{ ...baseSticker, is_animated: format === 'animated', is_video: format === 'video' }] };
    const app = setup({ pack: changed, bytes });
    const response = await app.get(await assetPath(app));
    assert.equal(response.status, 200); assert.equal(response.headers.get('content-type'), type);
    assert.deepEqual(new Uint8Array(await response.arrayBuffer()), bytes);
    const invalid = setup({ pack: changed, bytes: png });
    assert.equal((await invalid.get(await assetPath(invalid))).status, 415);
  }
  const app = setup({ pack: { ...pack, stickers: [{ ...baseSticker, is_animated: true }] },
    bytes: new Uint8Array([31,139,8, ...new Uint8Array(64 * 1024)]) });
  assert.equal((await app.get(await assetPath(app))).status, 415);
});
test('declared and streamed oversize, unknown binary and traversal upstream paths are rejected', async () => {
  for (const options of [
    { headers: { 'content-length': String(20 * 1024 * 1024 + 1) } },
    { bytes: new Uint8Array(20 * 1024 * 1024 + 1) },
    { bytes: new TextEncoder().encode('not an image') },
    { path: '../private/file.png' }
  ]) {
    const app = setup(options); const response = await app.get(await assetPath(app));
    assert.ok([413,415,502].includes(response.status));
    assert.ok(!(await response.text()).includes(token));
  }
});
test('upstream errors are sanitized and retry-after is bounded', async () => {
  const app = setup({ fetch: async () => Response.json({ ok: false, error_code: 429,
    description: `secret ${token}`, parameters: { retry_after: 99999 } }, { status: 429 }) });
  const response = await app.get(); assert.equal(response.status, 429); assert.equal(response.headers.get('retry-after'), '60');
  assert.ok(!(await response.text()).includes(token));
  const thrown = setup({ fetch: async () => { throw new Error(`https://api.telegram.org/bot${token}`); } });
  assert.ok(!(await (await thrown.get()).text()).includes(token));
});
test('expired file path is re-resolved once', async () => {
  let files = 0, downloads = 0;
  const app = setup({ fetch: async url => {
    if (url.endsWith('getStickerSet')) return Response.json({ ok: true, result: pack });
    if (url.endsWith('getFile')) { files++; return Response.json({ ok: true, result: { file_path: 'stickers/file.png' } }); }
    downloads++; return downloads === 1 ? new Response('', { status: 404 }) : new Response(png);
  } });
  assert.equal((await app.get(await assetPath(app))).status, 200); assert.equal(files, 2);
});
test('missing secrets fail closed', async () => {
  const app = setup(); app.env.ACCESS_KEY = '';
  assert.equal((await app.get()).status, 503); assert.equal(app.calls.length, 0);
});

test('Telegram authentication rejection is non-retryable and does not expose its body', async () => {
  for (const status of [401, 403]) {
    const app = setup({ fetch: async () => new Response(`secret ${token}`, { status }) });
    const response = await app.get();
    assert.equal(response.status, 502);
    assert.deepEqual(await response.json(), { error: { code: 'telegram_auth_failed', retryable: false } });
  }
});

test('Telegram API and file redirects are rejected without following or exposing Location', async () => {
  for (const redirectAt of ['api', 'file']) {
    const app = setup({ fetch: async url => {
      if (redirectAt === 'api' || url.includes('/file/bot')) {
        return new Response(null, { status: 302, headers: { location: `https://other.example/${token}` } });
      }
      if (url.endsWith('getStickerSet')) return Response.json({ ok: true, result: pack });
      return Response.json({ ok: true, result: { file_path: 'stickers/file.png' } });
    }});
    const response = redirectAt === 'api' ? await app.get() : await app.get(await assetPath(app));
    assert.equal(response.status, 502);
    assert.deepEqual(await response.json(), { error: { code: 'upstream_redirect', retryable: false } });
    assert.equal(response.headers.get('location'), null);
    assert.ok(app.calls.every(c => c.url.startsWith('https://api.telegram.org/') && c.init.redirect === 'manual'));
  }
});

test('refresh bypasses metadata cache and acknowledges a real upstream check', async () => {
  const app = setup(); await app.get(); await app.get();
  assert.equal(app.calls.length, 1);
  const fresh = await (await app.get('/v1/packs/TestPack?refresh=1')).json();
  assert.equal(app.calls.length, 2); assert.equal(fresh.refreshed, true);
  assert.ok(Number.isFinite(fresh.fetchedAt));
  for (const query of ['refresh=0', 'refresh=1&refresh=1', 'refresh=1&x=1']) {
    assert.equal((await app.get('/v1/packs/TestPack?' + query)).status, 400);
  }
});
test('valid-signature assets above the old 2MiB limit are streamed intact', async () => {
  const bytes = new Uint8Array(3 * 1024 * 1024); bytes.set([26,69,223,163]);
  const app = setup({ pack: { ...pack, stickers: [{ ...baseSticker, is_video: true, file_size: bytes.length }] }, bytes });
  const response = await app.get(await assetPath(app)); assert.equal(response.status, 200);
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), bytes);
});
test('streamed size overflow after a valid prefix fails the body without forwarding secrets', async () => {
  const app = setup({ fetch: async url => {
    if (url.endsWith('/getStickerSet')) return Response.json({ ok: true, result: pack });
    if (url.endsWith('/getFile')) return Response.json({ ok: true, result: { file_path: 'stickers/test.png' } });
    let chunk = 0;
    return new Response(new ReadableStream({ pull(controller) {
      if (chunk++ === 0) { const header = new Uint8Array(12); header.set(png); controller.enqueue(header); }
      else if (chunk <= 22) controller.enqueue(new Uint8Array(1024 * 1024));
      else controller.close();
    } }));
  } });
  const response = await app.get(await assetPath(app)); assert.equal(response.status, 200);
  await assert.rejects(response.arrayBuffer(), /file_too_large/);
});
