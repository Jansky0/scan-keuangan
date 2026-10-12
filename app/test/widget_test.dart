import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/main.dart';
import 'package:app/services/storage_service.dart';

void main() {
  testWidgets('CatatDuit app smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CatatDuitApp());
    await tester.pumpAndSettle();

    expect(find.text('CatatDuit'), findsAtLeastNWidgets(1));
    expect(find.text('Catat Cepat'), findsOneWidget);
    expect(find.text('SALDO KEUANGAN'), findsOneWidget);
    expect(find.text('Pindai Bukti'), findsOneWidget);
  });

  test('Streak calculation and title unit test', () {
    final now = DateTime.now();
    final todayStr = StorageService.formatDateKey(now);
    final yesterdayStr = StorageService.formatDateKey(now.subtract(const Duration(days: 1)));
    final dayBeforeYesterdayStr = StorageService.formatDateKey(now.subtract(const Duration(days: 2)));

    // Case 1: 3 hari beruntun no-spend
    final streak = StorageService.calculateStreak(
      transactions: [],
      noSpendDays: {todayStr, yesterdayStr, dayBeforeYesterdayStr},
    );
    expect(streak, 3);
    expect(StorageService.getFinancialTitle(streak), '🛡️ Penjaga Dompet Disiplin');

    // Case 2: Kemarin aktif, hari ini belum
    final streakYesterdayOnly = StorageService.calculateStreak(
      transactions: [],
      noSpendDays: {yesterdayStr},
    );
    expect(streakYesterdayOnly, 1);

    // Case 3: Kosong
    final streakEmpty = StorageService.calculateStreak(
      transactions: [],
      noSpendDays: {},
    );
    expect(streakEmpty, 0);
    expect(StorageService.getFinancialTitle(0), '🌱 Siap Memulai Kebiasaan');
  });

  testWidgets('Daily check-in claim No-Spend day test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CatatDuitApp());
    await tester.pumpAndSettle();

    // Pastikan tombol Hari Hemat tampil di Action Dock
    expect(find.text('Hari Hemat'), findsOneWidget);

    // Ketuk 'Hari Hemat'
    await tester.tap(find.text('Hari Hemat'));
    await tester.pumpAndSettle();

    // Modal perayaan No-Spend Day muncul
    expect(find.text('Hari Hemat Rp 0 Berhasil Dicatat!'), findsOneWidget);
    expect(find.text('Mantap, Pertahankan! 🚀'), findsOneWidget);

    // Tutup modal
    await tester.tap(find.text('Mantap, Pertahankan! 🚀'));
    await tester.pumpAndSettle();

    // Action dock dan kartu sekarang menampilkan status Terklaim
    expect(find.text('Terklaim 🛡️'), findsOneWidget);
  });

  testWidgets('Bottom Navigation Bar switching test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CatatDuitApp());
    await tester.pumpAndSettle();

    // Pastikan Navbar tampil
    expect(find.text('Beranda'), findsOneWidget);
    expect(find.text('Analisis'), findsOneWidget);
    expect(find.text('Pengaturan'), findsOneWidget);

    // Pindah ke Tab Analisis
    await tester.tap(find.text('Analisis'));
    await tester.pumpAndSettle();

    expect(find.text('Kesehatan Finansial'), findsOneWidget);
    expect(find.text('Perbandingan Arus Kas'), findsOneWidget);
    expect(find.text('Pola Belanja Harian'), findsOneWidget);

    // Pindah ke Tab Pengaturan
    await tester.tap(find.text('Pengaturan'));
    await tester.pumpAndSettle();

    expect(find.text('Pilihan Tema Visual Neo-Banking'), findsOneWidget);
    expect(find.text('Pengelolaan & Ekspor Data'), findsOneWidget);

    // Kembali ke Tab Beranda
    await tester.tap(find.text('Beranda'));
    await tester.pumpAndSettle();

    expect(find.text('SALDO KEUANGAN'), findsOneWidget);
  });
}


