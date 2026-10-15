import type { Context, WorkerCache } from '../types.ts';
import { digest } from '../services/digest.ts';

export async function createWorkerCache(cache: WorkerCache | undefined, context: Context, token: string) {
  const namespace = await digest(token);
  const cacheKey = (suffix: string) => new Request(`https://stickerbridge-cache.invalid/v1/${namespace}/${suffix}`);
  const cacheGet = async (suffix: string) => {
    try { return await cache?.match(cacheKey(suffix)); } catch { return undefined; }
  };
  const cachePut = (suffix: string, value: Response, ttl: number) => {
    if (!cache) return;
    const cached = new Response(value.body, value);
    cached.headers.set('cache-control', `public, max-age=${ttl}`);
    context.waitUntil(cache.put(cacheKey(suffix), cached).catch(() => {}));
  };
  return { get: cacheGet, put: cachePut };
}
export type RequestCache = Awaited<ReturnType<typeof createWorkerCache>>;
