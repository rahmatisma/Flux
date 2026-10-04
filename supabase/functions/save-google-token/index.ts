import { createClient } from 'npm:@supabase/supabase-js@2'

// Edge Function ini satu-satunya jalan nulis ke tabel google_tokens (tabel itu
// sengaja dikunci total dari client lewat RLS -- lihat architecture.md Section 3).
// Dipanggil dari web/mobile tepat setelah login Google berhasil, karena
// refresh token cuma dikasih Google sekali, pas itu juga.

// Browser selalu nolak kirim request lintas-origin (misal dari localhost:5173
// ke *.supabase.co) kecuali server ini eksplisit ngasih izin lewat header ini --
// tanpa ini, request-nya gak akan pernah nyampe ke sini sama sekali.
const headerCors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (permintaan) => {
  // Browser ngirim request "OPTIONS" dulu buat nanya izin (preflight) sebelum
  // POST beneran -- wajib dijawab di sini, kalau nggak POST-nya gak akan dikirim.
  if (permintaan.method === 'OPTIONS') {
    return new Response('ok', { headers: headerCors })
  }

  if (permintaan.method !== 'POST') {
    return new Response('Method not allowed', { status: 405, headers: headerCors })
  }

  const headerOtorisasi = permintaan.headers.get('Authorization')
  if (!headerOtorisasi) {
    return new Response('Unauthorized', { status: 401, headers: headerCors })
  }

  let tokenRefresh: unknown
  try {
    const body = await permintaan.json()
    tokenRefresh = body.tokenRefresh
  } catch {
    return new Response('Body harus JSON', { status: 400, headers: headerCors })
  }

  if (typeof tokenRefresh !== 'string' || tokenRefresh.length === 0) {
    return new Response('tokenRefresh wajib diisi', { status: 400, headers: headerCors })
  }

  const urlSupabase = Deno.env.get('SUPABASE_URL')!
  const kunciAnon = Deno.env.get('SUPABASE_ANON_KEY')!
  const kunciServiceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  // Verifikasi identitas pemanggil pakai token dia sendiri (bukan service role),
  // supaya cuma user yang beneran login yang bisa trigger penyimpanan ini.
  const klienAuth = createClient(urlSupabase, kunciAnon, {
    global: { headers: { Authorization: headerOtorisasi } },
  })
  const { data: dataPengguna, error: errorPengguna } = await klienAuth.auth.getUser()
  if (errorPengguna || !dataPengguna.user?.email) {
    return new Response('Unauthorized', { status: 401, headers: headerCors })
  }

  // Dari sini baru pakai service role, karena google_tokens & app_settings
  // tertutup total dari role client biasa.
  const klienAdmin = createClient(urlSupabase, kunciServiceRole)

  const { data: pengaturanPemilik } = await klienAdmin
    .from('app_settings')
    .select('owner_email')
    .maybeSingle()

  const emailCocok =
    pengaturanPemilik?.owner_email.toLowerCase() === dataPengguna.user.email.toLowerCase()

  if (!emailCocok) {
    return new Response('Forbidden', { status: 403, headers: headerCors })
  }

  const { data: tokenLama } = await klienAdmin
    .from('google_tokens')
    .select('id')
    .maybeSingle()

  const hasilSimpan = tokenLama
    ? await klienAdmin
        .from('google_tokens')
        .update({ refresh_token: tokenRefresh })
        .eq('id', tokenLama.id)
    : await klienAdmin.from('google_tokens').insert({ refresh_token: tokenRefresh })

  if (hasilSimpan.error) {
    return new Response('Gagal menyimpan token', { status: 500, headers: headerCors })
  }

  return new Response(JSON.stringify({ message: 'ok' }), {
    headers: { ...headerCors, 'Content-Type': 'application/json' },
  })
})
