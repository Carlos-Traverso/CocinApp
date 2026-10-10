import type { ShoppingItem, ShoppingSuggestion } from '../domain/shopping'
import type { AdminStorageData } from '../../admin/data/localAdminStore'

export interface ShoppingRepository {
  list(): Promise<ShoppingItem[]>
  save(items: ShoppingItem[]): Promise<void>
  append(suggestions: ShoppingSuggestion[]): Promise<ShoppingItem[]>
  setPurchased(id: string, checked: boolean): Promise<ShoppingItem[]>
  markAllPurchased(): Promise<ShoppingItem[]>
  transferPurchased(): Promise<{ items: ShoppingItem[]; transferredCount: number; removedCount: number }>
  load(): Promise<{ items: ShoppingItem[]; catalog: AdminStorageData }>
  suggestionsFromFavorites(): Promise<ShoppingSuggestion[]>
  suggestionsFromWeek(dates: string[]): Promise<ShoppingSuggestion[]>
  suggestionsForRestock(): Promise<ShoppingSuggestion[]>
}
