import type { Env, Runtime, RequestDiagnostics } from '../../platform/types.ts';
import type { TelegramClient } from './client.ts';
import { APIError } from '../../platform/response.ts';
import { boundedString } from '../../platform/validation.ts';
import { MAX_FILE_BYTES } from './limits.ts';

export async function downloadTelegramFile(fileID: string, upstream: TelegramClient, runtime: Runtime,
  env: Env, signal: AbortSignal, diagnostics: RequestDiagnostics): Promise<Response> {
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
    return response;
  }
  throw new APIError(502, 'upstream_unavailable', true);
}
