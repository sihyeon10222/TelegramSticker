import type { Env } from '../../platform/types.ts';
import { APIError, json } from '../../platform/response.ts';
import { issueSession } from './session.ts';

export async function sessionRoute(request: Request, env: Env): Promise<Response> {
  if (env.PUBLIC_IMPORT_ENABLED !== 'true' || request.method !== 'POST' || new URL(request.url).search) {
    throw new APIError(400, 'invalid_request');
  }
  const key = request.headers.get('cf-connecting-ip') ?? 'local';
  if (!(await env.PACK_LIMIT.limit({ key })).success) throw new APIError(429, 'rate_limited', true, 60);
  return json(await issueSession(env.ACCESS_KEY));
}
