import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient } from '@supabase/supabase-js';

const urlSupabase = process.env.EXPO_PUBLIC_SUPABASE_URL;
const kunciAnonSupabase = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

if (!urlSupabase || !kunciAnonSupabase) {
  throw new Error(
    'EXPO_PUBLIC_SUPABASE_URL dan EXPO_PUBLIC_SUPABASE_ANON_KEY wajib diisi di .env',
  );
}

export const klienSupabase = createClient(urlSupabase, kunciAnonSupabase, {
  auth: {
    storage: AsyncStorage,
    autoRefreshToken: true,
    persistSession: true,
    // Di RN gak ada alamat web buat dibaca sessionnya dari situ -- sesi
    // ditangani manual lewat exchangeCodeForSession, lihat lib/loginGoogle.ts.
    detectSessionInUrl: false,
  },
});
