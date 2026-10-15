import { APIError } from '../../platform/response.ts';
import { MAX_BYTES } from './limits.ts';

export async function bounded(response: Response): Promise<Uint8Array<ArrayBuffer>> {
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
