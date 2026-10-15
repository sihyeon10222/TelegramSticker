export const MAX_BYTES = 2 * 1024 * 1024; // Metadata only.
export const MAX_FILE_BYTES = 20 * 1024 * 1024; // Telegram cloud Bot API limit.
export const namePattern = /^[A-Za-z0-9_]{1,64}$/;
export const idPattern = /^[a-f0-9]{64}$/;
export const isObject = (v: unknown): v is Record<string, any> => !!v && typeof v === 'object' && !Array.isArray(v);
export const boundedString = (v: unknown, max: number): v is string => typeof v === 'string' && v.length > 0 && v.length <= max;
export const dimension = (v: unknown): v is number => Number.isInteger(v) && Number(v) > 0 && Number(v) <= 4096;
