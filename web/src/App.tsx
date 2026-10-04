import { useEffect, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import './App.css'
import { klienSupabase } from './lib/supabaseClient'

const daftarFitur = [
  {
    judul: 'Transaksi',
    deskripsi: 'Catat pemasukan & pengeluaran, sinkron otomatis ke Google Sheets.',
  },
  {
    judul: 'Goal Nabung',
    deskripsi: 'Nabung dengan tujuan jelas lewat kantong tabungan terpisah.',
  },
  {
    judul: 'Budget',
    deskripsi: 'Kontrol pengeluaran per kategori, mingguan atau bulanan.',
  },
  {
    judul: 'Kalender',
    deskripsi: 'Hubungkan jadwal dengan transaksi yang terkait.',
  },
]

const scopeCalendar = 'https://www.googleapis.com/auth/calendar'

function App() {
  const [sesi, setSesi] = useState<Session | null>(null)
  const [sedangMuat, setSedangMuat] = useState(true)

  useEffect(() => {
    klienSupabase.auth.getSession().then(({ data }) => {
      setSesi(data.session)
      setSedangMuat(false)
    })

    const { data: langganan } = klienSupabase.auth.onAuthStateChange((event, sesiBaru) => {
      setSesi(sesiBaru)

      // provider_refresh_token cuma ada sesaat setelah redirect balik dari Google --
      // harus ditangkep & dikirim ke Edge Function di sini, gak akan muncul lagi setelahnya.
      if (event === 'SIGNED_IN' && sesiBaru?.provider_refresh_token) {
        klienSupabase.functions
          .invoke('save-google-token', {
            body: { tokenRefresh: sesiBaru.provider_refresh_token },
          })
          .catch((error) => {
            console.error('Gagal menyimpan refresh token Google:', error)
          })
      }
    })

    return () => langganan.subscription.unsubscribe()
  }, [])

  async function tanganiLoginGoogle() {
    await klienSupabase.auth.signInWithOAuth({
      provider: 'google',
      options: {
        scopes: scopeCalendar,
        queryParams: { access_type: 'offline', prompt: 'consent' },
      },
    })
  }

  async function tanganiLogout() {
    await klienSupabase.auth.signOut()
  }

  return (
    <div className="halaman-utama">
      <header className="header">
        <h1>Flux</h1>
        <p className="tagline">
          Catat transaksi keuangan & kelola jadwal dalam satu tempat
        </p>
        <span className="status">Dalam pengembangan</span>

        <div className="area-login">
          {sedangMuat ? null : sesi ? (
            <>
              <span className="info-akun">Login sebagai {sesi.user.email}</span>
              <button type="button" className="tombol-login" onClick={tanganiLogout}>
                Keluar
              </button>
            </>
          ) : (
            <button type="button" className="tombol-login" onClick={tanganiLoginGoogle}>
              Login dengan Google
            </button>
          )}
        </div>
      </header>

      <main className="daftar-fitur">
        {daftarFitur.map((fitur) => (
          <div className="kartu-fitur" key={fitur.judul}>
            <h2>{fitur.judul}</h2>
            <p>{fitur.deskripsi}</p>
          </div>
        ))}
      </main>
    </div>
  )
}

export default App
