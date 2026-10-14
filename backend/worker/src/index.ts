// No runtime packages. Secrets are provided only through Worker bindings.
interface Limiter { limit(options: { key: string }): Promise<{ success: boolean }> }
interface Env { BOT_TOKEN: string; ACCESS_KEY: string; PACK_LIMIT: Limiter; ASSET_LIMIT: Limiter }
interface WorkerCache { match(key: Request): Promise<Response | undefined>; put(key: Request, value: Response): Promise<void> }
interface Context { waitUntil(promise: Promise<unknown>): void }
interface Runtime { fetch: typeof fetch; cache?: WorkerCache }
interface StoredSticker {
  id: string; format: string; width: number; height: number; emoji?: string;
  fileSize?: number; fileID: string; thumbnailID?: string;
}
interface StoredPack { name: string; title: string; stickerType: string; stickers: StoredSticker[]; fetchedAt: number }

class APIError extends Error {
  status: number; code: string; retryable: boolean; retryAfter?: number;
  constructor(status: number, code: string, retryable = false, retryAfter?: number) {
    super(code); this.status = status; this.code = code; this.retryable = retryable; this.retryAfter = retryAfter;
  }
}
const MAX_BYTES = 2 * 1024 * 1024; // Metadata only.
const MAX_FILE_BYTES = 20 * 1024 * 1024; // Telegram cloud Bot API limit.
const namePattern = /^[A-Za-z0-9_]{1,64}$/;
const idPattern = /^[a-f0-9]{64}$/;
const isObject = (v: unknown): v is Record<string, any> => !!v && typeof v === 'object' && !Array.isArray(v);
const boundedString = (v: unknown, max: number): v is string => typeof v === 'string' && v.length > 0 && v.length <= max;
const dimension = (v: unknown): v is number => Number.isInteger(v) && Number(v) > 0 && Number(v) <= 4096;

async function digest(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map(v => v.toString(16).padStart(2, '0')).join('');
}
async function authorized(request: Request, key: string): Promise<boolean> {
  const supplied = request.headers.get('authorization') ?? '';
  if (supplied.length > 512) return false;
  const a = await digest(supplied), b = await digest(`Bearer ${key}`);
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return difference === 0;
}
function json(value: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(value), { status, headers: {
    'content-type': 'application/json', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff', ...extra
  } });
}
async function bounded(response: Response): Promise<Uint8Array<ArrayBuffer>> {
  const declared = response.headers.get('content-length');
  if (declared && (!/^\d+$/.test(declared) || Number(declared) > MAX_BYTES)) {
    await response.body?.cancel(); throw new APIError(413, 'file_too_large');
  }
  const stream = response.body?.getReader();
  if (!stream) throw new APIError(502, 'invalid_upstream');
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    for (;;) {
      const { done, value } = await stream.read();
      if (done) break;
      length += value.byteLength;
      if (length > MAX_BYTES) { await stream.cancel(); throw new APIError(413, 'file_too_large'); }
      chunks.push(value);
    }
  } finally { stream.releaseLock(); }
  const result = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { result.set(chunk, offset); offset += chunk.byteLength; }
  return result;
}
function contentType(bytes: Uint8Array, thumbnail: boolean, format: string): string {
  const starts = (prefix: number[]) => prefix.every((v, i) => bytes[i] === v);
  if (!thumbnail && format === 'animated') {
    if (starts([31,139,8])) return 'application/x-tgsticker';
    throw new APIError(415, 'unsupported_format');
  }
  if (!thumbnail && format === 'video') {
    if (starts([26,69,223,163])) return 'video/webm';
    throw new APIError(415, 'unsupported_format');
  }
  if (starts([137,80,78,71,13,10,26,10])) return 'image/png';
  if (starts([82,73,70,70]) && new TextDecoder().decode(bytes.slice(8,12)) === 'WEBP') return 'image/webp';
  if (thumbnail && starts([255,216,255])) return 'image/jpeg';
  throw new APIError(415, 'unsupported_format');
}

