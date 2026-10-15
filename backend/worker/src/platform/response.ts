export class APIError extends Error {
  status: number; code: string; retryable: boolean; retryAfter?: number;
  constructor(status: number, code: string, retryable = false, retryAfter?: number) {
    super(code); this.status = status; this.code = code; this.retryable = retryable; this.retryAfter = retryAfter;
  }
}

export function json(value: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(value), { status, headers: {
    'content-type': 'application/json', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff', ...extra
  } });
}
