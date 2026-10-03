import 'dart:convert';
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
}
