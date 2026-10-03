import '../models/transaction_model.dart';

class ReceiptParser {
  /// Mem-parsing teks hasil OCR dari struk/bukti transfer bank & e-wallet Indonesia
  static TransactionModel parse(String fullText, {String? userName}) {
    final lines = fullText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    // 1. Deteksi Platform
    String platform = _detectPlatform(fullText);

    // 2. Deteksi Nominal & Biaya Admin
    double totalAmount = _detectAmount(fullText);

    // 3. Deteksi Status
    String status = 'BERHASIL';
    if (fullText.toLowerCase().contains('gagal') || fullText.toLowerCase().contains('failed')) {
      status = 'GAGAL';
    } else if (fullText.toLowerCase().contains('pending') || fullText.toLowerCase().contains('menunggu')) {
      status = 'PENDING';
    }

    // 4. Deteksi Pengirim & Penerima
    String? sender = _extractSender(lines, fullText);
    String recipient = _extractRecipient(lines, fullText) ?? 'Penerima';

    // 5. Deteksi Tanggal & Waktu
    String date = _extractDate(fullText);
    String? time = _extractTime(fullText);

    // 6. Deteksi Deskripsi / Catatan Transfer
    String? description = _extractDescription(lines, fullText);

    // 7. Deteksi Nomor Referensi / Order SN
    String? reference = _extractReference(lines, fullText);

    // 8. Tentukan Arus Dana (Pemasukan vs Pengeluaran) dengan Heuristik Pintar
    String flowType = _determineFlowType(fullText, sender, recipient, userName: userName);

    // 9. Kategori Otomatis berdasarkan Deskripsi & Penerima
    String category = _determineCategory(description ?? '', recipient);

    return TransactionModel(
      status: status,
      flowType: flowType,
      sourcePlatform: platform,
      transactionType: 'TRANSFER_BANK',
      amount: totalAmount,
      adminFee: 0.0,
      totalAmount: totalAmount,
      senderName: sender,
      recipientName: recipient,
      destinationBankOrWallet: _extractBank(fullText),
      destinationAccount: _extractAccountNumber(fullText),
      transactionDate: date,
      transactionTime: time,
      referenceNumber: reference,
      description: description,
      category: category,
    );
  }

