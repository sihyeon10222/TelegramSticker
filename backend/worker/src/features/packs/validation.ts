export const namePattern = /^[A-Za-z0-9_]{1,64}$/;
export const idPattern = /^[a-f0-9]{64}$/;
export const dimension = (v: unknown): v is number => Number.isInteger(v) && Number(v) > 0 && Number(v) <= 4096;
