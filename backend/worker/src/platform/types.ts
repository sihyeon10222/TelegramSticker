// No runtime packages. Secrets are provided only through Worker bindings.
export interface Limiter { limit(options: { key: string }): Promise<{ success: boolean }> }
export interface GalleryKV { get(key: string, options: { cacheTtl: number }): Promise<string | null> }
export interface Env { GALLERY_CATALOG?: GalleryKV; BOT_TOKEN: string; ACCESS_KEY: string; PUBLIC_IMPORT_ENABLED?: string; PACK_LIMIT: Limiter; ASSET_LIMIT: Limiter }
export interface WorkerCache { match(key: Request): Promise<Response | undefined>; put(key: Request, value: Response): Promise<void> }
export interface Context { waitUntil(promise: Promise<unknown>): void }
export interface Runtime { fetch: typeof fetch; cache?: WorkerCache }
export interface RequestDiagnostics { stage: string; upstreamStatus?: number }