async function streamAsset(response: Response, thumbnail: boolean, format: string) {
  const declared = response.headers.get('content-length');
  if (declared && (!/^\d+$/.test(declared) || Number(declared) > MAX_FILE_BYTES)) {
    await response.body?.cancel(); throw new APIError(413, 'file_too_large');
  }
  const reader = response.body?.getReader();
  if (!reader) throw new APIError(502, 'invalid_upstream');
  let length = 0;
  const first: Uint8Array[] = [];
  try {
    while (length < 12) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.byteLength; first.push(value);
      if (length > MAX_FILE_BYTES) throw new APIError(413, 'file_too_large');
    }
    const header = new Uint8Array(Math.min(length, 12));
    let offset = 0;
    for (const chunk of first) { const part = chunk.subarray(0, header.length - offset); header.set(part, offset); offset += part.length; }
    if (!thumbnail && format === 'animated' && length > 64 * 1024) throw new APIError(415, 'unsupported_format');
    const type = contentType(header, thumbnail, format);
    const body = new ReadableStream<Uint8Array>({
      async pull(controller) {
        if (first.length) { controller.enqueue(first.shift()!); return; }
        let timer: ReturnType<typeof setTimeout> | undefined;
        try {
          const result = await Promise.race([reader.read(), new Promise<never>((_, reject) => {
            timer = setTimeout(() => reject(new Error('stream_timeout')), 30_000);
          })]);
          if (result.done) { controller.close(); reader.releaseLock(); return; }
          length += result.value.byteLength;
          if (length > MAX_FILE_BYTES || (!thumbnail && format === 'animated' && length > 64 * 1024)) throw new Error('file_too_large');
          controller.enqueue(result.value);
        } catch (error) { await reader.cancel().catch(() => {}); controller.error(error); }
        finally { clearTimeout(timer); }
      },
      async cancel(reason) { await reader.cancel(reason); }
    });
    return { body, type };
  } catch (error) { await reader.cancel().catch(() => {}); throw error; }
}

