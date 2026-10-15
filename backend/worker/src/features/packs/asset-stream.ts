import { APIError } from '../../platform/response.ts';
import { MAX_FILE_BYTES } from '../../integrations/telegram/limits.ts';
import { contentType } from './content-type.ts';

export async function streamAsset(response: Response, thumbnail: boolean, format: string) {
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
