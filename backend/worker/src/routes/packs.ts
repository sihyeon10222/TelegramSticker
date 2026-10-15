import type { Env, Runtime, Context, RequestDiagnostics } from '../types.ts';
import { APIError, json } from '../http/response.ts';
import { boundedString, idPattern, MAX_FILE_BYTES } from '../validation/limits.ts';
import { createWorkerCache } from '../cache/worker-cache.ts';
import { createTelegramClient } from '../services/telegram.ts';
import { createPackLoader } from '../services/packs.ts';
import { streamAsset } from '../services/assets.ts';
import { digest } from '../services/digest.ts';

export async function packRoute(request: Request, env: Env, context: Context, runtime: Runtime, signal: AbortSignal, diagnostics: RequestDiagnostics): Promise<Response> {
  const url = new URL(request.url);
  const match = /^\/v1\/packs\/([A-Za-z0-9_]{1,64})(?:\/assets\/([a-f0-9]{64}))?$/.exec(url.pathname);
  if (!match || url.hash) throw new APIError(400, 'invalid_request');
  const name = match[1].toLowerCase(), assetID = match[2];
  const variants = url.searchParams.getAll('variant');
  const refresh = !assetID && url.searchParams.get('refresh') === '1';
  if ((!assetID && url.search && !(refresh && [...url.searchParams.keys()].length === 1)) || (assetID && (variants.length !== 1 ||
      !['original','thumbnail'].includes(variants[0]) || [...url.searchParams.keys()].some(k => k !== 'variant')))) {
    throw new APIError(400, 'invalid_request');
  }
  const rateKey = request.headers.get('cf-connecting-ip') ?? 'local';
  diagnostics.stage = 'rate_limit';
  if (!(await (assetID ? env.ASSET_LIMIT : env.PACK_LIMIT).limit({ key: rateKey })).success) {
    throw new APIError(429, 'rate_limited', true, 60);
  }
  const cache = await createWorkerCache(runtime.cache, context, env.BOT_TOKEN);
  const upstream = createTelegramClient(runtime, env, signal, diagnostics);
  const loadPack = createPackLoader(name, refresh, upstream, cache, diagnostics);
  const pack = await loadPack();
  if (!assetID) return json({ name: pack.name, title: pack.title, stickerType: pack.stickerType, fetchedAt: pack.fetchedAt, refreshed: refresh,
    stickers: pack.stickers.map(({ fileID, thumbnailID, ...sticker }) => ({ ...sticker,
      hasThumbnail: !!thumbnailID || sticker.format === 'static' })) });
  if (!idPattern.test(assetID)) throw new APIError(400, 'invalid_request');
  let sticker = pack.stickers.find(s => s.id === assetID);
  if (!sticker) sticker = (await loadPack(true)).stickers.find(s => s.id === assetID);
  if (!sticker) throw new APIError(404, 'asset_unavailable');
  const thumbnail = variants[0] === 'thumbnail';
  if (!thumbnail && pack.stickerType !== 'regular') {
    throw new APIError(415, 'unsupported_format');
  }
  const fileID = thumbnail ? sticker.thumbnailID ?? (sticker.format === 'static' ? sticker.fileID : undefined) : sticker.fileID;
  if (!fileID) throw new APIError(404, 'asset_unavailable');
  if (!thumbnail && (sticker.fileSize ?? 0) > MAX_FILE_BYTES) throw new APIError(413, 'file_too_large');
  const assetKey = `assets/${name}/${assetID}/${variants[0]}/${await digest(fileID)}`;
  const existing = await cache.get(assetKey);
  if (existing) {
    const response = new Response(existing.body, existing);
    response.headers.set('cache-control', 'private, max-age=86400');
    return response;
  }
  for (let attempt = 0; attempt < 2; attempt++) {
    const file = await upstream('getFile', { file_id: fileID });
    if ((file.file_size ?? 0) > MAX_FILE_BYTES) throw new APIError(413, 'file_too_large');
    if (!boundedString(file.file_path, 512) || !/^[A-Za-z0-9_./-]+$/.test(file.file_path) ||
        file.file_path.startsWith('/') || file.file_path.split('/').some((s: string) => !s || s === '.' || s === '..')) {
      throw new APIError(502, 'invalid_upstream');
    }
    diagnostics.stage = 'telegram_download'; diagnostics.upstreamStatus = undefined;
    const response = await runtime.fetch(`https://api.telegram.org/file/bot${env.BOT_TOKEN}/${file.file_path}`, {
      redirect: 'manual', signal: signal
    });
    diagnostics.upstreamStatus = response.status;
    if (response.status >= 300 && response.status < 400) {
      await response.body?.cancel();
      throw new APIError(502, 'upstream_redirect');
    }
    if ((response.status === 404 || response.status === 410) && attempt === 0) { await response.body?.cancel(); continue; }
    if (!response.ok) { await response.body?.cancel(); throw new APIError(502, 'upstream_unavailable', true); }
    const { body, type } = await streamAsset(response, thumbnail, sticker.format);
    const output = new Response(body, { headers: { 'content-type': type, 'cache-control': 'private, max-age=86400',
      'x-content-type-options': 'nosniff' } });
    cache.put(assetKey, output.clone(), 86400);
    return output;
  }
  throw new APIError(502, 'upstream_unavailable', true);
}
