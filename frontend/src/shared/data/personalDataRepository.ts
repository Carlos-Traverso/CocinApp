import { supabase } from './supabaseClient'

export type PersonalDataKey = 'profile' | 'favorites' | 'meal_plan' | 'shopping' | 'cooking_progress' | 'cooking_history'

export async function loadPersonalData(key: PersonalDataKey): Promise<unknown | null> {
  if (!supabase) return null
  const { data: { user }, error: userError } = await supabase.auth.getUser()
  if (userError) throw userError
  if (!user) return null

  const { data, error } = await supabase
    .from('personal_data')
    .select('value')
    .eq('user_id', user.id)
    .eq('data_key', key)
    .maybeSingle()
  if (error) throw error
  return data?.value ?? null
}

export async function savePersonalData(key: PersonalDataKey, value: unknown): Promise<void> {
  if (!supabase) return
  const { data: { user }, error: userError } = await supabase.auth.getUser()
  if (userError) throw userError
  if (!user) throw new Error('Iniciá sesión para guardar tus datos personales.')

  const { error } = await supabase
    .from('personal_data')
    .upsert({ user_id: user.id, data_key: key, value, updated_at: new Date().toISOString() }, { onConflict: 'user_id,data_key' })
  if (error) throw error
}
