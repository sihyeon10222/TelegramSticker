import type { Runtime, Env, Context, RequestDiagnostics } from './platform/types.ts';
import { APIError, json } from './platform/response.ts';
import { boundedString } from './platform/validation.ts';
import { authorized, validSession } from './features/sessions/session.ts';
import { sessionRoute } from './features/sessions/routes.ts';
import { gallery } from './features/gallery/routes.ts';
import { packRoute } from './features/packs/routes.ts';

export function createHandler(runtime: Runtime) {
  return async (request: Request, env: Env, context: Context): Promise<Response> => {
    // One deadline covers upstream calls AND reading bodies; no token-bearing exception escapes.
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15_000);
    const diagnostics: RequestDiagnostics = { stage: 'configuration' };
    try {
      if (!boundedString(env.BOT_TOKEN, 256) || !/^[0-9]+:[A-Za-z0-9_-]+$/.test(env.BOT_TOKEN) ||
          !boundedString(env.ACCESS_KEY, 256) || env.ACCESS_KEY.length < 24 || !env.PACK_LIMIT || !env.ASSET_LIMIT) {
        throw new APIError(503, 'server_not_configured');
      }
      const publicSessions = env.PUBLIC_IMPORT_ENABLED === 'true';
      if (new URL(request.url).pathname === '/v1/session') {
        diagnostics.stage = 'session';
        return await sessionRoute(request, env);
      }
      diagnostics.stage = 'authentication';
      if (!(await authorized(request, env.ACCESS_KEY)) &&
          !(publicSessions && await validSession(request, env.ACCESS_KEY))) throw new APIError(401, 'unauthorized');
      if (request.method !== 'GET') throw new APIError(405, 'method_not_allowed');
      const url = new URL(request.url);
      if (url.pathname === '/v1/gallery') {
        if (url.search || url.hash) throw new APIError(400, 'invalid_request');
        const key = request.headers.get('cf-connecting-ip') ?? 'local';
        if (!(await env.PACK_LIMIT.limit({ key })).success) throw new APIError(429, 'rate_limited', true, 60);
        diagnostics.stage = 'gallery';
        return await gallery(env);
      }
      return await packRoute(request, env, context, runtime, controller.signal, diagnostics);
    } catch (error) {
      const safe = error instanceof APIError ? error : new APIError(502, controller.signal.aborted ? 'timeout' : 'upstream_unavailable', true);
      const detail = error instanceof Error ? error.message : '';
      const failureKind = error instanceof APIError ? 'handled' :
        /illegal invocation|this.*(type|object)|receiver/i.test(detail) ? 'runtime_invocation' :
        /redirect/i.test(detail) ? 'redirect' :
        /certificate|ssl|tls/i.test(detail) ? 'tls' :
        /dns|resolve/i.test(detail) ? 'dns' :
        /network|connection|fetch failed/i.test(detail) ? 'network' :
        /different request|I\/O/i.test(detail) ? 'request_scope' :
        /abort|timeout/i.test(detail) ? 'timeout' : 'unclassified';
      // Fixed diagnostic fields only: never log request headers, URLs, body, or raw exceptions.
      if (safe.status >= 500) console.warn(JSON.stringify({ event: 'stickerbridge_error',
        stage: diagnostics.stage, code: safe.code, upstreamStatus: diagnostics.upstreamStatus, failureKind }));
      return json({ error: { code: safe.code, retryable: safe.retryable } }, safe.status,
        safe.retryAfter ? { 'retry-after': String(safe.retryAfter) } : {});
    } finally { clearTimeout(timeout); }
  };
}
