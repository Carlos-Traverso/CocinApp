import { supabase } from './supabaseClient'
import { assertPersonalDataOwner, assertPersonalDataSessionCurrent, capturePersonalDataSession, type PersonalDataSession } from './personalDataSession'

export type PersonalDataKey = 'profile' | 'favorites' | 'meal_plan' | 'shopping' | 'cooking_progress' | 'cooking_history'

export async function loadPersonalData(key: PersonalDataKey, session = capturePersonalDataSession()): Promise<unknown | null> {
  if (!supabase) return null
  assertPersonalDataSessionCurrent(session)
  const { data: { user }, error: userError } = await supabase.auth.getUser()
  if (userError) throw userError
  if (!user) return null
  assertPersonalDataOwner(session, user.id)

  const { data, error } = await supabase
    .from('personal_data')
    .select('value')
    .eq('user_id', user.id)
    .eq('data_key', key)
    .maybeSingle()
  if (error) throw error
  assertPersonalDataOwner(session, user.id)
  return data?.value ?? null
}

export async function savePersonalData(key: PersonalDataKey, value: unknown, session: PersonalDataSession = capturePersonalDataSession()): Promise<void> {
  if (!supabase) return
  assertPersonalDataSessionCurrent(session)
  const { data: { user }, error: userError } = await supabase.auth.getUser()
  if (userError) throw userError
  if (!user) throw new Error('Iniciá sesión para guardar tus datos personales.')
  assertPersonalDataOwner(session, user.id)

  const { error } = await supabase
    .from('personal_data')
    .upsert({ user_id: user.id, data_key: key, value, updated_at: new Date().toISOString() }, { onConflict: 'user_id,data_key' })
  if (error) throw error
  assertPersonalDataOwner(session, user.id)
}
