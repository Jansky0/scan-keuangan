# CatatDuit 💳

Aplikasi Android cerdas pencatat pemasukan dan pengeluaran secara otomatis melalui tangkapan layar (screenshot) dan share bukti transfer m-Banking / e-Wallet (Livin' by Mandiri, BCA Mobile, BRImo, BNI, DANA, GoPay, ShopeePay, QRIS, dsb).

**100% Offline & On-Device** — Tidak memerlukan API Key atau server eksternal, seluruh pemrosesan Optical Character Recognition (OCR) dilakukan langsung di dalam perangkat menggunakan **Google ML Kit** dan pemotong gambar terintegrasi (**uCrop**).

---

## ✨ Fitur Utama

- ⚡ **100% Offline & Tanpa API Key**: Memanfaatkan Google ML Kit Text Recognition on-device, cepat, hemat baterai, dan aman bagi privasi data perbankan.
- ✂️ **Interactive Image Cropper**: Potong screenshot mutasi rekening atau struk belanja untuk menghilangkan elemen yang tidak perlu (saldo utama, jam, status bar baterai) agar nominal terbaca 100% presisi.
- 🔄 **Share Sheet Integration (Android Send Intent)**: Bagikan bukti transfer langsung dari aplikasi m-Banking atau Galeri ke CatatDuit tanpa perlu membuka aplikasi terlebih dahulu.
- 🟢🔴 **Smart Flow Detection (Pemasukan vs Pengeluaran)**: Otomatis mendeteksi transfer masuk/keluar dari mutasi bank (tanda `+`/`-`, `CR`/`DB`, atau nama pemilik akun).
- 📅 **Pengelompokan Bulanan & Ringkasan Anggaran**: Menyimpan riwayat mutasi per bulan dengan kartu ringkasan Pemasukan, Pengeluaran, dan Sisa Saldo.
- ✏️ **Koreksi Cepat & Kategori**: Dukungan edit instan jika ingin mengoreksi nominal serta memilih kategori transaksi (Makanan, Belanja, Tagihan, Hiburan, dll).

---

## 📱 Tangkapan Layar & Alur Penggunaan

1. **Share / Pilih Gambar**:
   - Bagikan gambar dari m-Banking ke **CatatDuit**, atau ketuk tombol **Pindai Bukti / Struk** di aplikasi.
2. **Crop Bagian Transaksi**:
   - Sesuaikan kotak pemotong pada bagian nominal dan detail transaksi.
3. **Konfirmasi & Simpan**:
   - Periksa ringkasan transaksi, sesuaikan tipe (*Uang Masuk* / *Uang Keluar*), lalu simpan ke rekap bulanan.

---

## 📁 Struktur Direktori

```text
scan-keuangan/
├── app/                              # Aplikasi Flutter Android
│   ├── android/                      # Native Android manifests, uCrop activity, intent filters
│   └── lib/
│       ├── main.dart                 # Dashboard, intent listener, cropper UI, & konfirmasi
│       ├── models/
│       │   └── transaction_model.dart # Schema model transaksi
│       └── services/
│           ├── receipt_parser.dart   # Engine parsing cerdas regex mutasi m-banking & e-wallet
│           ├── scanner_service.dart  # Google ML Kit on-device OCR engine
│           └── storage_service.dart  # Penyimpanan persisten lokal (SharedPreferences)
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
