import { digest } from '../../platform/digest.ts';

export async function authorized(request: Request, key: string): Promise<boolean> {
  const supplied = request.headers.get('authorization') ?? '';
  if (supplied.length > 512) return false;
  const a = await digest(supplied), b = await digest(`Bearer ${key}`);
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return difference === 0;
}
// Public, rate-limited sessions are not proof of app integrity. No provider secret leaves the Worker.
async function sessionKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey('raw', new TextEncoder().encode(`stickerbridge-session-v1:${secret}`),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
}
function hex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)].map(v => v.toString(16).padStart(2, '0')).join('');
}
export async function issueSession(secret: string): Promise<{ token: string; expiresAt: number }> {
  const expiresAt = Math.floor(Date.now() / 1000) + 3600;
  const payload = `sb1.${expiresAt}.${crypto.randomUUID()}`;
  const signature = await crypto.subtle.sign('HMAC', await sessionKey(secret), new TextEncoder().encode(payload));
  return { token: `${payload}.${hex(signature)}`, expiresAt };
}
export async function validSession(request: Request, secret: string): Promise<boolean> {
  const value = request.headers.get('authorization') ?? '';
  const match = /^Bearer (sb1\.([0-9]{10})\.[0-9a-f-]{36})\.([0-9a-f]{64})$/.exec(value);
  if (!match) return false;
  const remaining = Number(match[2]) - Math.floor(Date.now() / 1000);
  if (remaining <= 0 || remaining > 3600) return false;
  const signature = Uint8Array.from(match[3].match(/../g)!, byte => parseInt(byte, 16));
  return crypto.subtle.verify('HMAC', await sessionKey(secret), signature, new TextEncoder().encode(match[1]));
}
