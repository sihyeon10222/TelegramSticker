import type { Env, Runtime, RequestDiagnostics } from '../types.ts';
import { APIError } from '../http/response.ts';
import { bounded } from '../validation/response.ts';
import { isObject } from '../validation/limits.ts';

export function createTelegramClient(runtime: Runtime, env: Env, signal: AbortSignal, diagnostics: RequestDiagnostics) {
  return async (method: string, params: Record<string, string>): Promise<Record<string, any>> => {
    diagnostics.stage = method === 'getStickerSet' ? 'telegram_pack' : 'telegram_file';
    const response = await runtime.fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/${method}`, {
      method: 'POST', body: JSON.stringify(params), headers: { 'content-type': 'application/json' },
      redirect: 'manual', signal: signal
    });
    diagnostics.upstreamStatus = response.status;
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
}
export type TelegramClient = ReturnType<typeof createTelegramClient>;
