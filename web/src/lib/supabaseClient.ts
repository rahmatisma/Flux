import { createClient } from '@supabase/supabase-js'

const urlSupabase = import.meta.env.VITE_SUPABASE_URL
const kunciAnonSupabase = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!urlSupabase || !kunciAnonSupabase) {
  throw new Error('VITE_SUPABASE_URL dan VITE_SUPABASE_ANON_KEY wajib diisi di .env')
}

export const klienSupabase = createClient(urlSupabase, kunciAnonSupabase)
