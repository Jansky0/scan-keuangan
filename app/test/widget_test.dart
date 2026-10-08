import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/main.dart';
import 'package:app/services/storage_service.dart';

void main() {
  testWidgets('CatatDuit app smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CatatDuitApp());
    await tester.pumpAndSettle();

    expect(find.text('CatatDuit'), findsOneWidget);
    expect(find.text('Catat Cepat'), findsOneWidget);
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
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CatatDuitApp());
    await tester.pumpAndSettle();

    // Pastikan tombol Hari Ini Rp 0 (Hemat) tampil
    expect(find.text('Hari Ini Rp 0 (Hemat)'), findsOneWidget);

    // Ketuk 'Hari Ini Rp 0 (Hemat)'
    await tester.tap(find.text('Hari Ini Rp 0 (Hemat)'));
    await tester.pumpAndSettle();

    // Modal perayaan No-Spend Day muncul
    expect(find.text('Hari Hemat Rp 0 Berhasil Dicatat!'), findsOneWidget);
    expect(find.text('Mantap, Pertahankan! 🚀'), findsOneWidget);

    // Tutup modal
    await tester.tap(find.text('Mantap, Pertahankan! 🚀'));
    await tester.pumpAndSettle();

    // Kartu sekarang menampilkan status Terklaim
    expect(find.text('Terklaim No-Spend Day! 🛡️'), findsOneWidget);
  });
}

