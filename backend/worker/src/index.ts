import type { Env, Context, WorkerCache } from './platform/types.ts';
import { createHandler } from './app.ts';

export { createHandler };

export default {
  fetch(request: Request, env: Env, context: Context) {
    const runtime = globalThis as typeof globalThis & { caches?: { default: WorkerCache } };
    return createHandler({ fetch: globalThis.fetch.bind(globalThis), cache: runtime.caches?.default })(request, env, context);
  }
};
