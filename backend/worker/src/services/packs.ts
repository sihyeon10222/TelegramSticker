import type { StoredPack, StoredSticker, RequestDiagnostics } from '../types.ts';
import type { RequestCache } from '../cache/worker-cache.ts';
import type { TelegramClient } from './telegram.ts';
import { APIError, json } from '../http/response.ts';
import { boundedString, dimension, isObject, namePattern } from '../validation/limits.ts';
import { digest } from './digest.ts';

export function createPackLoader(name: string, refresh: boolean, upstream: TelegramClient, cache: RequestCache, diagnostics: RequestDiagnostics) {
  return async (force = false): Promise<StoredPack> => {
    const cached = await cache.get(`packs/${name}`);
    if (cached && !refresh && !force) return await cached.json() as StoredPack;
    const result = await upstream('getStickerSet', { name });
    diagnostics.stage = 'pack_validation';
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
    cache.put(`packs/${name}`, json(pack), 600);
    return pack;
  };
}
