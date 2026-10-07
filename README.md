# CatatDuit 💳

Aplikasi Android cerdas pencatat pemasukan dan pengeluaran secara otomatis melalui tangkapan layar (screenshot) dan share bukti transfer m-Banking / e-Wallet (Livin' by Mandiri, BCA Mobile, BRImo, BNI, DANA, GoPay, ShopeePay, QRIS, dsb).

**100% Offline & On-Device** — Tidak memerlukan API Key atau server eksternal, seluruh pemrosesan Optical Character Recognition (OCR) dilakukan langsung di dalam perangkat menggunakan **Google ML Kit** dan pemotong gambar terintegrasi (**uCrop**).

---

## ✨ Fitur Utama

- ⚡ **100% Offline & Tanpa API Key**: Memanfaatkan Google ML Kit Text Recognition on-device, cepat, hemat baterai, dan aman bagi privasi data perbankan.
- ✂️ **Interactive Image Cropper**: Potong screenshot mutasi rekening atau struk belanja untuk menghilangkan elemen yang tidak perlu (saldo utama, jam, status bar baterai) agar nominal terbaca 100% presisi.
- 🔄 **Share Sheet Integration (Android Send Intent)**: Bagikan bukti transfer langsung dari aplikasi m-Banking atau Galeri ke CatatDuit tanpa perlu membuka aplikasi terlebih dahulu.
- ✍️ **Pencatatan Transaksi Manual (Kas / Tunai)**: Catat transaksi tunai sehari-hari (warteg, parkir, belanja pasar) lengkap dengan kategori, metode pembayaran, dan tanggal fleksibel.
- 📤 **Ekspor Laporan Bulanan (CSV & WhatsApp)**: Unduh data ke file CSV spreadsheet untuk dibuka di Excel/Google Sheets atau salin ringkasan teks terformat rapi untuk dibagikan ke WhatsApp.
- 📊 **Distribusi Pengeluaran per Kategori**: Pantau ke mana saja uang Anda pergi lewat bar persentase visual pengeluaran bulanan.
- 🔍 **Pencarian & Filter Arus Real-Time**: Temukan transaksi dalam hitungan detik dengan pencarian toko/catatan serta filter chip (*Semua*, *🟢 Uang Masuk*, *🔴 Uang Keluar*).
- 🟢🔴 **Smart Flow Detection (Pemasukan vs Pengeluaran)**: Otomatis mendeteksi transfer masuk/keluar dari mutasi bank (tanda `+`/`-`, `CR`/`DB`, atau nama pemilik akun).
- 📅 **Rekap & Sisa Saldo Bulanan**: Menyimpan riwayat mutasi per bulan dengan kartu ringkasan Pemasukan, Pengeluaran, dan Sisa Dana.
- ✏️ **Koreksi Cepat & Detail Transaksi**: Ketuk transaksi untuk melihat detail lengkap atau menghapusnya, serta koreksi nominal instan jika OCR membutuhkan penyesuaian.

---

## 📱 Alur Penggunaan

1. **Tambah Transaksi**:
   - **Scan Otomatis**: Pilih foto/screenshot dari galeri atau kamera, potong area nominal, lalu konfirmasi.
   - **Share Langsung**: Dari m-Banking/e-Wallet, tekan *Share* lalu pilih **CatatDuit**.
   - **Input Manual**: Tekan *Tambah Transaksi* lalu pilih *Catat Manual* untuk pembayaran kas/tunai.
2. **Kelola & Pantau**:
   - Gunakan filter atau pencarian untuk mengecek transaksi tertentu.
   - Perhatikan bar distribusi kategori untuk evaluasi anggaran bulanan.
3. **Ekspor Laporan**:
   - Tekan ikon *Ekspor* di pojok kanan atas untuk menyalin laporan teks ke WhatsApp atau menyimpan file `.csv`.

---

## 📁 Struktur Direktori

```text
scan-keuangan/
├── app/                              # Aplikasi Flutter Android
│   ├── android/                      # Native Android manifests, uCrop activity, intent filters
│   └── lib/
│       ├── main.dart                 # Dashboard, search, manual input, cropper & UI
│       ├── models/
│       │   └── transaction_model.dart # Schema model transaksi
│       └── services/
│           ├── receipt_parser.dart   # Engine parsing cerdas regex mutasi m-banking & e-wallet
│           ├── scanner_service.dart  # Google ML Kit on-device OCR engine
│           └── storage_service.dart  # Persistensi lokal & exporter CSV / ringkasan teks
├── sample_shopeepay.png              # Contoh gambar bukti transfer untuk pengujian
├── scanner.py                        # (Opsional) Prototipe parser python
└── README.md
```

---

## 🛠️ Cara Menjalankan

### Prasyarat
- Flutter SDK (>= 3.13.x)
- Android SDK (API 21+)
- Perangkat Android atau Emulator

### Build & Jalankan
```bash
cd app
flutter pub get
flutter run
```

### Build APK Rilis
```bash
cd app
flutter build apk --release
# File APK akan tersedia di: app/build/app/outputs/flutter-apk/app-release.apk
```

---

## 📄 Lisensi
MIT License © 2026 Andika Ramadhan
