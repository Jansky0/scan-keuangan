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

