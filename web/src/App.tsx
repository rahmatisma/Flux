import './App.css'

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

function App() {
  return (
    <div className="halaman-utama">
      <header className="header">
        <h1>Flux</h1>
        <p className="tagline">
          Catat transaksi keuangan & kelola jadwal dalam satu tempat
        </p>
        <span className="status">Dalam pengembangan</span>
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
