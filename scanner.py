import os
import sys
import json
from pathlib import Path
from dotenv import load_dotenv
from pydantic import BaseModel, Field
from google import genai
from google.genai import types

load_dotenv()

# Skema data transaksi yang diharapkan dari bukti transfer/struk
class TransactionData(BaseModel):
    status: str = Field(description="Status transaksi: 'BERHASIL', 'PENDING', atau 'GAGAL'")
    flow_type: str = Field(description="Arus keuangan: 'PEMASUKAN' (uang masuk/transfer masuk) atau 'PENGELUARAN' (uang keluar/belanja/transfer keluar)")
    source_platform: str = Field(description="Nama bank atau e-wallet (contoh: 'ShopeePay', 'BCA', 'Livin by Mandiri', 'GoPay', 'DANA', 'OVO', 'BRImo', dll)")
    transaction_type: str = Field(description="Tipe transaksi: 'TRANSFER_BANK', 'QRIS', 'TOPUP', 'TAGIHAN', 'BELANJA_MERCHANT'")
    amount: float = Field(description="Nominal transaksi bersih")
    admin_fee: float = Field(default=0.0, description="Biaya admin atau biaya layanan jika ada (0 jika gratis)")
    total_amount: float = Field(description="Total nominal transaksi")
    sender_name: str | None = Field(default=None, description="Nama pengirim dana")
    recipient_name: str = Field(description="Nama penerima dana atau nama merchant")
    destination_bank_or_wallet: str | None = Field(default=None, description="Bank/E-wallet tujuan (contoh: 'Bank Mandiri', 'BCA', dll)")
    destination_account: str | None = Field(default=None, description="Nomor rekening atau nomor e-wallet tujuan")
    transaction_date: str = Field(description="Tanggal transaksi format YYYY-MM-DD")
    transaction_time: str | None = Field(default=None, description="Waktu transaksi format HH:mm:ss atau HH:mm")
    reference_number: str | None = Field(default=None, description="Order SN atau nomor referensi transaksi")
    description: str | None = Field(default=None, description="Catatan, berita, atau deskripsi transfer (misal: 'Patungan wifi')")
    category: str = Field(description="Kategori pencatatan: 'Tagihan & Utilitas', 'Makanan & Minuman', 'Belanja', 'Transportasi', 'Transfer/Patungan', 'Hiburan', 'Gaji/Pendapatan', 'Lainnya'")


def scan_receipt(file_path: str) -> TransactionData:
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        print("\n[PERINGATAN] GEMINI_API_KEY belum disetel.")
        print("Silakan masukkan GEMINI_API_KEY Anda di file .env atau export GEMINI_API_KEY='key_anda'\n")
        sys.exit(1)

    path = Path(file_path)
    if not path.exists():
        raise FileNotFoundError(f"File tidak ditemukan: {file_path}")

    # Tentukan mime type
    suffix = path.suffix.lower()
    mime_map = {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".webp": "image/webp",
        ".pdf": "application/pdf"
    }
    mime_type = mime_map.get(suffix, "image/jpeg")

    with open(path, "rb") as f:
        file_bytes = f.read()

    client = genai.Client(api_key=api_key)

    prompt = """
    Kamu adalah asisten keuangan pintar spesialis struk dan bukti transfer perbankan/e-wallet Indonesia.
    Analisis gambar/dokumen bukti transaksi terlampir dengan sangat teliti.
    
    Tugasmu:
    1. Identifikasi platform bank atau e-wallet (ShopeePay, BCA, Livin Mandiri, BRImo, DANA, GoPay, OVO, dll).
    2. Deteksi status transaksi (apakah Berhasil/Sukses).
    3. Deteksi pengirim dan penerima secara jelas:
       - Nama pengirim (misal: 'Muhammad ******')
       - Nama penerima (misal: 'ANDIKA RAMADHAN YUSU')
       - Bank/e-wallet dan nomor rekening tujuan (misal: 'Bank Mandiri', '1670010166980')
    4. Tentukan arus transaksi (flow_type):
       - Jika bukti menunjukkan uang ditransfer masuk ke rekening pemilik (contoh: 'Kirim Ke: ANDIKA RAMADHAN YUSU' dan user membuka/menerima bukti ini), tandai sebagai 'PEMASUKAN' atau sesuaikan dengan konteks.
       - Jika pengguna yang mengirim/membayar, tandai 'PENGELUARAN'.
    5. Ambil nominal transfer (amount), biaya admin (jika gratis/0 maka 0), dan total_amount.
    6. Ambil tanggal dan waktu secara presisi (contoh: 01 Okt 2026, 06:43 -> 2026-10-01, 06:43).
    7. Ambil catatan/deskripsi transaksi jika ada (contoh: 'Patungan wifi') serta nomor referensi / Order SN.
    8. Tentukan kategori yang paling tepat (misal: jika ada deskripsi 'Patungan wifi' -> 'Tagihan & Utilitas' atau 'Transfer/Patungan').
    
    Ekstrak data tersebut secara ketat sesuai skema JSON yang telah ditentukan.
    """

    response = client.models.generate_content(
        model="gemini-2.5-flash",
        contents=[
            types.Part.from_bytes(data=file_bytes, mime_type=mime_type),
            prompt
        ],
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
            response_schema=TransactionData,
            temperature=0.1,
        )
    )

    data = TransactionData.model_validate_json(response.text)
    return data

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Penggunaan: python scanner.py <path_ke_bukti_transfer_atau_gambar>")
        print("Contoh: python scanner.py bukti_bca.jpg")
        sys.exit(1)

    file_path = sys.argv[1]
    print(f"[*] Memproses bukti transaksi: {file_path} ...")
    try:
        result = scan_receipt(file_path)
        print("\n=== HASIL EKSTRAKSI TRANSAKSI ===")
        print(json.dumps(result.model_dump(), indent=2, ensure_ascii=False))
        print("=================================\n")
        print(f"✅ Berhasil dideteksi:")
        print(f"   • Arus Dana : {'🟢 PEMASUKAN (+)' if result.flow_type == 'PEMASUKAN' else '🔴 PENGELUARAN (-)'}")
        print(f"   • Platform  : {result.source_platform}")
        print(f"   • Tipe      : {result.transaction_type}")
        print(f"   • Pengirim  : {result.sender_name}")
        print(f"   • Penerima  : {result.recipient_name} ({result.destination_bank_or_wallet} {result.destination_account})")
        print(f"   • Nominal   : Rp {result.total_amount:,.0f}".replace(",", "."))
        print(f"   • Deskripsi : {result.description or '-'}")
        print(f"   • Kategori  : {result.category}")
        print(f"   • Waktu     : {result.transaction_date} {result.transaction_time or ''}")
        print(f"   • Ref/SN    : {result.reference_number or '-'}")
    except Exception as e:
        print(f"\n❌ Gagal memproses: {e}")
