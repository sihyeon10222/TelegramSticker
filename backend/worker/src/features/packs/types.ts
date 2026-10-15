export interface StoredSticker {
  id: string; format: string; width: number; height: number; emoji?: string;
  fileSize?: number; fileID: string; thumbnailID?: string;
}
export interface StoredPack { name: string; title: string; stickerType: string; stickers: StoredSticker[]; fetchedAt: number }
