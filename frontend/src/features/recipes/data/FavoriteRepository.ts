export interface FavoriteRepository {
  listIds(): Promise<string[]>
  saveIds(ids: string[]): Promise<void>
}
