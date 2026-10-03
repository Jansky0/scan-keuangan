import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/transaction_model.dart';
import 'receipt_parser.dart';
import 'storage_service.dart';

class ScannerService {
  /// Pindai bukti transaksi 100% On-Device menggunakan Google ML Kit
  static Future<TransactionModel> scanReceipt(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File bukti tidak ditemukan di: $filePath');
    }

    try {
      final inputImage = InputImage.fromFilePath(filePath);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final fullText = recognizedText.text;
      debugPrint('--- HASIL OCR ML KIT ---');
      debugPrint(fullText);
      debugPrint('------------------------');

      if (fullText.trim().isEmpty) {
        throw Exception('Tidak ada teks yang terbaca pada gambar bukti.');
      }

      // Ambil nama pengguna jika sudah disetel untuk pencocokan pengirim/penerima
      final userName = await StorageService.getUserName();

      // Parsing teks struk dengan parser pintar lokal
      final transaction = ReceiptParser.parse(fullText, userName: userName);
      return transaction;
    } catch (e) {
      debugPrint('Error ML Kit OCR: $e');
      throw Exception('Gagal membaca gambar bukti: $e');
    }
  }

  /// Data contoh simulasi ShopeePay (Patungan Wifi)
  static TransactionModel getSampleShopeePayData() {
    return TransactionModel(
      status: 'BERHASIL',
      flowType: 'PEMASUKAN',
      sourcePlatform: 'ShopeePay',
      transactionType: 'TRANSFER_BANK',
      amount: 110000.0,
      adminFee: 0.0,
      totalAmount: 110000.0,
      senderName: 'Muhammad ******',
      recipientName: 'ANDIKA RAMADHAN YUSU',
      destinationBankOrWallet: 'Bank Mandiri',
      destinationAccount: '1670010166980',
      transactionDate: '2026-10-01',
      transactionTime: '06:43',
      referenceNumber: 'UWSHKYJDBOGPSV6JSKUUEPHLYHWVA',
      description: 'Patungan wifi',
      category: 'Tagihan & Utilitas',
    );
  }
}
