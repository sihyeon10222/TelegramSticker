import { APIError } from '../../platform/response.ts';

export function contentType(bytes: Uint8Array, thumbnail: boolean, format: string): string {
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