  static String _detectPlatform(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('shopeepay') || lower.contains('shopee')) return 'ShopeePay';
    if (lower.contains('dana')) return 'DANA';
    if (lower.contains('bca') || lower.contains('klikbca') || lower.contains('mybca')) return 'BCA';
    if (lower.contains('mandiri') || lower.contains('livin')) return 'Bank Mandiri';
    if (lower.contains('brimo') || lower.contains('bri')) return 'Bank BRI';
    if (lower.contains('bni') || lower.contains('wondr')) return 'Bank BNI';
    if (lower.contains('gopay') || lower.contains('gojek')) return 'GoPay';
    if (lower.contains('ovo')) return 'OVO';
    if (lower.contains('seabank')) return 'SeaBank';
    if (lower.contains('jago')) return 'Bank Jago';
    return 'Bank / E-Wallet';
  }

  static double _detectAmount(String text) {
    final reg = RegExp(r'Rp\s*([0-9\.\,]+)', caseSensitive: false);
    final matches = reg.allMatches(text);

    final amounts = <double>[];
    for (final m in matches) {
      final raw = m.group(1) ?? '';
      final clean = raw.replaceAll('.', '').replaceAll(',', '.');
      final val = double.tryParse(clean);
      if (val != null && val > 0 && val < 500000000) {
        amounts.add(val);
      }
    }

    if (amounts.isNotEmpty) {
      amounts.sort((a, b) => b.compareTo(a));
      return amounts.first;
    }

    final numReg = RegExp(r'\b([1-9][0-9]{0,2}(?:\.[0-9]{3})+)\b');
    final numMatches = numReg.allMatches(text);
    for (final m in numMatches) {
      final clean = (m.group(1) ?? '').replaceAll('.', '');
      final val = double.tryParse(clean);
      if (val != null && val >= 1000) return val;
    }

    return 0.0;
  }

  static String? _extractSender(List<String> lines, String fullText) {
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].toLowerCase();
      if (line.contains('dikirim dari') || line.contains('pengirim') || line.contains('dari:')) {
        if (lines[i].contains(':')) {
          final parts = lines[i].split(':');
          if (parts.length > 1 && parts[1].trim().isNotEmpty) {
            return parts[1].trim();
          }
        }
        if (i + 1 < lines.length) {
          return lines[i + 1].trim();
        }
      }
    }
    return null;
  }

  static String? _extractRecipient(List<String> lines, String fullText) {
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].toLowerCase();
      if (line.contains('kirim ke') || line.contains('penerima') || line.contains('tujuan')) {
        if (lines[i].contains(':')) {
          final parts = lines[i].split(':');
          if (parts.length > 1 && parts[1].trim().isNotEmpty) {
            return parts[1].trim();
          }
        }
        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1].trim();
          if (nextLine.isNotEmpty && !nextLine.toLowerCase().contains('bank')) {
            return nextLine;
          } else if (i + 2 < lines.length) {
            return lines[i + 2].trim();
          }
        }
      }
    }
    return null;
  }

  static String _extractDate(String text) {
    final dateReg = RegExp(
      r'(\d{1,2})\s+(Jan|Feb|Mar|Apr|Mei|Jun|Jul|Agu|Sep|Okt|Nov|Des)[a-z]*\s+(\d{4})',
      caseSensitive: false,
    );
    final match = dateReg.firstMatch(text);
    if (match != null) {
      final day = match.group(1)!.padLeft(2, '0');
      final monthStr = match.group(2)!.toLowerCase();
      final year = match.group(3)!;

      final months = {
        'jan': '01', 'feb': '02', 'mar': '03', 'apr': '04',
        'mei': '05', 'jun': '06', 'jul': '07', 'agu': '08',
        'sep': '09', 'okt': '10', 'nov': '11', 'des': '12',
      };
      final mCode = months[monthStr.substring(0, 3)] ?? '01';
      return '$year-$mCode-$day';
    }

    final numDateReg = RegExp(r'(\d{2})[\/\-](\d{2})[\/\-](\d{4})');
    final numMatch = numDateReg.firstMatch(text);
    if (numMatch != null) {
      return '${numMatch.group(3)}-${numMatch.group(2)}-${numMatch.group(1)}';
    }

    return DateTime.now().toIso8601String().substring(0, 10);
  }

  static String? _extractTime(String text) {
    final timeReg = RegExp(r'(\d{2}:\d{2}(?::\d{2})?)');
    final match = timeReg.firstMatch(text);
    return match?.group(1);
  }

  static String? _extractDescription(List<String> lines, String fullText) {
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].toLowerCase();
      if (line.contains('deskripsi') || line.contains('catatan') || line.contains('berita') || line.contains('keterangan')) {
        if (lines[i].contains(':')) {
          final parts = lines[i].split(':');
          if (parts.length > 1 && parts[1].trim().isNotEmpty) {
            return parts[1].trim();
          }
        }
        if (i + 1 < lines.length) {
          final next = lines[i + 1].trim();
          if (!next.toLowerCase().contains('order') && !next.toLowerCase().contains('ref')) {
            return next;
          }
        }
      }
    }
    return null;
  }

  static String? _extractReference(List<String> lines, String fullText) {
    final refReg = RegExp(r'(?:order\s*sn|no\.?\s*referensi|id\s*transaksi|no\.?\s*transaksi)[\s:]*([A-Za-z0-9]+)', caseSensitive: false);
    final match = refReg.firstMatch(fullText);
    if (match != null) return match.group(1);

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].toLowerCase();
      if (line.contains('order sn') || line.contains('referensi')) {
        if (i + 1 < lines.length) {
          return lines[i + 1].trim();
        }
      }
    }
    return null;
  }

  static String? _extractBank(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('mandiri')) return 'Bank Mandiri';
    if (lower.contains('bca')) return 'Bank BCA';
    if (lower.contains('bri')) return 'Bank BRI';
    if (lower.contains('bni')) return 'Bank BNI';
    if (lower.contains('seabank')) return 'SeaBank';
    if (lower.contains('jago')) return 'Bank Jago';
    if (lower.contains('dana')) return 'DANA';
    if (lower.contains('gopay')) return 'GoPay';
    if (lower.contains('shopeepay')) return 'ShopeePay';
    return null;
  }

  static String? _extractAccountNumber(String text) {
    final reg = RegExp(r'\b(\d{10,16})\b');
    final match = reg.firstMatch(text);
    return match?.group(1);
  }

  /// Logika akurat untuk membedakan Pemasukan vs Pengeluaran
  static String _determineFlowType(String fullText, String? sender, String recipient, {String? userName}) {
    final lower = fullText.toLowerCase();

    // 1. Cek terhadap Nama Profil Pengguna jika sudah disetel
    if (userName != null && userName.trim().isNotEmpty) {
      final cleanUser = userName.trim().toLowerCase();
      // Jika nama pengguna ada di bagian PENERIMA -> UANG MASUK (PEMASUKAN)
      if (recipient.toLowerCase().contains(cleanUser)) {
        return 'PEMASUKAN';
      }
      // Jika nama pengguna ada di bagian PENGIRIM -> UANG KELUAR (PENGELUARAN)
      if (sender != null && sender.toLowerCase().contains(cleanUser)) {
        return 'PENGELUARAN';
      }
    }

    // 2. Cek simbol plus/minus pada mutasi / screenshot
    if (lower.contains('+rp') || lower.contains('+ rp') || lower.contains(' cr') || lower.contains('uang masuk') || lower.contains('transfer masuk') || lower.contains('diterima dari')) {
      return 'PEMASUKAN';
    }
    if (lower.contains('-rp') || lower.contains('- rp') || lower.contains(' db') || lower.contains('total pembayaran') || lower.contains('jumlah transfer')) {
      // Jika ada minus jelas pengeluaran
      if (lower.contains('-rp') || lower.contains('- rp') || lower.contains(' db')) {
        return 'PENGELUARAN';
      }
    }

    // 3. Cek kata kunci eksplisit UANG MASUK (PEMASUKAN)
    if (lower.contains('top up berhasil') ||
        lower.contains('isi saldo berhasil') ||
        lower.contains('rekening tujuan: anda') ||
        lower.contains('dana masuk') ||
        lower.contains('bi-fast cr') ||
        lower.contains('setoran')) {
      return 'PEMASUKAN';
    }

    // 4. Cek kata kunci eksplisit UANG KELUAR (PENGELUARAN)
    if (lower.contains('qris') ||
        lower.contains('pembayaran qris') ||
        lower.contains('bayar merchant') ||
        lower.contains('pembelian') ||
        lower.contains('tagihan') ||
        lower.contains('beli pulsa') ||
        lower.contains('bayar ke') ||
        lower.contains('bi-fast db') ||
        lower.contains('transfer rupiah berhasil')) {
      return 'PENGELUARAN';
    }

    // 5. Kasus bukti transfer seperti ShopeePay yang dikirimkan orang lain
    if (lower.contains('dikirim dari') && lower.contains('kirim ke')) {
      return 'PEMASUKAN';
    }

    // Default umum transfer keluar dari m-Banking
    if (lower.contains('kirim uang') || lower.contains('transfer berhasil') || lower.contains('transaksi berhasil')) {
      return 'PENGELUARAN';
    }

    return 'PENGELUARAN';
  }

  static String _determineCategory(String description, String recipient) {
    final text = '$description $recipient'.toLowerCase();
    if (text.contains('wifi') || text.contains('listrik') || text.contains('pln') || text.contains('pdam') || text.contains('pulsa') || text.contains('data') || text.contains('kuota')) {
      return 'Tagihan & Utilitas';
    }
    if (text.contains('makan') || text.contains('kopi') || text.contains('resto') || text.contains('cafe') || text.contains('bakso') || text.contains('mie') || text.contains('food')) {
      return 'Makanan & Minuman';
    }
    if (text.contains('gojek') || text.contains('grab') || text.contains('bensin') || text.contains('pertamina') || text.contains('parkir') || text.contains('tol')) {
      return 'Transportasi';
    }
    if (text.contains('shopee') || text.contains('tokopedia') || text.contains('lazada') || text.contains('belanja')) {
      return 'Belanja';
    }
    if (text.contains('patungan') || text.contains('transfer') || text.contains('kirim')) {
      return 'Transfer / Patungan';
    }
    if (text.contains('gaji') || text.contains('bonus') || text.contains('upah')) {
      return 'Gaji / Pendapatan';
    }
    return 'Lainnya';
  }
}
