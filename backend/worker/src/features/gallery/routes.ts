import type { Env } from '../../platform/types.ts';
import { APIError, json } from '../../platform/response.ts';
import { digest } from '../../platform/digest.ts';

export async function gallery(env: Env): Promise<Response> {
  if (!env.GALLERY_CATALOG) throw new APIError(503, 'gallery_not_configured');
  const text = await env.GALLERY_CATALOG.get('recommended-packs', { cacheTtl: 60 });
  if (text === null) throw new APIError(503, 'gallery_not_configured');
  if (new TextEncoder().encode(text).length > 65536) throw new APIError(503, 'gallery_catalog_invalid');
  const names: string[] = [];
  for (const line of text.split(/\r?\n/).map(v => v.trim()).filter(Boolean)) {
    let url: URL;
    try { url = new URL(line); } catch { throw new APIError(503, 'gallery_catalog_invalid'); }
    const match = /^\/addstickers\/([A-Za-z0-9_]{1,64})\/?$/.exec(url.pathname);
    if (url.protocol !== 'https:' || !['t.me', 'telegram.me'].includes(url.hostname) ||
        url.username || url.password || url.port || url.search || url.hash || !match) {
      throw new APIError(503, 'gallery_catalog_invalid');
    }
    const name = match[1].toLowerCase();
    if (!names.includes(name)) names.push(name);
    if (names.length > 200) throw new APIError(503, 'gallery_catalog_invalid');
  }
  return json({ schemaVersion: 1, revision: await digest(names.join('\n')),
    packs: names.map(name => ({ name, link: `https://t.me/addstickers/${name}` })) });
}
