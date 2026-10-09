import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction_model.dart';

class StorageService {
  static const String _keyTransactions = 'saved_transactions';
  static const String _keyUserName = 'user_profile_name';

  /// Memuat semua transaksi dari memori HP
  static Future<List<TransactionModel>> loadTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_keyTransactions);
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }
    try {
      final List<dynamic> list = jsonDecode(jsonString);
      return list.map((item) => TransactionModel.fromJson(item)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Menyimpan daftar transaksi permanen
  static Future<void> saveAllTransactions(List<TransactionModel> transactions) async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonString = jsonEncode(transactions.map((t) => t.toJson()).toList());
    await prefs.setString(_keyTransactions, jsonString);
  }

  /// Menambahkan satu transaksi baru di urutan teratas
  static Future<List<TransactionModel>> addTransaction(TransactionModel tx) async {
    final currentList = await loadTransactions();
    currentList.insert(0, tx);
    await saveAllTransactions(currentList);
    return currentList;
  }

  /// Menghapus transaksi berdasarkan index
  static Future<List<TransactionModel>> deleteTransaction(int index) async {
    final currentList = await loadTransactions();
    if (index >= 0 && index < currentList.length) {
      currentList.removeAt(index);
      await saveAllTransactions(currentList);
    }
    return currentList;
  }
  /// Mengambil nama pemilik HP (untuk deteksi otomatis transfer masuk/keluar)
  static Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserName);
  }

  /// Menyimpan nama pemilik HP
  static Future<void> saveUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserName, name.trim());
  }

  static const String _keyCardSkinIndex = 'user_card_skin_index';
  static const String _keyBalanceVisibility = 'user_balance_visibility';

  /// Memuat pilihan tema kartu
  static Future<int> loadCardSkinIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyCardSkinIndex) ?? 0;
  }

  /// Menyimpan pilihan tema kartu
  static Future<void> saveCardSkinIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCardSkinIndex, index);
  }

  /// Memuat preferensi privasi sensor saldo
  static Future<bool> loadBalanceVisibility() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBalanceVisibility) ?? true;
  }

  /// Menyimpan preferensi privasi sensor saldo
  static Future<void> saveBalanceVisibility(bool isVisible) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBalanceVisibility, isVisible);
  }

  static const String _keyNoSpendDays = 'user_no_spend_days';

  /// Memuat daftar tanggal yang diklaim sebagai 'Hari Hemat Rp 0'
  static Future<Set<String>> loadNoSpendDays() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyNoSpendDays) ?? [];
    return list.toSet();
  }

  /// Menandai tanggal tertentu sebagai Hari Hemat Rp 0 (atau membatalkannya)
  static Future<Set<String>> toggleNoSpendDay(String dateStr) async {
    final prefs = await SharedPreferences.getInstance();
    final current = (prefs.getStringList(_keyNoSpendDays) ?? []).toSet();
    if (current.contains(dateStr)) {
      current.remove(dateStr);
    } else {
      current.add(dateStr);
    }
    await prefs.setStringList(_keyNoSpendDays, current.toList());
    return current;
  }

  /// Menambahkan tanggal Hari Hemat Rp 0
  static Future<Set<String>> addNoSpendDay(String dateStr) async {
    final prefs = await SharedPreferences.getInstance();
    final current = (prefs.getStringList(_keyNoSpendDays) ?? []).toSet();
    current.add(dateStr);
    await prefs.setStringList(_keyNoSpendDays, current.toList());
    return current;
  }

  /// Menghapus tanggal Hari Hemat Rp 0
  static Future<Set<String>> removeNoSpendDay(String dateStr) async {
    final prefs = await SharedPreferences.getInstance();
    final current = (prefs.getStringList(_keyNoSpendDays) ?? []).toSet();
    if (current.contains(dateStr)) {
      current.remove(dateStr);
      await prefs.setStringList(_keyNoSpendDays, current.toList());
    }
    return current;
  }

  /// Format tanggal standar yyyy-MM-dd
  static String formatDateKey(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Menghitung streak berturut-turut (dalam hari)
  static int calculateStreak({
    required List<TransactionModel> transactions,
    required Set<String> noSpendDays,
  }) {
    final activeDates = <String>{};
    for (final t in transactions) {
      activeDates.add(t.transactionDate);
    }
    activeDates.addAll(noSpendDays);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayStr = formatDateKey(today);
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdayStr = formatDateKey(yesterday);

    // Jika hari ini belum aktif dan kemarin juga tidak aktif, streak = 0
    if (!activeDates.contains(todayStr) && !activeDates.contains(yesterdayStr)) {
      return 0;
    }

    int streak = 0;
    DateTime checkDate = activeDates.contains(todayStr) ? today : yesterday;

    while (true) {
      final key = formatDateKey(checkDate);
      if (activeDates.contains(key)) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  /// Mengambil gelar/pangkat gamifikasi berdasarkan panjang streak
  static String getFinancialTitle(int streak) {
    if (streak >= 30) return '👑 Sultan Anti-Boncos';
    if (streak >= 14) return '💎 Pendekar Finansial Bijak';
    if (streak >= 7) return '⚡ Master Arus Kas';
    if (streak >= 3) return '🛡️ Penjaga Dompet Disiplin';
    if (streak >= 1) return '🌱 Pemula Sadar Keuangan';
    return '🌱 Siap Memulai Kebiasaan';
  }

  /// Menghitung jumlah hari hemat Rp 0 pada bulan tertentu
  static int countNoSpendThisMonth(Set<String> noSpendDays, DateTime month) {
    final prefix = '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
    return noSpendDays.where((d) => d.startsWith(prefix)).length;
  }

  /// Menghasilkan status 7 hari terakhir (H-6 hingga Hari Ini)
  static List<DailyActivityDay> getWeeklyActivity({
    required List<TransactionModel> transactions,
    required Set<String> noSpendDays,
  }) {
    const dayNames = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayStr = formatDateKey(today);

    final result = <DailyActivityDay>[];
    for (int i = 6; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      final dateStr = formatDateKey(d);
      final hasTx = transactions.any((t) => t.transactionDate == dateStr);
      final isNoSpend = noSpendDays.contains(dateStr);
      final isToday = dateStr == todayStr;
      final isMissed = !hasTx && !isNoSpend && !isToday;

      result.add(DailyActivityDay(
        date: d,
        dateStr: dateStr,
        dayName: dayNames[d.weekday - 1],
        hasTransaction: hasTx,
        isNoSpend: isNoSpend,
        isToday: isToday,
        isMissed: isMissed,
      ));
    }
    return result;
  }

  /// Menghasilkan format string CSV dari daftar transaksi
  static String generateCsvString(List<TransactionModel> transactions) {
    final buffer = StringBuffer();
    buffer.writeln('Tanggal,Waktu,Tipe Arus,Platform,Kategori,Keterangan/Penerima,Pengirim,Nominal,Admin,Total,No Referensi');

    for (final tx in transactions) {
      final date = tx.transactionDate;
      final time = tx.transactionTime ?? '';
      final flow = tx.flowType;
      final platform = tx.sourcePlatform;
      final category = tx.category;
      final desc = (tx.description?.isNotEmpty == true ? tx.description! : tx.recipientName).replaceAll('"', '""');
      final sender = (tx.senderName ?? '').replaceAll('"', '""');
      final amount = tx.amount.toInt();
      final admin = tx.adminFee.toInt();
      final total = tx.totalAmount.toInt();
      final ref = tx.referenceNumber ?? '';

      buffer.writeln('"$date","$time","$flow","$platform","$category","$desc","$sender",$amount,$admin,$total,"$ref"');
    }
    return buffer.toString();
  }

  /// Menyimpan file CSV ke folder Download HP (atau Documents fallback)
  static Future<String> saveCsvToDownload(String csvContent, String fileName) async {
    try {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        final file = File('${downloadDir.path}/$fileName');
        await file.writeAsString(csvContent);
        return file.path;
      }
    } catch (_) {}

    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/$fileName');
    await file.writeAsString(csvContent);
    return file.path;
  }

  /// Menghasilkan ringkasan laporan teks rapi untuk WhatsApp / Catatan
  static String generateSummaryText({
    required List<TransactionModel> transactions,
    required String monthLabel,
    required double totalPemasukan,
    required double totalPengeluaran,
    required double sisaSaldo,
    required String Function(num) formatCurrency,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('📊 LAPORAN KEUANGAN - $monthLabel');
    buffer.writeln('Aplikasi CatatDuit 💳');
    buffer.writeln('==============================');
    buffer.writeln('🟢 Total Pemasukan  : ${formatCurrency(totalPemasukan)}');
    buffer.writeln('🔴 Total Pengeluaran: ${formatCurrency(totalPengeluaran)}');
    buffer.writeln('💵 Sisa Saldo       : ${formatCurrency(sisaSaldo)}');
    buffer.writeln('==============================');
    buffer.writeln('📋 Rincian Transaksi (${transactions.length}):');

    if (transactions.isEmpty) {
      buffer.writeln('(Belum ada transaksi)');
    } else {
      for (final tx in transactions) {
        final sign = tx.flowType == 'PEMASUKAN' ? '+' : '-';
        final title = tx.description?.isNotEmpty == true ? tx.description! : tx.recipientName;
        buffer.writeln('• ${tx.transactionDate} | $title: $sign${formatCurrency(tx.totalAmount)} [${tx.category}]');
      }
    }
    buffer.writeln('\nGenerated with CatatDuit (100% Offline OCR & Expense Tracker)');
    return buffer.toString();
  }
}

/// Model untuk representasi status aktivitas harian dalam seminggu
class DailyActivityDay {
  final DateTime date;
  final String dateStr;
  final String dayName; // 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'
  final bool hasTransaction;
  final bool isNoSpend;
  final bool isToday;
  final bool isMissed;

  DailyActivityDay({
    required this.date,
    required this.dateStr,
    required this.dayName,
    required this.hasTransaction,
    required this.isNoSpend,
    required this.isToday,
    required this.isMissed,
  });
}

