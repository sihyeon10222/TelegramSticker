export const isObject = (v: unknown): v is Record<string, any> => !!v && typeof v === 'object' && !Array.isArray(v);
export const boundedString = (v: unknown, max: number): v is string => typeof v === 'string' && v.length > 0 && v.length <= max;
