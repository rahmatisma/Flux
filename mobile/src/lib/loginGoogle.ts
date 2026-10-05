import { makeRedirectUri } from 'expo-auth-session';
import * as QueryParams from 'expo-auth-session/build/QueryParams';
import * as WebBrowser from 'expo-web-browser';

import { klienSupabase } from '@/lib/supabaseClient';

// Wajib dipanggil sekali di awal supaya browser auth tau cara nutup diri
// sendiri & balik ke app setelah proses login selesai.
WebBrowser.maybeCompleteAuthSession();

const scopeCalendar = 'https://www.googleapis.com/auth/calendar';

// Supabase gak mau kirim balik langsung ke alamat khusus Expo Go
// ("exp://<ip>:<port>") -- selalu nyasar ke Site URL fallback walau udah
// didaftarin persis/wildcard sekalipun (sudah dicoba berkali-kali). Jadi
// alurnya dibikin lewat "halaman jembatan" di web dashboard yang didaftarin
// di Supabase pakai alamat https biasa (ini yang didukung), lalu halaman
// itu yang nerusin ke alamat exp:// app lewat JS di browser HP sendiri.
const urlRedirectApp = makeRedirectUri();
const urlJembatan = `https://flux-lac-xi.vercel.app/mobile-bridge.html?app=${encodeURIComponent(urlRedirectApp)}`;

async function buatSesiDariUrl(url: string) {
  const { params, errorCode } = QueryParams.getQueryParams(url);

  if (errorCode) {
    throw new Error(errorCode);
  }

  const { access_token: tokenAkses, refresh_token: tokenRefresh } = params;

  if (!tokenAkses || !tokenRefresh) {
    return null;
  }

  const { data: dataSesi, error: errorSetSesi } = await klienSupabase.auth.setSession({
    access_token: tokenAkses,
    refresh_token: tokenRefresh,
  });

  if (errorSetSesi) {
    throw errorSetSesi;
  }

  // provider_refresh_token cuma ada sesaat di sini, sama kayak di web --
  // harus langsung dikirim ke Edge Function, gak akan muncul lagi setelahnya.
  if (params.provider_refresh_token) {
    await klienSupabase.functions
      .invoke('save-google-token', {
        body: { tokenRefresh: params.provider_refresh_token },
      })
      .catch((errorSimpanToken) => {
        console.error('Gagal menyimpan refresh token Google:', errorSimpanToken);
      });
  }

  return dataSesi.session;
}

export async function loginDenganGoogle() {
  const { data, error } = await klienSupabase.auth.signInWithOAuth({
    provider: 'google',
    options: {
      redirectTo: urlJembatan,
      scopes: scopeCalendar,
      queryParams: { access_type: 'offline', prompt: 'consent' },
      skipBrowserRedirect: true,
    },
  });

  if (error || !data?.url) {
    throw error ?? new Error('Gagal membuat URL login Google');
  }

  // Tetap tunggu alamat exp:// app (bukan alamat halaman jembatannya) --
  // ini yang dipakai browser auth buat tau kapan harus "nutup diri" dan
  // ngelempar kontrol balik ke app.
  const hasilBrowser = await WebBrowser.openAuthSessionAsync(data.url, urlRedirectApp);

  if (hasilBrowser.type !== 'success' || !hasilBrowser.url) {
    return null;
  }

  return buatSesiDariUrl(hasilBrowser.url);
}

export async function logoutGoogle() {
  await klienSupabase.auth.signOut();
}
