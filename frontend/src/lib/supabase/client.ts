import { createClient } from '@supabase/supabase-js'

let client: ReturnType<typeof createClient> | undefined

export function getSupabaseClient() {
  if (client) return client

  const url = import.meta.env.VITE_SUPABASE_URL
  const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

  if (!url || !anonKey) {
    throw new Error('Faltan VITE_SUPABASE_URL y VITE_SUPABASE_ANON_KEY en el entorno.')
  }

  client = createClient(url, anonKey)
  return client
}
