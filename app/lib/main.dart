import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'models/transaction_model.dart';
import 'services/scanner_service.dart';
import 'services/storage_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CatatDuitApp());
}

class CatatDuitApp extends StatelessWidget {
  const CatatDuitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CatatDuit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF070E12),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF34D399),
          secondary: Color(0xFF60A5FA),
          surface: Color(0xFF0F1B20),
          onSurface: Color(0xFFF8FAFC),
        ),
        fontFamily: 'Roboto',
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late StreamSubscription _intentSub;
  List<TransactionModel> _allTransactions = [];
  Set<String> _noSpendDays = {};
  bool _isScanning = false;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  String? _userName;
  String _searchQuery = '';
  String _selectedFilterFlow = 'ALL';
  String? _selectedCategoryFilter;
  final TextEditingController _searchController = TextEditingController();

  bool _isBalanceVisible = true;
  int _selectedCardSkinIndex = 0;

  static const List<Map<String, dynamic>> _cardSkins = [
    {
      'name': 'Emerald Obsidian',
      'colors': [Color(0xFF04201D), Color(0xFF0D5751), Color(0xFF021715)],
      'accent': Color(0xFF34D399),
      'chip': Color(0xFFD4AF37),
      'tag': 'DEBIT PLATINUM',
      'bg': Color(0xFF061011),
      'surface': Color(0xFF0D1C1E),
      'surfaceElevated': Color(0xFF13272A),
      'border': Color(0xFF1A383D),
      'accentGlow': Color(0x3334D399),
      'icon': '🌿',
    },
    {
      'name': 'Midnight Sapphire',
      'colors': [Color(0xFF07112B), Color(0xFF1E3A8A), Color(0xFF050B1B)],
      'accent': Color(0xFF60A5FA),
      'chip': Color(0xFFE2E8F0),
      'tag': 'BLACK CARD',
      'bg': Color(0xFF080D1A),
      'surface': Color(0xFF101930),
      'surfaceElevated': Color(0xFF172344),
      'border': Color(0xFF223561),
      'accentGlow': Color(0x3360A5FA),
      'icon': '💎',
    },
    {
      'name': 'Neon Amethyst',
      'colors': [Color(0xFF240D50), Color(0xFF6B21A8), Color(0xFF160633)],
      'accent': Color(0xFFC084FC),
      'chip': Color(0xFFFDE047),
      'tag': 'CYBER POCKET',
      'bg': Color(0xFF0E071D),
      'surface': Color(0xFF1B1033),
      'surfaceElevated': Color(0xFF27174A),
      'border': Color(0xFF3B236E),
      'accentGlow': Color(0x33C084FC),
      'icon': '🔮',
    },
    {
      'name': 'Titanium Gold',
      'colors': [Color(0xFF181512), Color(0xFF38332C), Color(0xFF12100E)],
      'accent': Color(0xFFFBBF24),
      'chip': Color(0xFFEAB308),
      'tag': 'ROYAL GOLD',
      'bg': Color(0xFF0D0C0A),
      'surface': Color(0xFF1C1A16),
      'surfaceElevated': Color(0xFF2A2721),
      'border': Color(0xFF3F3B32),
      'accentGlow': Color(0x33FBBF24),
      'icon': '👑',
    },
  ];

  final currencyFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  static const List<String> _monthNames = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
  ];

  @override
  void initState() {
    super.initState();
    _loadStoredData();
    _initShareIntentListener();
  }

  Future<void> _loadStoredData() async {
    final list = await StorageService.loadTransactions();
    final name = await StorageService.getUserName();
    final noSpend = await StorageService.loadNoSpendDays();
    final skinIndex = await StorageService.loadCardSkinIndex();
    final isVisible = await StorageService.loadBalanceVisibility();
    if (mounted) {
      setState(() {
        _allTransactions = list;
        _userName = name;
        _noSpendDays = noSpend;
        _selectedCardSkinIndex = skinIndex.clamp(0, _cardSkins.length - 1);
        _isBalanceVisible = isVisible;
      });
    }
  }

  void _initShareIntentListener() {
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        final path = value.first.path;
        ReceiveSharingIntent.instance.reset();
        _processIncomingPath(path);
      }
    }, onError: (err) {
      debugPrint("Error sharing stream: $err");
    });

    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        final path = value.first.path;
        ReceiveSharingIntent.instance.reset();
        _processIncomingPath(path);
      }
    });
  }

  @override
  void dispose() {
    _intentSub.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _currentSkin => _cardSkins[_selectedCardSkinIndex];

  Future<String?> _cropImage(String filePath) async {
    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: filePath,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 95,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Potong Bukti / Kwitansi',
            toolbarColor: _currentSkin['surface'] as Color,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: _currentSkin['accent'] as Color,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            showCropGrid: true,
            aspectRatioPresets: [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
            ],
          ),
        ],
      );
      return croppedFile?.path;
    } catch (e) {
      debugPrint("Crop error: $e");
      return filePath;
    }
  }

  Future<void> _processIncomingPath(String filePath) async {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.pdf')) {
      _handleIncomingFile(filePath);
      return;
    }

    final croppedPath = await _cropImage(filePath);
    if (croppedPath != null) {
      _handleIncomingFile(croppedPath, originalPath: filePath);
    }
  }

  Future<void> _handleIncomingFile(String filePath, {String? originalPath}) async {
    setState(() => _isScanning = true);

    try {
      final transaction = await ScannerService.scanReceipt(filePath);
      if (mounted) {
        _showConfirmationDialog(transaction, originalFilePath: originalPath ?? filePath);
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog(e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: source);
      if (image != null) {
        final croppedPath = await _cropImage(image.path);
        if (croppedPath != null) {
          _handleIncomingFile(croppedPath, originalPath: image.path);
        }
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengambil gambar: $e')),
        );
      }
    }
  }

  void _showImageSourceDialog() {
    final skin = _currentSkin;
    final Color surface = skin['surfaceElevated'];
    final Color border = skin['border'];
    final Color accent = skin['accent'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: border),
          ),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.qr_code_scanner, color: accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pilih Bukti Transaksi',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white),
                      ),
                      Text(
                        'Pindai screenshot m-banking atau foto struk',
                        style: TextStyle(fontSize: 12, color: Colors.white60),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildModernOptionTile(
                icon: Icons.image_outlined,
                iconColor: const Color(0xFF38BDF8),
                title: 'Galeri (Screenshot Livin / BCA / QRIS)',
                subtitle: 'Pilih tangkapan layar, potong area nominal',
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 10),
              _buildModernOptionTile(
                icon: Icons.camera_alt_outlined,
                iconColor: const Color(0xFF34D399),
                title: 'Kamera Struk Kertas',
                subtitle: 'Foto langsung struk kasir atau struk ATM',
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              const SizedBox(height: 10),
              _buildModernOptionTile(
                icon: Icons.flash_on_outlined,
                iconColor: const Color(0xFFFBBF24),
                title: 'Catat Cepat (Tanpa Bukti Gambar)',
                subtitle: 'Kalkulator pintar, tombol preset, hitung budget instan',
                onTap: () {
                  Navigator.pop(ctx);
                  _showSmartQuickInputModal();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernOptionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final skin = _currentSkin;
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: skin['border']),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  void _showErrorDialog(String errorMsg) {
    final skin = _currentSkin;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: skin['surfaceElevated'],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: skin['border']),
        ),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Text('Gagal Scan Bukti', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          errorMsg,
          style: const TextStyle(fontSize: 13, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup', style: TextStyle(color: Colors.white60)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: skin['accent']),
            onPressed: () {
              Navigator.pop(ctx);
              final sampleTx = ScannerService.getSampleShopeePayData();
              _showConfirmationDialog(sampleTx);
            },
            child: const Text('Pakai Data Contoh', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showConfirmationDialog(TransactionModel initialTx, {String? originalFilePath}) {
    String currentFlowType = initialTx.flowType;
    String currentCategory = initialTx.category;
    double currentTotalAmount = initialTx.totalAmount;

    final categories = [
      'Tagihan & Utilitas',
      'Makanan & Minuman',
      'Belanja',
      'Transportasi',
      'Transfer / Patungan',
      'Hiburan',
      'Gaji / Pendapatan',
      'Lainnya',
    ];

    final skin = _currentSkin;
    final Color surface = skin['surfaceElevated'];
    final Color border = skin['border'];
    final Color accent = skin['accent'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final isIncome = currentFlowType == 'PEMASUKAN';

            void editAmountDialog() {
              final controller = TextEditingController(text: currentTotalAmount.toInt().toString());
              showDialog(
                context: modalCtx,
                builder: (dialogCtx) => AlertDialog(
                  backgroundColor: surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: border),
                  ),
                  title: Row(
                    children: [
                      Icon(Icons.edit_note, color: accent),
                      const SizedBox(width: 8),
                      const Text('Koreksi Nominal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                  content: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      prefixText: 'Rp ',
                      prefixStyle: const TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      labelText: 'Nominal Transaksi',
                      labelStyle: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      child: const Text('Batal', style: TextStyle(color: Colors.white60)),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: accent),
                      onPressed: () {
                        final cleaned = controller.text.replaceAll(RegExp(r'[^0-9]'), '');
                        final val = double.tryParse(cleaned);
                        if (val != null && val > 0) {
                          setModalState(() {
                            currentTotalAmount = val;
                          });
                        }
                        Navigator.pop(dialogCtx);
                      },
                      child: const Text('Simpan', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            }

            return Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: border),
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Verifikasi Bukti Transfer',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            initialTx.sourcePlatform,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isIncome ? 'Uang Masuk Terdeteksi' : 'Pengeluaran Terdeteksi',
                                style: const TextStyle(fontSize: 12, color: Colors.white60),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                currencyFormatter.format(currentTotalAmount),
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: isIncome ? const Color(0xFF34D399) : const Color(0xFFFB7185),
                                ),
                              ),
                            ],
                          ),
                          OutlinedButton.icon(
                            onPressed: editAmountDialog,
                            icon: const Icon(Icons.edit, size: 14),
                            label: const Text('Ubah'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: accent,
                              side: BorderSide(color: accent),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setModalState(() => currentFlowType = 'PENGELUARAN'),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: !isIncome ? Colors.redAccent.withValues(alpha: 0.2) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: !isIncome ? Colors.redAccent : Colors.white24,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '🔴 Pengeluaran',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: !isIncome ? Colors.redAccent : Colors.white60,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: () => setModalState(() => currentFlowType = 'PEMASUKAN'),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isIncome ? Colors.greenAccent.withValues(alpha: 0.2) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isIncome ? Colors.greenAccent : Colors.white24,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '🟢 Pemasukan',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isIncome ? Colors.greenAccent : Colors.white60,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Kategori:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: categories.map((cat) {
                        final isSel = currentCategory == cat;
                        return ChoiceChip(
                          label: Text(cat, style: TextStyle(fontSize: 12, color: isSel ? Colors.black : Colors.white70)),
                          selected: isSel,
                          selectedColor: accent,
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                          side: BorderSide(color: isSel ? accent : border),
                          onSelected: (sel) {
                            if (sel) setModalState(() => currentCategory = cat);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    if (originalFilePath != null)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.pop(modalCtx);
                            final newCropped = await _cropImage(originalFilePath);
                            if (newCropped != null) {
                              _handleIncomingFile(newCropped, originalPath: originalFilePath);
                            }
                          },
                          icon: const Icon(Icons.crop),
                          label: const Text('Potong Ulang Gambar (Crop Lagi)'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(color: border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () async {
                          final finalTx = TransactionModel(
                            status: initialTx.status,
                            flowType: currentFlowType,
                            sourcePlatform: initialTx.sourcePlatform,
                            transactionType: initialTx.transactionType,
                            amount: currentTotalAmount,
                            adminFee: initialTx.adminFee,
                            totalAmount: currentTotalAmount,
                            senderName: initialTx.senderName,
                            recipientName: initialTx.recipientName,
                            destinationBankOrWallet: initialTx.destinationBankOrWallet,
                            destinationAccount: initialTx.destinationAccount,
                            transactionDate: initialTx.transactionDate,
                            transactionTime: initialTx.transactionTime,
                            referenceNumber: initialTx.referenceNumber,
                            description: initialTx.description,
                            category: currentCategory,
                          );

                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(modalCtx);
                          final updated = await StorageService.addTransaction(finalTx);
                          if (mounted) {
                            setState(() {
                              _allTransactions = updated;
                            });
                            nav.pop();
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Transaksi ${currencyFormatter.format(finalTx.totalAmount)} berhasil dicatat!'),
                                backgroundColor: const Color(0xFF059669),
                              ),
                            );
                          }
                        },
                        child: const Text('Simpan ke CatatDuit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showProfileDialog() {
    final controller = TextEditingController(text: _userName ?? '');
    final skin = _currentSkin;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: skin['surfaceElevated'],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: skin['border']),
        ),
        title: Row(
          children: [
            Icon(Icons.account_circle, color: skin['accent']),
            const SizedBox(width: 8),
            const Text('Nama Pemilik Akun', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Masukkan nama rekening/e-wallet Anda (misal: Andika). Sistem akan otomatis mengenali uang masuk jika nama Anda tertera di bagian penerima.',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: skin['border'])),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: skin['border'])),
                hintText: 'Contoh: Andika Ramadhan',
                hintStyle: const TextStyle(color: Colors.white38),
                labelText: 'Nama Anda',
                labelStyle: const TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Colors.white60)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: skin['accent']),
            onPressed: () async {
              final name = controller.text.trim();
              await StorageService.saveUserName(name);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                setState(() => _userName = name.isEmpty ? null : name);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Nama pemilik berhasil disimpan!')),
                );
              }
            },
            child: const Text('Simpan', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSmartQuickInputModal() {
    String flowType = 'PENGELUARAN';
    String natureTag = 'Kebutuhan';
    String rawNominal = '';
    String category = 'Makanan & Minuman';
    String platform = 'Tunai / Cash';
    final noteController = TextEditingController();

    final categories = [
      {'name': 'Makanan & Minuman', 'icon': Icons.restaurant, 'color': const Color(0xFFEA580C)},
      {'name': 'Kopi & Nongkrong', 'icon': Icons.local_cafe, 'color': const Color(0xFF92400E)},
      {'name': 'Belanja', 'icon': Icons.shopping_bag, 'color': const Color(0xFF059669)},
      {'name': 'Transportasi', 'icon': Icons.directions_car, 'color': const Color(0xFF2563EB)},
      {'name': 'Tagihan & Utilitas', 'icon': Icons.receipt_long, 'color': const Color(0xFFDC2626)},
      {'name': 'Hiburan', 'icon': Icons.movie, 'color': const Color(0xFF7C3AED)},
      {'name': 'Kesehatan', 'icon': Icons.medical_services, 'color': const Color(0xFFE11D48)},
      {'name': 'Gaji / Pendapatan', 'icon': Icons.account_balance_wallet, 'color': const Color(0xFF16A34A)},
      {'name': 'Lainnya', 'icon': Icons.more_horiz, 'color': const Color(0xFF475569)},
    ];

    final presets = [
      {'label': '☕ Es Kopi', 'amount': 22000, 'cat': 'Kopi & Nongkrong', 'nature': 'Keinginan', 'note': 'Kopi Kenangan'},
      {'label': '🍛 Makan Siang', 'amount': 25000, 'cat': 'Makanan & Minuman', 'nature': 'Kebutuhan', 'note': 'Warteg / Nasi Padang'},
      {'label': '⛽ Bensin Motor', 'amount': 30000, 'cat': 'Transportasi', 'nature': 'Kebutuhan', 'note': 'Bensin Pertamax'},
      {'label': '🅿️ Parkir', 'amount': 5000, 'cat': 'Transportasi', 'nature': 'Kebutuhan', 'note': 'Parkir Motor'},
      {'label': '🛒 Belanja Mart', 'amount': 50000, 'cat': 'Belanja', 'nature': 'Kebutuhan', 'note': 'Alfamart / Indomaret'},
      {'label': '⚡ Token Listrik', 'amount': 100000, 'cat': 'Tagihan & Utilitas', 'nature': 'Kebutuhan', 'note': 'Listrik PLN'},
    ];

    final skin = _currentSkin;
    final Color surface = skin['surfaceElevated'];
    final Color border = skin['border'];
    final Color accent = skin['accent'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final isIncome = flowType == 'PEMASUKAN';
            final currentAmount = double.tryParse(rawNominal) ?? 0.0;
            final double sisaSetelah = isIncome 
                ? (_saldoBulanIni + currentAmount) 
                : (_saldoBulanIni - currentAmount);

            void onDigitPress(String digit) {
              HapticFeedback.lightImpact();
              setModalState(() {
                if (digit == '⌫') {
                  if (rawNominal.isNotEmpty) {
                    rawNominal = rawNominal.substring(0, rawNominal.length - 1);
                  }
                } else if (digit == '000') {
                  if (rawNominal.isNotEmpty && rawNominal != '0' && rawNominal.length < 9) {
                    rawNominal += '000';
                  }
                } else {
                  if (rawNominal == '0') {
                    rawNominal = digit;
                  } else if (rawNominal.length < 11) {
                    rawNominal += digit;
                  }
                }
              });
            }

            void applyPreset(Map<String, dynamic> preset) {
              HapticFeedback.mediumImpact();
              setModalState(() {
                rawNominal = (preset['amount'] as int).toString();
                category = preset['cat'] as String;
                natureTag = preset['nature'] as String;
                noteController.text = preset['note'] as String;
              });
            }

            return Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: border),
              ),
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 14,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 18,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Text(
                              '⚡ Catat Cepat',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: border),
                          ),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setModalState(() => flowType = 'PENGELUARAN');
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: !isIncome ? Colors.redAccent.withValues(alpha: 0.3) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Keluar',
                                    style: TextStyle(
                                      color: !isIncome ? Colors.white : Colors.white60,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setModalState(() {
                                    flowType = 'PEMASUKAN';
                                    category = 'Gaji / Pendapatan';
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isIncome ? Colors.greenAccent.withValues(alpha: 0.3) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Masuk',
                                    style: TextStyle(
                                      color: isIncome ? Colors.white : Colors.white60,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!isIncome) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: presets.map((p) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                label: Text(p['label'] as String, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                                backgroundColor: Colors.white.withValues(alpha: 0.05),
                                side: BorderSide(color: border),
                                onPressed: () => applyPreset(p),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        children: [
                          Text(
                            rawNominal.isEmpty ? 'Rp 0' : currencyFormatter.format(currentAmount),
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: isIncome ? const Color(0xFF34D399) : const Color(0xFFFB7185),
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sisa Saldo Setelahnya: ${currencyFormatter.format(sisaSetelah)}',
                            style: const TextStyle(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: categories.map((catItem) {
                          final catName = catItem['name'] as String;
                          final isSel = category == catName;
                          final catIcon = catItem['icon'] as IconData;
                          final catColor = catItem['color'] as Color;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              avatar: Icon(catIcon, size: 14, color: isSel ? Colors.black : catColor),
                              label: Text(catName, style: TextStyle(fontSize: 11, color: isSel ? Colors.black : Colors.white70)),
                              selected: isSel,
                              selectedColor: accent,
                              backgroundColor: Colors.white.withValues(alpha: 0.04),
                              side: BorderSide(color: isSel ? accent : border),
                              onSelected: (sel) {
                                if (sel) setModalState(() => category = catName);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Keterangan (contoh: Kopi Kenangan, Nasi Padang...)',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.04),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildInteractiveNumpad(onDigitPress, border),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        onPressed: currentAmount <= 0
                            ? null
                            : () async {
                                final now = DateTime.now();
                                final timeStr = '${now.hour.toString().padLeft(2, "0")}:${now.minute.toString().padLeft(2, "0")}';
                                final dateStr = StorageService.formatDateKey(now);

                                final tx = TransactionModel(
                                  status: 'BERHASIL',
                                  flowType: flowType,
                                  sourcePlatform: platform,
                                  transactionType: isIncome ? 'PENDAPATAN' : 'CATAT_CEPAT',
                                  amount: currentAmount,
                                  totalAmount: currentAmount,
                                  recipientName: noteController.text.trim().isNotEmpty ? noteController.text.trim() : category,
                                  transactionDate: dateStr,
                                  transactionTime: timeStr,
                                  description: noteController.text.trim().isNotEmpty
                                      ? '${noteController.text.trim()} ($natureTag)'
                                      : 'Catat Manual ($natureTag)',
                                  category: category,
                                );

                                final messenger = ScaffoldMessenger.of(context);
                                final nav = Navigator.of(modalCtx);
                                final updated = await StorageService.addTransaction(tx);
                                if (mounted) {
                                  setState(() {
                                    _allTransactions = updated;
                                  });
                                  nav.pop();
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('Catat Cepat ${currencyFormatter.format(currentAmount)} tersimpan!'),
                                      backgroundColor: const Color(0xFF059669),
                                    ),
                                  );
                                }
                              },
                        child: const Text('Simpan Catatan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInteractiveNumpad(Function(String) onDigitPress, Color border) {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['000', '0', '⌫'],
    ];

    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: row.map((key) {
              final isDelete = key == '⌫';
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => onDigitPress(key),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: border),
                        ),
                        alignment: Alignment.center,
                        child: isDelete
                            ? const Icon(Icons.backspace_outlined, size: 18, color: Colors.white70)
                            : Text(
                                key,
                                style: TextStyle(
                                  fontSize: key == '000' ? 14 : 17,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  void _showExportDialog() {
    final currentMonthLabel = '${_monthNames[_selectedMonth.month - 1]} ${_selectedMonth.year}';
    final transactions = _monthlyTransactions;
    final skin = _currentSkin;
    final Color surface = skin['surfaceElevated'];
    final Color border = skin['border'];
    final Color accent = skin['accent'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: border),
          ),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.ios_share, color: accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ekspor Laporan ($currentMonthLabel)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                      ),
                      const Text(
                        'Bagikan teks atau unduh file CSV spreadsheet',
                        style: TextStyle(fontSize: 12, color: Colors.white60),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildModernOptionTile(
                icon: Icons.copy,
                iconColor: const Color(0xFF34D399),
                title: 'Salin Ringkasan Teks',
                subtitle: 'Format rapi untuk dibagikan ke WhatsApp / Catatan',
                onTap: () async {
                  Navigator.pop(ctx);
                  final text = StorageService.generateSummaryText(
                    transactions: transactions,
                    monthLabel: currentMonthLabel,
                    totalPemasukan: _totalPemasukanBulanIni,
                    totalPengeluaran: _totalPengeluaranBulanIni,
                    sisaSaldo: _saldoBulanIni,
                    formatCurrency: (n) => currencyFormatter.format(n),
                  );
                  await Clipboard.setData(ClipboardData(text: text));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Ringkasan laporan berhasil disalin ke papan klip!'),
                        backgroundColor: Color(0xFF0F766E),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 10),
              _buildModernOptionTile(
                icon: Icons.table_chart_outlined,
                iconColor: const Color(0xFF60A5FA),
                title: 'Unduh File CSV (Excel)',
                subtitle: 'Simpan file spreadsheet ke folder Download HP',
                onTap: () async {
                  Navigator.pop(ctx);
                  final year = _selectedMonth.year.toString();
                  final month = _selectedMonth.month.toString().padLeft(2, '0');
                  final fileName = 'CatatDuit_Laporan_${year}_$month.csv';

                  final csv = StorageService.generateCsvString(transactions);
                  final path = await StorageService.saveCsvToDownload(csv, fileName);

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('File CSV tersimpan di:\n$path'),
                        duration: const Duration(seconds: 4),
                        backgroundColor: Colors.blue.shade900,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTransactionDetailDialog(TransactionModel tx, int originalIndex) {
    final skin = _currentSkin;
    final Color surface = skin['surfaceElevated'];
    final Color border = skin['border'];
    final isIncome = tx.flowType == 'PEMASUKAN';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: border),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Detail Transaksi',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isIncome
                          ? const Color(0xFF34D399).withValues(alpha: 0.15)
                          : const Color(0xFFFB7185).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isIncome ? 'UANG MASUK' : 'UANG KELUAR',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isIncome ? const Color(0xFF34D399) : const Color(0xFFFB7185),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: border),
                ),
                child: Column(
                  children: [
                    _buildRowItem('Nominal', currencyFormatter.format(tx.totalAmount), isBold: true, isAmount: true, isIncome: isIncome),
                    const Divider(height: 20, color: Colors.white12),
                    _buildRowItem('Platform', tx.sourcePlatform),
                    if (tx.destinationBankOrWallet != null)
                      _buildRowItem('Bank / Tujuan', '${tx.destinationBankOrWallet} ${tx.destinationAccount ?? ""}'),
                    if (tx.senderName != null)
                      _buildRowItem('Pengirim', tx.senderName!),
                    _buildRowItem('Penerima / Toko', tx.recipientName),
                    if (tx.description != null)
                      _buildRowItem('Catatan', tx.description!),
                    _buildRowItem('Kategori', tx.category),
                    _buildRowItem('Tanggal & Jam', '${tx.transactionDate} ${tx.transactionTime ?? ""}'),
                    if (tx.referenceNumber != null)
                      _buildRowItem('No. Referensi', tx.referenceNumber!),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFB7185),
                        side: const BorderSide(color: Color(0xFFFB7185)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        if (originalIndex != -1 && originalIndex < _allTransactions.length) {
                          final updated = await StorageService.deleteTransaction(originalIndex);
                          if (mounted) {
                            setState(() => _allTransactions = updated);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Transaksi berhasil dihapus')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Hapus Transaksi'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: skin['accent'],
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Tutup', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRowItem(String label, String value, {bool isBold = false, bool isAmount = false, bool isIncome = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.white60)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: isAmount ? 18 : 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: isAmount
                    ? (isIncome ? const Color(0xFF34D399) : const Color(0xFFFB7185))
                    : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<TransactionModel> get _monthlyTransactions {
    final year = _selectedMonth.year.toString();
    final month = _selectedMonth.month.toString().padLeft(2, '0');
    final prefix = '$year-$month';

    return _allTransactions.where((t) => t.transactionDate.startsWith(prefix)).toList();
  }

  List<TransactionModel> get _filteredTransactions {
    return _monthlyTransactions.where((tx) {
      if (_selectedFilterFlow != 'ALL' && tx.flowType != _selectedFilterFlow) {
        return false;
      }
      if (_selectedCategoryFilter != null && tx.category != _selectedCategoryFilter) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final title = (tx.description?.isNotEmpty == true ? tx.description! : tx.recipientName).toLowerCase();
        final platform = tx.sourcePlatform.toLowerCase();
        final category = tx.category.toLowerCase();
        final amountStr = tx.totalAmount.toInt().toString();
        if (!title.contains(query) && !platform.contains(query) && !category.contains(query) && !amountStr.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  double get _totalPemasukanBulanIni => _monthlyTransactions
      .where((t) => t.flowType == 'PEMASUKAN')
      .fold(0.0, (acc, item) => acc + item.totalAmount);

  double get _totalPengeluaranBulanIni => _monthlyTransactions
      .where((t) => t.flowType == 'PENGELUARAN')
      .fold(0.0, (acc, item) => acc + item.totalAmount);

  double get _saldoBulanIni => _totalPemasukanBulanIni - _totalPengeluaranBulanIni;

  Map<String, double> get _categoryExpenses {
    final map = <String, double>{};
    for (final tx in _monthlyTransactions.where((t) => t.flowType == 'PENGELUARAN')) {
      map[tx.category] = (map[tx.category] ?? 0) + tx.totalAmount;
    }
    return map;
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Makanan & Minuman':
        return Icons.restaurant;
      case 'Tagihan & Utilitas':
        return Icons.receipt_long;
      case 'Belanja':
        return Icons.shopping_bag;
      case 'Transportasi':
        return Icons.directions_car;
      case 'Transfer / Patungan':
        return Icons.swap_horiz;
      case 'Hiburan':
        return Icons.movie;
      case 'Gaji / Pendapatan':
        return Icons.account_balance_wallet;
      default:
        return Icons.category;
    }
  }

  Color _getCategoryColor(int index) {
    const colors = [
      Color(0xFFFB7185), // Rose
      Color(0xFFFB923C), // Orange
      Color(0xFFFBBF24), // Amber
      Color(0xFF34D399), // Emerald
      Color(0xFF60A5FA), // Blue
      Color(0xFFA78BFA), // Violet
      Color(0xFFF472B6), // Pink
      Color(0xFF94A3B8), // Slate
    ];
    return colors[index % colors.length];
  }

  Widget _buildCategoryBreakdownCard() {
    final expenses = _categoryExpenses;
    if (expenses.isEmpty) return const SizedBox.shrink();

    final total = _totalPengeluaranBulanIni;
    final sortedEntries = expenses.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final skin = _currentSkin;
    final Color surface = skin['surface'];
    final Color border = skin['border'];
    final Color accent = skin['accent'];

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.pie_chart, size: 18, color: accent),
                  const SizedBox(width: 8),
                  const Text(
                    'Kategori Pengeluaran',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                  ),
                ],
              ),
              if (_selectedCategoryFilter != null)
                InkWell(
                  onTap: () => setState(() => _selectedCategoryFilter = null),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('Reset Filter ✕', style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.bold)),
                  ),
                )
              else
                Text(
                  '${sortedEntries.length} Kategori',
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Apple Card style Proportional Multi-Segment Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 10,
              child: Row(
                children: sortedEntries.map((entry) {
                  final index = sortedEntries.indexOf(entry);
                  final pct = total > 0 ? (entry.value / total) : 0.0;
                  final flexValue = (pct * 1000).toInt().clamp(1, 1000);
                  return Expanded(
                    flex: flexValue,
                    child: Container(
                      color: _getCategoryColor(index),
                      margin: const EdgeInsets.only(right: 1.5),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),

          ...sortedEntries.take(4).map((entry) {
            final cat = entry.key;
            final amount = entry.value;
            final percentage = total > 0 ? (amount / total) : 0.0;
            final index = sortedEntries.indexOf(entry);
            final color = _getCategoryColor(index);
            final isSelected = _selectedCategoryFilter == cat;

            return InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _selectedCategoryFilter = isSelected ? null : cat;
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected ? Border.all(color: color, width: 1.2) : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(_getCategoryIcon(cat), size: 14, color: color),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          cat,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.white : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          currencyFormatter.format(amount),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${(percentage * 100).toStringAsFixed(0)}%',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _claimNoSpendToday() async {
    final todayStr = StorageService.formatDateKey(DateTime.now());
    final updated = await StorageService.addNoSpendDay(todayStr);
    if (mounted) {
      setState(() {
        _noSpendDays = updated;
      });
    }

    final streak = StorageService.calculateStreak(
      transactions: _allTransactions,
      noSpendDays: updated,
    );
    final title = StorageService.getFinancialTitle(streak);
    final noSpendCount = StorageService.countNoSpendThisMonth(updated, _selectedMonth);

    _showNoSpendCelebrationModal(streak: streak, title: title, monthCount: noSpendCount);
  }

  Future<void> _cancelNoSpendToday() async {
    final todayStr = StorageService.formatDateKey(DateTime.now());
    final updated = await StorageService.removeNoSpendDay(todayStr);
    if (mounted) {
      setState(() {
        _noSpendDays = updated;
      });
    }
    _showSmartQuickInputModal();
  }

  void _promptBackfillNoSpend(String dateStr, String dayName) {
    final skin = _currentSkin;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: skin['surfaceElevated'],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: skin['border']),
        ),
        title: Row(
          children: [
            const Icon(Icons.shield, color: Color(0xFF34D399)),
            const SizedBox(width: 8),
            Text('Klaim $dayName ($dateStr)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        content: const Text(
          'Apakah di hari ini kamu juga sukses berhemat tanpa pengeluaran sama sekali (Rp 0)?\nKlaim sekarang agar catatan streak disiplinmu tidak terputus.',
          style: TextStyle(fontSize: 13, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final updated = await StorageService.addNoSpendDay(dateStr);
              if (mounted) {
                setState(() => _noSpendDays = updated);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Hari $dayName ($dateStr) tercatat sebagai Hari Hemat! 🛡️'),
                    backgroundColor: Colors.green.shade800,
                  ),
                );
              }
            },
            icon: const Icon(Icons.shield, size: 16),
            label: const Text('Klaim Hari Hemat'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _showNoSpendCelebrationModal({
    required int streak,
    required String title,
    required int monthCount,
  }) {
    final skin = _currentSkin;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: skin['surfaceElevated'],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: skin['border']),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: const Color(0xFF34D399).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF34D399), width: 2),
                ),
                alignment: Alignment.center,
                child: const Text('🛡️', style: TextStyle(fontSize: 36)),
              ),
              const SizedBox(height: 14),
              const Text(
                'Hari Hemat Rp 0 Berhasil Dicatat!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'Hebat! Menahan pengeluaran impulsif adalah langkah besar menuju kebebasan finansial.',
                style: TextStyle(fontSize: 13, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: skin['border']),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          const Text('🔥 Streak Harian', style: TextStyle(fontSize: 11, color: Colors.white60)),
                          const SizedBox(height: 4),
                          Text(
                            '$streak Hari',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepOrangeAccent),
                          ),
                        ],
                      ),
                    ),
                    Container(height: 30, width: 1, color: skin['border']),
                    Expanded(
                      child: Column(
                        children: [
                          const Text('🛡️ Hemat Bulan Ini', style: TextStyle(fontSize: 11, color: Colors.white60)),
                          const SizedBox(height: 4),
                          Text(
                            '$monthCount Hari',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF34D399)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: skin['accent'].withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.military_tech, color: skin['accent'], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pangkat Keuangan: $title',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: skin['accent']),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'Mantap, Pertahankan! 🚀',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDailyStreakCard() {
    final todayStr = StorageService.formatDateKey(DateTime.now());
    final streak = StorageService.calculateStreak(
      transactions: _allTransactions,
      noSpendDays: _noSpendDays,
    );
    final title = StorageService.getFinancialTitle(streak);
    final weekly = StorageService.getWeeklyActivity(
      transactions: _allTransactions,
      noSpendDays: _noSpendDays,
    );
    final todayTxs = _allTransactions.where((t) => t.transactionDate == todayStr).toList();
    final isTodayNoSpend = _noSpendDays.contains(todayStr);
    final isTodayCompleted = todayTxs.isNotEmpty || isTodayNoSpend;
    final noSpendMonthCount = StorageService.countNoSpendThisMonth(_noSpendDays, _selectedMonth);

    final skin = _currentSkin;
    final Color surface = skin['surface'];
    final Color border = skin['border'];
    final Color accent = skin['accent'];

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isTodayCompleted ? const Color(0xFF34D399).withValues(alpha: 0.6) : border,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isTodayCompleted ? const Color(0xFF34D399) : Colors.black).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isTodayCompleted
                      ? const Color(0xFF34D399).withValues(alpha: 0.2)
                      : Colors.amber.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  isTodayCompleted ? '🔥' : '⏳',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          streak > 0 ? '$streak Hari Beruntun' : 'Mulai Kebiasaan',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: accent,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isTodayCompleted
                          ? (isTodayNoSpend
                              ? 'Hari ini: 🛡️ Hari Hemat Rp 0 aktif'
                              : 'Hari ini: ${todayTxs.length} transaksi tercatat')
                          : 'Cek keuangan hari ini untuk menjaga streak!',
                      style: TextStyle(
                        fontSize: 12,
                        color: isTodayCompleted ? const Color(0xFF34D399) : Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              if (noSpendMonthCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF34D399).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield, size: 12, color: Color(0xFF34D399)),
                      const SizedBox(width: 4),
                      Text(
                        '$noSpendMonthCount hari hemat',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF34D399)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Kalender 7 Hari Terakhir
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: weekly.map((day) {
                final isToday = day.isToday;
                Color dotBg;
                Widget dotChild;

                if (day.hasTransaction) {
                  dotBg = Colors.amber.withValues(alpha: 0.25);
                  dotChild = const Text('🔥', style: TextStyle(fontSize: 11));
                } else if (day.isNoSpend) {
                  dotBg = const Color(0xFF34D399).withValues(alpha: 0.25);
                  dotChild = const Icon(Icons.shield, size: 12, color: Color(0xFF34D399));
                } else if (isToday) {
                  dotBg = Colors.amber.withValues(alpha: 0.15);
                  dotChild = const Text('⏳', style: TextStyle(fontSize: 10));
                } else {
                  dotBg = Colors.white12;
                  dotChild = Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: Colors.white38,
                      shape: BoxShape.circle,
                    ),
                  );
                }

                return InkWell(
                  onTap: () {
                    if (!isToday && day.isMissed) {
                      _promptBackfillNoSpend(day.dateStr, day.dayName);
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Column(
                      children: [
                        Text(
                          isToday ? 'Hari Ini' : day.dayName,
                          style: TextStyle(
                            fontSize: isToday ? 10 : 11,
                            fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                            color: isToday ? accent : Colors.white60,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: dotBg,
                            shape: BoxShape.circle,
                            border: isToday
                                ? Border.all(color: accent, width: 1.5)
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: dotChild,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          // Tombol Aksi Harian
          if (!isTodayCompleted) ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: _claimNoSpendToday,
                    icon: const Icon(Icons.shield_outlined, size: 18),
                    label: const Text(
                      'Hari Ini Rp 0 (Hemat)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: _showSmartQuickInputModal,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text(
                      'Ada Jajan',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (isTodayNoSpend) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, size: 16, color: Color(0xFF34D399)),
                      const SizedBox(width: 6),
                      const Flexible(
                        child: Text(
                          'Terklaim No-Spend Day! 🛡️',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF34D399),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _cancelNoSpendToday,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text(
                    'Eh, ada jajan tadi',
                    style: TextStyle(fontSize: 11, color: Colors.white60),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _toggleBalanceVisibility() async {
    final next = !_isBalanceVisible;
    setState(() => _isBalanceVisible = next);
    await StorageService.saveBalanceVisibility(next);
  }

  void _cycleCardSkin() async {
    HapticFeedback.mediumImpact();
    final next = (_selectedCardSkinIndex + 1) % _cardSkins.length;
    setState(() => _selectedCardSkinIndex = next);
    await StorageService.saveCardSkinIndex(next);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tema: ${_cardSkins[next]['icon']} ${_cardSkins[next]['name']} aktif! ✨'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildMonthSelector(String currentMonthLabel) {
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;
    final skin = _currentSkin;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: skin['surface'],
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: skin['border']),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 14),
            color: Colors.white70,
            onPressed: _previousMonth,
            tooltip: 'Bulan Sebelumnya',
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_month, size: 16, color: skin['accent']),
              const SizedBox(width: 6),
              Text(
                currentMonthLabel,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
              ),
              if (!isCurrentMonth) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    setState(() {
                      _selectedMonth = DateTime(now.year, now.month);
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: (skin['accent'] as Color).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: skin['accent']),
                    ),
                    child: Text(
                      'Bulan Ini',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: skin['accent']),
                    ),
                  ),
                ),
              ],
            ],
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 14),
            color: Colors.white70,
            onPressed: _nextMonth,
            tooltip: 'Bulan Berikutnya',
          ),
        ],
      ),
    );
  }

  Widget _buildNeoBankHeroCard(String currentMonthLabel) {
    final skin = _currentSkin;
    final List<Color> colors = skin['colors'];
    final Color accent = skin['accent'];
    final Color chipColor = skin['chip'];
    final String tag = skin['tag'];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1.2,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -30,
                right: -30,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        accent.withValues(alpha: 0.35),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -40,
                left: -20,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(22.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 26,
                              decoration: BoxDecoration(
                                color: chipColor.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: chipColor.withValues(alpha: 0.8),
                                  width: 1.2,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Container(
                                      width: 20,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        border: Border.all(color: chipColor.withValues(alpha: 0.6), width: 0.8),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(width: 8, height: 1, color: chipColor.withValues(alpha: 0.6)),
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Container(width: 8, height: 1, color: chipColor.withValues(alpha: 0.6)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Icon(Icons.contactless, color: Colors.white70, size: 20),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              color: accent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'SALDO KEUANGAN',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                        InkWell(
                          onTap: _toggleBalanceVisibility,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              _isBalanceVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              color: Colors.white70,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isBalanceVisible
                          ? currencyFormatter.format(_saldoBulanIni)
                          : 'Rp ••••••••',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.greenAccent.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.arrow_downward, color: Colors.greenAccent, size: 12),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Masuk', style: TextStyle(color: Colors.white60, fontSize: 10)),
                                      Text(
                                        _isBalanceVisible
                                            ? currencyFormatter.format(_totalPemasukanBulanIni)
                                            : '+Rp •••',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.arrow_upward, color: Colors.redAccent, size: 12),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Keluar', style: TextStyle(color: Colors.white60, fontSize: 10)),
                                      Text(
                                        _isBalanceVisible
                                            ? currencyFormatter.format(_totalPengeluaranBulanIni)
                                            : '-Rp •••',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _userName?.isNotEmpty == true ? _userName!.toUpperCase() : 'DOMPET UTAMA',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          'PERIODE: ${currentMonthLabel.toUpperCase()}',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernActionDock() {
    final todayStr = StorageService.formatDateKey(DateTime.now());
    final isTodayNoSpend = _noSpendDays.contains(todayStr);

    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: _buildActionDockItem(
              icon: Icons.flash_on,
              label: 'Catat Cepat',
              color: const Color(0xFFFBBF24),
              onTap: _showSmartQuickInputModal,
            ),
          ),
          Expanded(
            child: _buildActionDockItem(
              icon: Icons.qr_code_scanner,
              label: 'Pindai Bukti',
              color: const Color(0xFF38BDF8),
              onTap: _showImageSourceDialog,
            ),
          ),
          Expanded(
            child: _buildActionDockItem(
              icon: isTodayNoSpend ? Icons.verified : Icons.shield_outlined,
              label: isTodayNoSpend ? 'Terklaim 🛡️' : 'Hari Hemat',
              color: const Color(0xFF34D399),
              onTap: _claimNoSpendToday,
            ),
          ),
          Expanded(
            child: _buildActionDockItem(
              icon: Icons.ios_share,
              label: 'Ekspor Data',
              color: const Color(0xFFA78BFA),
              onTap: _showExportDialog,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionDockItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final skin = _currentSkin;
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: skin['surface'],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: skin['border'], width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _previousMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentMonthLabel = '${_monthNames[_selectedMonth.month - 1]} ${_selectedMonth.year}';
    final transactionsToShow = _filteredTransactions;
    final skin = _currentSkin;
    final Color bg = skin['bg'];
    final Color surface = skin['surface'];
    final Color surfaceElevated = skin['surfaceElevated'];
    final Color border = skin['border'];
    final Color accent = skin['accent'];

    // Kelompokkan transaksi per tanggal untuk tampilan neo-banking profesional
    final Map<String, List<TransactionModel>> groupedByDate = {};
    for (final tx in transactionsToShow) {
      groupedByDate.putIfAbsent(tx.transactionDate, () => []).add(tx);
    }
    final sortedDates = groupedByDate.keys.toList()..sort((a, b) => b.compareTo(a));

    final todayStr = StorageService.formatDateKey(DateTime.now());
    final yesterdayStr = StorageService.formatDateKey(DateTime.now().subtract(const Duration(days: 1)));

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: accent, width: 1.5),
              ),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: accent.withValues(alpha: 0.15),
                child: Text(
                  (_userName?.isNotEmpty == true ? _userName![0] : 'C').toUpperCase(),
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Halo, ${_userName?.isNotEmpty == true ? _userName : "Teman Hemat"} 👋',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white60,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Row(
                  children: [
                    const Text(
                      'CatatDuit',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        letterSpacing: -0.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'NEO',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: accent,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          InkWell(
            onTap: _cycleCardSkin,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  Text(skin['icon'] as String, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  Text(
                    (skin['name'] as String).split(' ').first,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accent),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Atur Profil & Nama',
            icon: Icon(
              Icons.account_circle_outlined,
              color: _userName != null ? accent : Colors.white60,
            ),
            onPressed: _showProfileDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildMonthSelector(currentMonthLabel),
              _buildNeoBankHeroCard(currentMonthLabel),
              _buildModernActionDock(),
              _buildDailyStreakCard(),
              _buildCategoryBreakdownCard(),
              const SizedBox(height: 22),

              // Header Riwayat Transaksi Bulan Ini
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Riwayat Transaksi',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    '${transactionsToShow.length} dari ${_monthlyTransactions.length}',
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Bar Pencarian Modern Neo
              TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Cari toko, keterangan, nominal...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                  prefixIcon: Icon(Icons.search, size: 20, color: accent),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18, color: Colors.white60),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  filled: true,
                  fillColor: surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: accent, width: 1.5),
                  ),
                ),
                onChanged: (val) {
                  setState(() => _searchQuery = val.trim());
                },
              ),
              const SizedBox(height: 10),

              // Filter Chips Neo-Banking (Semua, Masuk, Keluar)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterPill(
                      label: 'Semua (${_monthlyTransactions.length})',
                      isSelected: _selectedFilterFlow == 'ALL',
                      onTap: () => setState(() => _selectedFilterFlow = 'ALL'),
                    ),
                    const SizedBox(width: 8),
                    _buildFilterPill(
                      label: '🟢 Uang Masuk',
                      isSelected: _selectedFilterFlow == 'PEMASUKAN',
                      onTap: () => setState(() => _selectedFilterFlow = 'PEMASUKAN'),
                    ),
                    const SizedBox(width: 8),
                    _buildFilterPill(
                      label: '🔴 Uang Keluar',
                      isSelected: _selectedFilterFlow == 'PENGELUARAN',
                      onTap: () => setState(() => _selectedFilterFlow = 'PENGELUARAN'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              if (transactionsToShow.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: border),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.receipt_long_outlined, size: 48, color: accent),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _monthlyTransactions.isEmpty
                              ? 'Belum ada transaksi di bulan $currentMonthLabel'
                              : 'Tidak ada transaksi yang cocok',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _monthlyTransactions.isEmpty
                              ? 'Catat manual dengan Numpad atau pindai bukti transfer'
                              : 'Coba ubah kata kunci pencarian atau filter kategori',
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        if (_monthlyTransactions.isEmpty) ...[
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _showImageSourceDialog,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Tambah Transaksi Pertama', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                ...sortedDates.map((dateStr) {
                  final dayTxs = groupedByDate[dateStr]!;
                  final dayIncome = dayTxs.where((t) => t.flowType == 'PEMASUKAN').fold(0.0, (acc, t) => acc + t.totalAmount);
                  final dayExpense = dayTxs.where((t) => t.flowType == 'PENGELUARAN').fold(0.0, (acc, t) => acc + t.totalAmount);
                  final dayNet = dayIncome - dayExpense;

                  String headerLabel;
                  if (dateStr == todayStr) {
                    headerLabel = 'HARI INI';
                  } else if (dateStr == yesterdayStr) {
                    headerLabel = 'KEMARIN';
                  } else {
                    headerLabel = dateStr;
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              headerLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: accent,
                                letterSpacing: 0.8,
                              ),
                            ),
                            Text(
                              '${dayNet >= 0 ? "+" : ""}${currencyFormatter.format(dayNet)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: dayNet >= 0 ? const Color(0xFF34D399) : const Color(0xFFFB7185),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...dayTxs.map((tx) {
                        final originalIndex = _allTransactions.indexOf(tx);
                        return _buildTransactionCard(tx, originalIndex);
                      }),
                    ],
                  );
                }),
              const SizedBox(height: 70),
            ],
          ),

          if (_isScanning)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    color: surfaceElevated,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: accent),
                      const SizedBox(height: 16),
                      const Text(
                        'Sedang membaca bukti transfer...',
                        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showImageSourceDialog,
        backgroundColor: accent,
        foregroundColor: Colors.black,
        elevation: 6,
        icon: const Icon(Icons.add, size: 22),
        label: const Text(
          'Tambah Transaksi',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildFilterPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final skin = _currentSkin;
    final Color accent = skin['accent'];
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.18) : skin['surface'],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? accent : skin['border'],
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(TransactionModel tx, int originalIndex) {
    final isIncome = tx.flowType == 'PEMASUKAN';
    final skin = _currentSkin;
    final Color surface = skin['surface'];
    final Color border = skin['border'];

    return Dismissible(
      key: Key('${tx.transactionDate}_${tx.referenceNumber}_$originalIndex'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) async {
        if (originalIndex != -1 && originalIndex < _allTransactions.length) {
          final updated = await StorageService.deleteTransaction(originalIndex);
          if (mounted) {
            setState(() {
              _allTransactions = updated;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Transaksi berhasil dihapus')),
            );
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border),
        ),
        child: ListTile(
          onTap: () => _showTransactionDetailDialog(tx, originalIndex),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isIncome
                  ? const Color(0xFF34D399).withValues(alpha: 0.15)
                  : const Color(0xFFFB7185).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _getCategoryIcon(tx.category),
              color: isIncome ? const Color(0xFF34D399) : const Color(0xFFFB7185),
              size: 20,
            ),
          ),
          title: Text(
            tx.description?.isNotEmpty == true ? tx.description! : tx.recipientName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
          ),
          subtitle: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tx.sourcePlatform.toUpperCase(),
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white60),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${tx.category} • ${tx.transactionTime ?? ""}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ),
            ],
          ),
          trailing: Text(
            '${isIncome ? '+' : '-'}${currencyFormatter.format(tx.totalAmount)}',
            style: TextStyle(
              color: isIncome ? const Color(0xFF34D399) : const Color(0xFFFB7185),
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
