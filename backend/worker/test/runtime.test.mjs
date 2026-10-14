import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';

test('production entry point runs in workerd and never follows Telegram redirects', async () => {
  const source = await readFile(new URL('../src/index.ts', import.meta.url), 'utf8');
  const access = 'local-runtime-test-access-key';
  const token = '123456:LOCAL_RUNTIME_TEST_TOKEN';
  const png = new Uint8Array([137,80,78,71,13,10,26,10,0]);
  const calls = [];
  let redirectFiles = false;
  const worker = new Miniflare(convertV4MiniflareOptions({
    modules: true, script: stripTypeScriptTypes(source), compatibilityDate: '2026-10-13',
    bindings: { BOT_TOKEN: token, ACCESS_KEY: access },
    ratelimits: {
      PACK_LIMIT: { namespace_id: '1', simple: { limit: 100, period: 60 } },
      ASSET_LIMIT: { namespace_id: '2', simple: { limit: 100, period: 60 } }
    },
    // All outbound I/O is intercepted. No real token, Telegram connection, or deployment.
    outboundService: async request => {
      const url = new URL(request.url);
      calls.push(url);
      assert.equal(url.origin, 'https://api.telegram.org');
      if (url.pathname.endsWith('getStickerSet')) {
        const { name } = await request.json();
        if (name === 'redirect_pack') return new Response(null, { status: 302, headers: { location: 'https://other.invalid' } });
        return Response.json({ ok: true, result: { name, title: 'Runtime fixture', sticker_type: 'regular', stickers: [{
          file_id: 'runtime-file', file_unique_id: 'runtime-stable', width: 512, height: 512,
          is_animated: false, is_video: false
        }] } });
      }
      if (url.pathname.endsWith('getFile')) return Response.json({ ok: true, result: { file_path: 'stickers/fixture.png' } });
      if (redirectFiles) return new Response(null, { status: 307, headers: { location: 'https://other.invalid' } });
      return new Response(png);
    }
  }));
  const get = path => worker.dispatchFetch(`https://worker.invalid${path}`, { headers: { authorization: `Bearer ${access}` } });
  try {
    const response = await get('/v1/packs/runtime_pack');
    assert.equal(response.status, 200);
    const pack = await response.json();
    assert.equal(pack.name, 'runtime_pack');
    const asset = `/v1/packs/runtime_pack/assets/${pack.stickers[0].id}`;
    const original = await get(asset + '?variant=original');
    assert.equal(original.status, 200);
    assert.deepEqual(new Uint8Array(await original.arrayBuffer()), png);
    const before = calls.length;
    const redirect = await get('/v1/packs/redirect_pack');
    assert.equal(redirect.status, 502);
    assert.equal((await redirect.json()).error.code, 'upstream_redirect');
    assert.equal(calls.length, before + 1);
    redirectFiles = true;
    const thumbnail = await get(asset + '?variant=thumbnail');
    assert.equal(thumbnail.status, 502);
    assert.equal((await thumbnail.json()).error.code, 'upstream_redirect');
    assert.ok(calls.every(url => url.origin === 'https://api.telegram.org'));
  } finally { await worker.dispose(); }
});