export function createHandler(runtime: Runtime) {
  return async (request: Request, env: Env, context: Context): Promise<Response> => {
    // One deadline covers upstream calls AND reading bodies; no token-bearing exception escapes.
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15_000);
    let stage = 'configuration';
    let upstreamStatus: number | undefined;
    try {
      if (!boundedString(env.BOT_TOKEN, 256) || !/^[0-9]+:[A-Za-z0-9_-]+$/.test(env.BOT_TOKEN) ||
          !boundedString(env.ACCESS_KEY, 256) || env.ACCESS_KEY.length < 24 || !env.PACK_LIMIT || !env.ASSET_LIMIT) {
        throw new APIError(503, 'server_not_configured');
      }
      stage = 'authentication';
      if (!(await authorized(request, env.ACCESS_KEY))) throw new APIError(401, 'unauthorized');
      if (request.method !== 'GET') throw new APIError(405, 'method_not_allowed');
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
      stage = 'rate_limit';
      if (!(await (assetID ? env.ASSET_LIMIT : env.PACK_LIMIT).limit({ key: rateKey })).success) {
        throw new APIError(429, 'rate_limited', true, 60);
      }
      const namespace = await digest(env.BOT_TOKEN);
      const cacheKey = (suffix: string) => new Request(`https://stickerbridge-cache.invalid/v1/${namespace}/${suffix}`);
      const cacheGet = async (suffix: string) => {
        try { return await runtime.cache?.match(cacheKey(suffix)); } catch { return undefined; }
      };
      const cachePut = (suffix: string, value: Response, ttl: number) => {
        if (!runtime.cache) return;
        const cached = new Response(value.body, value);
        cached.headers.set('cache-control', `public, max-age=${ttl}`);
        context.waitUntil(runtime.cache.put(cacheKey(suffix), cached).catch(() => {}));
      };
      const upstream = async (method: string, params: Record<string, string>): Promise<Record<string, any>> => {
        stage = method === 'getStickerSet' ? 'telegram_pack' : 'telegram_file';
        const response = await runtime.fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/${method}`, {
          method: 'POST', body: JSON.stringify(params), headers: { 'content-type': 'application/json' },
          redirect: 'manual', signal: controller.signal
        });
        upstreamStatus = response.status;
        if (response.status >= 300 && response.status < 400) {
          await response.body?.cancel();
          throw new APIError(502, 'upstream_redirect');
        }
        if (response.status === 401 || response.status === 403) {
          await response.body?.cancel();
          throw new APIError(502, 'telegram_auth_failed');
        }
        const data: unknown = JSON.parse(new TextDecoder().decode(await bounded(response)));
        if (!isObject(data)) throw new APIError(502, 'invalid_upstream');
        if (!response.ok || data.ok !== true) {
          if (response.status === 429 || data.error_code === 429) {
            throw new APIError(429, 'upstream_rate_limited', true,
              Math.min(60, Math.max(1, Number(data.parameters?.retry_after) || 5)));
          }
          if (method === 'getStickerSet' && data.error_code === 400) throw new APIError(404, 'pack_unavailable');
          throw new APIError(502, 'upstream_unavailable', true);
        }
        if (!isObject(data.result)) throw new APIError(502, 'invalid_upstream');
        return data.result;
      };
      const loadPack = async (force = false): Promise<StoredPack> => {
        const cached = await cacheGet(`packs/${name}`);
        if (cached && !refresh && !force) return await cached.json() as StoredPack;
        const result = await upstream('getStickerSet', { name });
        stage = 'pack_validation';
        if (!boundedString(result.name, 64) || !namePattern.test(result.name) || result.name.toLowerCase() !== name ||
            !boundedString(result.title, 256) || !['regular', 'mask', 'custom_emoji'].includes(result.sticker_type) ||
            !Array.isArray(result.stickers) || result.stickers.length > 1000) throw new APIError(502, 'invalid_upstream');
        const seen = new Set<string>();
        const stickers: StoredSticker[] = [];
        for (const sticker of result.stickers) {
          if (!isObject(sticker) || !boundedString(sticker.file_id, 512) || !boundedString(sticker.file_unique_id, 256) ||
              !dimension(sticker.width) || !dimension(sticker.height) || typeof sticker.is_animated !== 'boolean' ||
              typeof sticker.is_video !== 'boolean') throw new APIError(502, 'invalid_upstream');
          const id = await digest(sticker.file_unique_id);
          if (seen.has(id)) throw new APIError(502, 'invalid_upstream');
          seen.add(id);
          stickers.push({ id, format: sticker.is_video ? 'video' : sticker.is_animated ? 'animated' : 'static',
            width: sticker.width, height: sticker.height,
            emoji: typeof sticker.emoji === 'string' ? sticker.emoji.slice(0,32) : undefined,
            fileSize: Number.isSafeInteger(sticker.file_size) && sticker.file_size >= 0 ? sticker.file_size : undefined,
            fileID: sticker.file_id,
            thumbnailID: boundedString(sticker.thumbnail?.file_id, 512) ? sticker.thumbnail.file_id : undefined });
        }
        const pack = { name, title: result.title, stickerType: result.sticker_type, stickers, fetchedAt: Date.now() / 1000 };
        cachePut(`packs/${name}`, json(pack), 600);
        return pack;
      };
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
      const existing = await cacheGet(assetKey);
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
        stage = 'telegram_download'; upstreamStatus = undefined;
        const response = await runtime.fetch(`https://api.telegram.org/file/bot${env.BOT_TOKEN}/${file.file_path}`, {
          redirect: 'manual', signal: controller.signal
        });
        upstreamStatus = response.status;
        if (response.status >= 300 && response.status < 400) {
          await response.body?.cancel();
          throw new APIError(502, 'upstream_redirect');
        }
        if ((response.status === 404 || response.status === 410) && attempt === 0) { await response.body?.cancel(); continue; }
        if (!response.ok) { await response.body?.cancel(); throw new APIError(502, 'upstream_unavailable', true); }
        const { body, type } = await streamAsset(response, thumbnail, sticker.format);
        const output = new Response(body, { headers: { 'content-type': type, 'cache-control': 'private, max-age=86400',
          'x-content-type-options': 'nosniff' } });
        cachePut(assetKey, output.clone(), 86400);
        return output;
      }
      throw new APIError(502, 'upstream_unavailable', true);
    } catch (error) {
      const safe = error instanceof APIError ? error : new APIError(502, controller.signal.aborted ? 'timeout' : 'upstream_unavailable', true);
      const detail = error instanceof Error ? error.message : '';
      const failureKind = error instanceof APIError ? 'handled' :
        /illegal invocation|this.*(type|object)|receiver/i.test(detail) ? 'runtime_invocation' :
        /redirect/i.test(detail) ? 'redirect' :
        /certificate|ssl|tls/i.test(detail) ? 'tls' :
        /dns|resolve/i.test(detail) ? 'dns' :
        /network|connection|fetch failed/i.test(detail) ? 'network' :
        /different request|I\/O/i.test(detail) ? 'request_scope' :
        /abort|timeout/i.test(detail) ? 'timeout' : 'unclassified';
      // Fixed diagnostic fields only: never log request headers, URLs, body, or raw exceptions.
      if (safe.status >= 500) console.warn(JSON.stringify({ event: 'stickerbridge_error',
        stage, code: safe.code, upstreamStatus, failureKind }));
      return json({ error: { code: safe.code, retryable: safe.retryable } }, safe.status,
        safe.retryAfter ? { 'retry-after': String(safe.retryAfter) } : {});
    } finally { clearTimeout(timeout); }
  };
}

export default {
  fetch(request: Request, env: Env, context: Context) {
    const runtime = globalThis as typeof globalThis & { caches?: { default: WorkerCache } };
    return createHandler({ fetch: globalThis.fetch.bind(globalThis), cache: runtime.caches?.default })(request, env, context);
  }
};
