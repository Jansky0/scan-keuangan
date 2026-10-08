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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
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
  final TextEditingController _searchController = TextEditingController();

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
    if (mounted) {
      setState(() {
        _allTransactions = list;
        _userName = name;
        _noSpendDays = noSpend;
      });
    }
  }

  void _initShareIntentListener() {
    // 1. Mendengarkan share saat aplikasi sedang berjalan
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        final path = value.first.path;
        ReceiveSharingIntent.instance.reset();
        _processIncomingPath(path);
      }
    }, onError: (err) {
      debugPrint("Error sharing stream: $err");
    });

    // 2. Mendengarkan share saat aplikasi baru dibuka (Cold Start)
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

  Future<String?> _cropImage(String filePath) async {
    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: filePath,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 95,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Potong Bukti / Kwitansi',
            toolbarColor: const Color(0xFF0F766E),
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: const Color(0xFF0F766E),
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
      // Fallback ke gambar asli jika cropper mengalami kendala
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
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Pilih Bukti Transaksi',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
              const SizedBox(height: 6),
              Text(
                'Pilih gambar, lalu potong area nominal transaksi agar scan akurat',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.teal.shade50,
                  child: const Icon(Icons.crop, color: Color(0xFF0F766E)),
                ),
                title: const Text('Galeri (Screenshot / Foto)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Pilih tangkapan layar Livin, BCA, potong area nominal', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
              const Divider(height: 12),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.teal.shade50,
                  child: const Icon(Icons.camera_alt, color: Color(0xFF0F766E)),
                ),
                title: const Text('Kamera', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Foto langsung struk kertas belanja / kasir', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              const Divider(height: 12),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.amber.shade50,
                  child: const Icon(Icons.flash_on, color: Color(0xFFB45309)),
                ),
                title: const Text('Catat Cepat Interaktif (Tanpa Bukti)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Kalkulator pintar, tombol preset, rasio kebutuhan vs jajan', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, size: 20),
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

  void _showErrorDialog(String errorMsg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.orange),
            SizedBox(width: 8),
            Text('Gagal Scan Bukti'),
          ],
        ),
        content: Text(
          errorMsg,
          style: const TextStyle(fontSize: 13, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              final sampleTx = ScannerService.getSampleShopeePayData();
              _showConfirmationDialog(sampleTx);
            },
            child: const Text('Pakai Data Contoh'),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Row(
                    children: [
                      Icon(Icons.edit_note, color: Color(0xFF0F766E)),
                      SizedBox(width: 8),
                      Text('Koreksi Nominal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  content: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixText: 'Rp ',
                      border: OutlineInputBorder(),
                      labelText: 'Nominal Transaksi',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      child: const Text('Batal'),
                    ),
                    FilledButton(
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
                      child: const Text('Simpan'),
                    ),
                  ],
                ),
              );
            }

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Konfirmasi Transaksi',
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),

                    // Selector Arus Keuangan: 🟢 PEMASUKAN vs 🔴 PENGELUARAN
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setModalState(() {
                                currentFlowType = 'PEMASUKAN';
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: isIncome ? Colors.green.shade600 : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isIncome ? Colors.green.shade700 : Colors.grey.shade300,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.arrow_downward,
                                    size: 18,
                                    color: isIncome ? Colors.white : Colors.grey.shade700,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'UANG MASUK',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: isIncome ? Colors.white : Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setModalState(() {
                                currentFlowType = 'PENGELUARAN';
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: !isIncome ? Colors.red.shade600 : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: !isIncome ? Colors.red.shade700 : Colors.grey.shade300,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.arrow_upward,
                                    size: 18,
                                    color: !isIncome ? Colors.white : Colors.grey.shade700,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'UANG KELUAR',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: !isIncome ? Colors.white : Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Detail Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          _buildRowItem('Platform', initialTx.sourcePlatform),
                          const Divider(height: 16),
                          _buildRowItem(
                            'Nominal',
                            currencyFormatter.format(currentTotalAmount),
                            valueStyle: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: isIncome ? Colors.green.shade700 : Colors.red.shade700,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit, size: 16, color: Colors.grey),
                              onPressed: editAmountDialog,
                              tooltip: 'Koreksi Nominal',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            onTap: editAmountDialog,
                          ),
                          if (initialTx.senderName != null) ...[
                            const Divider(height: 16),
                            _buildRowItem('Pengirim', initialTx.senderName!),
                          ],
                          const Divider(height: 16),
                          _buildRowItem('Penerima / Toko', initialTx.recipientName),
                          if (initialTx.destinationBankOrWallet != null) ...[
                            const Divider(height: 16),
                            _buildRowItem('Bank Tujuan', '${initialTx.destinationBankOrWallet} ${initialTx.destinationAccount ?? ""}'),
                          ],
                          if (initialTx.description != null && initialTx.description!.isNotEmpty) ...[
                            const Divider(height: 16),
                            _buildRowItem('Catatan / Berita', initialTx.description!),
                          ],
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Kategori', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                              DropdownButton<String>(
                                value: categories.contains(currentCategory) ? currentCategory : 'Lainnya',
                                isDense: true,
                                underline: const SizedBox(),
                                items: categories.map((cat) {
                                  return DropdownMenuItem(value: cat, child: Text(cat, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)));
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setModalState(() {
                                      currentCategory = val;
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          _buildRowItem('Tanggal & Jam', '${initialTx.transactionDate} ${initialTx.transactionTime ?? ""}'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Tombol Simpan
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
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

                          final updated = await StorageService.addTransaction(finalTx);
                          final updatedNoSpend = await StorageService.removeNoSpendDay(finalTx.transactionDate);
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }
                          if (mounted) {
                            setState(() {
                              _allTransactions = updated;
                              _noSpendDays = updatedNoSpend;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Transaksi ${currencyFormatter.format(finalTx.totalAmount)} tersimpan!'),
                                backgroundColor: Colors.green.shade800,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text(
                          'Simpan Transaksi',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),

                    if (originalFilePath != null && !originalFilePath.toLowerCase().endsWith('.pdf')) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final newCropped = await _cropImage(originalFilePath);
                            if (newCropped != null) {
                              _handleIncomingFile(newCropped, originalPath: originalFilePath);
                            }
                          },
                          icon: const Icon(Icons.crop, size: 18),
                          label: const Text(
                            'Potong Ulang Bagian Lain',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0F766E),
                            side: const BorderSide(color: Color(0xFF0F766E)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRowItem(
    String label,
    String value, {
    TextStyle? valueStyle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final rowContent = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        const SizedBox(width: 8),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: valueStyle ?? const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 6),
                trailing,
              ],
            ],
          ),
        ),
      ],
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: rowContent,
        ),
      );
    }
    return rowContent;
  }

  void _showProfileDialog() {
    final controller = TextEditingController(text: _userName ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.person, color: Color(0xFF0F766E)),
            SizedBox(width: 8),
            Text('Nama Pemilik Akun'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Masukkan nama rekening/e-wallet Anda (misal: Andika). Sistem akan otomatis mengenali uang masuk jika nama Anda tertera di bagian penerima.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Contoh: Andika Ramadhan',
                labelText: 'Nama Anda',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              await StorageService.saveUserName(name);
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (mounted) {
                setState(() {
                  _userName = name.isEmpty ? null : name;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Nama pemilik berhasil disimpan!')),
                );
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  // Modal Catat Cepat & Cerdas (Smart Quick Input dengan Numpad & Budget Impact)
  void _showSmartQuickInputModal() {
    String flowType = 'PENGELUARAN';
    String natureTag = 'Kebutuhan'; // 'Kebutuhan' atau 'Keinginan'
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

            void onAddAmount(int increment) {
              HapticFeedback.selectionClick();
              setModalState(() {
                final current = double.tryParse(rawNominal) ?? 0.0;
                rawNominal = (current + increment).toInt().toString();
              });
            }

            void applyPreset(Map<String, dynamic> preset) {
              HapticFeedback.mediumImpact();
              setModalState(() {
                rawNominal = preset['amount'].toString();
                category = preset['cat'] as String;
                natureTag = preset['nature'] as String;
                flowType = 'PENGELUARAN';
                noteController.text = preset['note'] as String;
              });
            }

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle Bar
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Baris Judul & Toggle Arus (Masuk / Keluar)
                    Row(
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.bolt, color: Color(0xFF0F766E), size: 22),
                            SizedBox(width: 6),
                            Text(
                              'Catat Cepat',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const Spacer(),
                        // Segmented Flow Toggle
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
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
                                    color: !isIncome ? Colors.red.shade600 : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Keluar',
                                    style: TextStyle(
                                      color: !isIncome ? Colors.white : Colors.grey.shade700,
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
                                    color: isIncome ? Colors.green.shade600 : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Masuk',
                                    style: TextStyle(
                                      color: isIncome ? Colors.white : Colors.grey.shade700,
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

                    // Template Cepat (Hanya muncul jika pengeluaran)
                    if (!isIncome) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: presets.map((p) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                label: Text(p['label'] as String, style: const TextStyle(fontSize: 12)),
                                backgroundColor: Colors.teal.shade50,
                                side: BorderSide(color: Colors.teal.shade100),
                                onPressed: () => applyPreset(p),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Display Nominal Jumbo
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      decoration: BoxDecoration(
                        color: isIncome ? Colors.green.shade50 : Colors.red.shade50.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isIncome ? Colors.green.shade200 : Colors.red.shade200,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${isIncome ? '+' : '-'}Rp ',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: isIncome ? Colors.green.shade800 : Colors.red.shade800,
                                ),
                              ),
                              Text(
                                rawNominal.isEmpty
                                    ? '0'
                                    : NumberFormat('#,###', 'id_ID').format(currentAmount),
                                style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                  color: isIncome ? Colors.green.shade900 : Colors.red.shade900,
                                ),
                              ),
                              if (rawNominal.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.cancel, size: 20, color: Colors.grey),
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    setModalState(() => rawNominal = '');
                                  },
                                ),
                            ],
                          ),

                          // Smart Financial Impact Badge (Real-Time Budget Impact)
                          if (currentAmount > 0) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    !isIncome && currentAmount > _saldoBulanIni && _saldoBulanIni > 0
                                        ? Icons.warning_amber_rounded
                                        : Icons.account_balance_wallet,
                                    size: 15,
                                    color: !isIncome && currentAmount > _saldoBulanIni && _saldoBulanIni > 0
                                        ? Colors.orange.shade800
                                        : const Color(0xFF0F766E),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      !isIncome && currentAmount > _saldoBulanIni && _saldoBulanIni > 0
                                          ? '⚠️ Melebihi sisa dana bulan ini!'
                                          : 'Sisa saldo nanti: ${currencyFormatter.format(sisaSetelah)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: !isIncome && currentAmount > _saldoBulanIni && _saldoBulanIni > 0
                                            ? Colors.orange.shade800
                                            : Colors.grey.shade800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Quick Increment Chips (+5rb, +10rb, +20rb, +50rb, +100rb)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [5000, 10000, 20000, 50000, 100000].map((inc) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                side: BorderSide(color: Colors.grey.shade300),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () => onAddAmount(inc),
                              child: Text(
                                '+${inc >= 1000 ? '${inc ~/ 1000}rb' : inc}',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Sifat Pengeluaran: Kebutuhan vs Keinginan
                    if (!isIncome) ...[
                      Row(
                        children: [
                          const Text('Sifat:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('🟢 Kebutuhan (Pokok)', style: TextStyle(fontSize: 11)),
                            selected: natureTag == 'Kebutuhan',
                            onSelected: (val) {
                              if (val) {
                                HapticFeedback.selectionClick();
                                setModalState(() => natureTag = 'Kebutuhan');
                              }
                            },
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            label: const Text('🟣 Keinginan (Jajan)', style: TextStyle(fontSize: 11)),
                            selected: natureTag == 'Keinginan',
                            onSelected: (val) {
                              if (val) {
                                HapticFeedback.selectionClick();
                                setModalState(() => natureTag = 'Keinginan');
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Pemilih Kategori (Horizontal Grid Chips)
                    const Text('Kategori:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: categories.map((catItem) {
                          final name = catItem['name'] as String;
                          final isSelected = category == name;
                          final icon = catItem['icon'] as IconData;
                          final color = catItem['color'] as Color;

                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: InkWell(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setModalState(() => category = name);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected ? color.withValues(alpha: 0.12) : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected ? color : Colors.grey.shade300,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(icon, size: 16, color: isSelected ? color : Colors.grey.shade600),
                                    const SizedBox(width: 6),
                                    Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        color: isSelected ? color : Colors.grey.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Catatan Singkat
                    TextField(
                      controller: noteController,
                      decoration: InputDecoration(
                        hintText: 'Keterangan (misal: Warteg Bu Siti, Alfamart, SPBU...)',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Custom Responsive Numpad (1 - 9, 000, 0, ⌫)
                    _buildInteractiveNumpad(onDigitPress),

                    const SizedBox(height: 14),

                    // Tombol Simpan
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: isIncome ? Colors.green.shade700 : const Color(0xFF0F766E),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: currentAmount <= 0
                            ? null
                            : () async {
                                final note = noteController.text.trim();
                                final naturePrefix = !isIncome ? '[$natureTag] ' : '';
                                final finalDescription = '$naturePrefix$note'.trim();

                                final newTx = TransactionModel(
                                  status: 'SUCCESS',
                                  flowType: flowType,
                                  sourcePlatform: platform,
                                  transactionType: isIncome ? 'Uang Masuk' : 'Pengeluaran Cepat',
                                  amount: currentAmount,
                                  adminFee: 0,
                                  totalAmount: currentAmount,
                                  senderName: isIncome ? (note.isNotEmpty ? note : 'Pendapatan Lain') : _userName,
                                  recipientName: !isIncome ? (note.isNotEmpty ? note : category) : (_userName ?? 'Saya'),
                                  destinationBankOrWallet: platform,
                                  transactionDate: DateFormat('yyyy-MM-dd').format(DateTime.now()),
                                  transactionTime: DateFormat('HH:mm').format(DateTime.now()),
                                  description: finalDescription.isNotEmpty ? finalDescription : null,
                                  category: category,
                                );

                                final updated = await StorageService.addTransaction(newTx);
                                final updatedNoSpend = await StorageService.removeNoSpendDay(newTx.transactionDate);
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  setState(() {
                                    _allTransactions = updated;
                                    _noSpendDays = updatedNoSpend;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Tercatat: ${currencyFormatter.format(currentAmount)} ($category)'),
                                      backgroundColor: Colors.green.shade800,
                                    ),
                                  );
                                }
                              },
                        child: Text(
                          currentAmount <= 0
                              ? 'Masukkan Nominal'
                              : 'Simpan ${isIncome ? 'Pemasukan' : 'Pengeluaran'} (${currencyFormatter.format(currentAmount)})',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
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

  // Helper Numpad Interaktif
  Widget _buildInteractiveNumpad(Function(String) onDigitPress) {
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
              final isTripleZero = key == '000';
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    onTap: () => onDigitPress(key),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: isDelete ? Colors.red.shade50 : (isTripleZero ? Colors.teal.shade50 : Colors.grey.shade100),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      alignment: Alignment.center,
                      child: isDelete
                          ? Icon(Icons.backspace_outlined, size: 20, color: Colors.red.shade700)
                          : Text(
                              key,
                              style: TextStyle(
                                fontSize: isTripleZero ? 16 : 20,
                                fontWeight: FontWeight.bold,
                                color: isTripleZero ? const Color(0xFF0F766E) : Colors.grey.shade900,
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

  // Modal Ekspor Laporan Bulanan (CSV / WhatsApp)
  void _showExportDialog() {
    final currentMonthLabel = '${_monthNames[_selectedMonth.month - 1]} ${_selectedMonth.year}';
    final transactions = _monthlyTransactions;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Ekspor Laporan ($currentMonthLabel)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
              const SizedBox(height: 6),
              Text(
                'Salin ringkasan ke WhatsApp atau simpan file CSV untuk dibuka di Excel',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade50,
                  child: const Icon(Icons.copy, color: Colors.green),
                ),
                title: const Text('Salin Ringkasan Teks', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Format rapi untuk dibagikan ke WhatsApp / Catatan', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, size: 20),
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
              const Divider(height: 12),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade50,
                  child: const Icon(Icons.table_chart, color: Colors.blue),
                ),
                title: const Text('Unduh File CSV (Excel)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Simpan file spreadsheet ke folder Download HP', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, size: 20),
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
                        content: Text('File CSV berhasil disimpan ke:\n$path'),
                        duration: const Duration(seconds: 4),
                        backgroundColor: Colors.blue.shade800,
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

  // Modal Detail & Hapus Transaksi
  void _showTransactionDetailDialog(TransactionModel tx, int originalIndex) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isIncome = tx.flowType == 'PEMASUKAN';
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Detail Transaksi',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isIncome ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isIncome ? 'UANG MASUK' : 'UANG KELUAR',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isIncome ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    _buildRowItem('Platform', tx.sourcePlatform),
                    const Divider(height: 16),
                    _buildRowItem(
                      'Nominal',
                      '${isIncome ? '+' : '-'}${currencyFormatter.format(tx.totalAmount)}',
                      valueStyle: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isIncome ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    ),
                    if (tx.senderName != null && tx.senderName!.isNotEmpty) ...[
                      const Divider(height: 16),
                      _buildRowItem('Pengirim', tx.senderName!),
                    ],
                    const Divider(height: 16),
                    _buildRowItem('Penerima / Toko', tx.recipientName),
                    if (tx.destinationBankOrWallet != null) ...[
                      const Divider(height: 16),
                      _buildRowItem('Bank / Tujuan', '${tx.destinationBankOrWallet} ${tx.destinationAccount ?? ""}'),
                    ],
                    if (tx.description != null && tx.description!.isNotEmpty) ...[
                      const Divider(height: 16),
                      _buildRowItem('Catatan', tx.description!),
                    ],
                    const Divider(height: 16),
                    _buildRowItem('Kategori', tx.category),
                    const Divider(height: 16),
                    _buildRowItem('Tanggal & Jam', '${tx.transactionDate} ${tx.transactionTime ?? ""}'),
                    if (tx.referenceNumber != null && tx.referenceNumber!.isNotEmpty) ...[
                      const Divider(height: 16),
                      _buildRowItem('No. Referensi', tx.referenceNumber!),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final updated = await StorageService.deleteTransaction(originalIndex);
                    if (mounted) {
                      setState(() {
                        _allTransactions = updated;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Transaksi berhasil dihapus')),
                      );
                    }
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text('Hapus Transaksi Ini', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Filter transaksi berdasarkan bulan yang dipilih
  List<TransactionModel> get _monthlyTransactions {
    final year = _selectedMonth.year.toString();
    final month = _selectedMonth.month.toString().padLeft(2, '0');
    final prefix = '$year-$month';

    return _allTransactions.where((t) => t.transactionDate.startsWith(prefix)).toList();
  }

  // Filter transaksi berdasarkan pencarian dan tipe arus
  List<TransactionModel> get _filteredTransactions {
    return _monthlyTransactions.where((tx) {
      if (_selectedFilterFlow != 'ALL' && tx.flowType != _selectedFilterFlow) {
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
      Color(0xFFE11D48), // Rose
      Color(0xFFEA580C), // Orange
      Color(0xFFD97706), // Amber
      Color(0xFF059669), // Emerald
      Color(0xFF2563EB), // Blue
      Color(0xFF7C3AED), // Violet
      Color(0xFFDB2777), // Pink
      Color(0xFF475569), // Slate
    ];
    return colors[index % colors.length];
  }

  // Widget Kartu Distribusi Pengeluaran per Kategori
  Widget _buildCategoryBreakdownCard() {
    final expenses = _categoryExpenses;
    if (expenses.isEmpty) return const SizedBox.shrink();

    final total = _totalPengeluaranBulanIni;
    final sortedEntries = expenses.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.pie_chart, size: 18, color: Color(0xFF0F766E)),
                  SizedBox(width: 8),
                  Text(
                    'Kategori Pengeluaran',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
              Text(
                '${sortedEntries.length} Kategori',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...sortedEntries.take(4).map((entry) {
            final cat = entry.key;
            final amount = entry.value;
            final percentage = total > 0 ? (amount / total) : 0.0;
            final index = sortedEntries.indexOf(entry);
            final color = _getCategoryColor(index);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(_getCategoryIcon(cat), size: 14, color: color),
                          const SizedBox(width: 6),
                          Text(cat, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      Text(
                        '${currencyFormatter.format(amount)} (${(percentage * 100).toStringAsFixed(0)}%)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percentage,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade100,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            );
          }),

          // Rasio Evaluasi Finansial (Kebutuhan vs Keinginan)
          if (total > 0) ...[
            Builder(builder: (c) {
              double totalKebutuhan = 0;
              double totalKeinginan = 0;
              for (final tx in _monthlyTransactions.where((t) => t.flowType == 'PENGELUARAN')) {
                final desc = tx.description ?? '';
                if (desc.contains('[Keinginan]') || tx.category == 'Hiburan' || tx.category == 'Kopi & Nongkrong') {
                  totalKeinginan += tx.totalAmount;
                } else {
                  totalKebutuhan += tx.totalAmount;
                }
              }
              final pctKebutuhan = (totalKebutuhan / total * 100).toStringAsFixed(0);
              final pctKeinginan = (totalKeinginan / total * 100).toStringAsFixed(0);

              return Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.psychology, size: 16, color: Color(0xFF0F766E)),
                            SizedBox(width: 6),
                            Text(
                              'Rasio Kebutuhan vs Jajan',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Text(
                          '$pctKebutuhan% : $pctKeinginan%',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Row(
                        children: [
                          Expanded(
                            flex: (totalKebutuhan > 0 ? totalKebutuhan : 1).toInt(),
                            child: Container(height: 6, color: Colors.green.shade600),
                          ),
                          Expanded(
                            flex: (totalKeinginan > 0 ? totalKeinginan : 1).toInt(),
                            child: Container(height: 6, color: Colors.purple.shade500),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('🟢 Kebutuhan: ${currencyFormatter.format(totalKebutuhan)}', style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                        Text('🟣 Jajan: ${currencyFormatter.format(totalKeinginan)}', style: TextStyle(fontSize: 11, color: Colors.purple.shade700, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // Klaim status Hari Hemat Rp 0 hari ini
  Future<void> _claimNoSpendToday() async {
    HapticFeedback.mediumImpact();
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

  // Batalkan status Hari Hemat Rp 0 hari ini (misal ternyata jajan malam hari)
  Future<void> _cancelNoSpendToday() async {
    final todayStr = StorageService.formatDateKey(DateTime.now());
    final updated = await StorageService.removeNoSpendDay(todayStr);
    if (mounted) {
      setState(() {
        _noSpendDays = updated;
      });
    }
    // Langsung buka modal catat cepat agar user bisa mencatat jajannya
    _showSmartQuickInputModal();
  }

  // Dialog untuk mengklaim hari kemarin jika sempat terlewat
  void _promptBackfillNoSpend(String dateStr, String dayName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.shield, color: Color(0xFF059669)),
            const SizedBox(width: 8),
            Text('Klaim $dayName ($dateStr)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Apakah di hari ini kamu juga sukses berhemat tanpa pengeluaran sama sekali (Rp 0)?\nKlaim sekarang agar catatan streak disiplinmu tidak terputus.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
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

  // Modal Apresiasi & Gamifikasi saat Klaim Hari Hemat Rp 0
  void _showNoSpendCelebrationModal({
    required int streak,
    required String title,
    required int monthCount,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.green.shade200, width: 2),
                ),
                alignment: Alignment.center,
                child: const Text('🛡️', style: TextStyle(fontSize: 36)),
              ),
              const SizedBox(height: 14),
              const Text(
                'Hari Hemat Rp 0 Berhasil Dicatat!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Hebat! Menahan pengeluaran impulsif adalah langkah besar menuju kebebasan finansial.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          const Text('🔥 Streak Harian', style: TextStyle(fontSize: 11, color: Colors.black54)),
                          const SizedBox(height: 4),
                          Text(
                            '$streak Hari',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                          ),
                        ],
                      ),
                    ),
                    Container(height: 30, width: 1, color: Colors.grey.shade300),
                    Expanded(
                      child: Column(
                        children: [
                          const Text('🛡️ Hemat Bulan Ini', style: TextStyle(fontSize: 11, color: Colors.black54)),
                          const SizedBox(height: 4),
                          Text(
                            '$monthCount Hari',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green.shade700),
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
                  color: const Color(0xFF0F766E).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.military_tech, color: Color(0xFF0F766E), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pangkat Keuangan: $title',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
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

  // Kartu Habit Harian & Streak Gamifikasi di Beranda
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

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isTodayCompleted ? const Color(0xFFF0FDF4) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isTodayCompleted ? const Color(0xFF86EFAC) : Colors.amber.shade200,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isTodayCompleted ? Colors.green : Colors.amber).withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Baris Atas: Icon, Judul Streak & Status
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isTodayCompleted ? Colors.green.shade100 : Colors.amber.shade100,
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
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F766E),
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
                        color: isTodayCompleted ? Colors.green.shade800 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (noSpendMonthCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield, size: 12, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        '$noSpendMonthCount hari hemat',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // Kalender 7 Hari Terakhir
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: isTodayCompleted ? Colors.white.withValues(alpha: 0.8) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: weekly.map((day) {
                final isToday = day.isToday;
                Color dotBg;
                Widget dotChild;

                if (day.hasTransaction) {
                  dotBg = Colors.amber.shade100;
                  dotChild = const Text('🔥', style: TextStyle(fontSize: 11));
                } else if (day.isNoSpend) {
                  dotBg = Colors.green.shade100;
                  dotChild = const Icon(Icons.shield, size: 12, color: Colors.green);
                } else if (isToday) {
                  dotBg = Colors.amber.shade50;
                  dotChild = const Text('⏳', style: TextStyle(fontSize: 10));
                } else {
                  dotBg = Colors.grey.shade200;
                  dotChild = Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
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
                            color: isToday ? const Color(0xFF0F766E) : Colors.grey.shade600,
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
                                ? Border.all(color: const Color(0xFF0F766E), width: 1.5)
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

          const SizedBox(height: 12),

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
                      padding: const EdgeInsets.symmetric(vertical: 11),
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
                      foregroundColor: const Color(0xFF0F766E),
                      side: const BorderSide(color: Color(0xFF0F766E)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
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
                Row(
                  children: [
                    Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'Terklaim No-Spend Day! 🛡️',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: _cancelNoSpendToday,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text(
                    'Eh, ada jajan tadi',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ),
              ],
            ),
          ],
        ],
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

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'CatatDuit',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Ekspor Laporan Bulanan',
            icon: const Icon(Icons.ios_share),
            onPressed: _showExportDialog,
          ),
          IconButton(
            tooltip: 'Atur Nama Pemilik',
            icon: Icon(
              Icons.account_circle,
              color: _userName != null ? Colors.teal.shade700 : Colors.grey.shade600,
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
              // Pengatur Bulan (Per Bulan)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _previousMonth,
                    ),
                    Row(
                      children: [
                        const Icon(Icons.calendar_month, size: 18, color: Color(0xFF0F766E)),
                        const SizedBox(width: 8),
                        Text(
                          currentMonthLabel,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _nextMonth,
                    ),
                  ],
                ),
              ),

              // Saldo Card Bulan Ini
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F766E), Color(0xFF115E59)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sisa Dana ($currentMonthLabel)',
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      currencyFormatter.format(_saldoBulanIni),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.arrow_downward, color: Colors.greenAccent, size: 16),
                                    SizedBox(width: 4),
                                    Text('Pemasukan', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  currencyFormatter.format(_totalPemasukanBulanIni),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.arrow_upward, color: Colors.redAccent, size: 16),
                                    SizedBox(width: 4),
                                    Text('Pengeluaran', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  currencyFormatter.format(_totalPengeluaranBulanIni),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Bar Aksi Cepat: Catat Cepat vs Pindai Bukti
              Container(
                margin: const EdgeInsets.only(top: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _showSmartQuickInputModal,
                        icon: const Icon(Icons.flash_on, color: Colors.white, size: 20),
                        label: const Text(
                          'Catat Cepat',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _showImageSourceDialog,
                        icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF0F766E), size: 20),
                        label: const Text(
                          'Pindai Bukti',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F766E)),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Color(0xFF0F766E), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Kartu Daily Habit & Streak Gamifikasi
              _buildDailyStreakCard(),

              // Distribusi Pengeluaran per Kategori
              _buildCategoryBreakdownCard(),

              const SizedBox(height: 20),

              // Header Riwayat Transaksi Bulan Ini
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Transaksi $currentMonthLabel',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${transactionsToShow.length} dari ${_monthlyTransactions.length}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Bar Pencarian & Filter
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Cari toko, keterangan, nominal...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                onChanged: (val) {
                  setState(() => _searchQuery = val.trim());
                },
              ),
              const SizedBox(height: 8),

              // Filter Chips (Semua, Masuk, Keluar)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Semua'),
                      selected: _selectedFilterFlow == 'ALL',
                      onSelected: (sel) {
                        if (sel) setState(() => _selectedFilterFlow = 'ALL');
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('🟢 Uang Masuk'),
                      selected: _selectedFilterFlow == 'PEMASUKAN',
                      onSelected: (sel) {
                        if (sel) setState(() => _selectedFilterFlow = 'PEMASUKAN');
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('🔴 Uang Keluar'),
                      selected: _selectedFilterFlow == 'PENGELUARAN',
                      onSelected: (sel) {
                        if (sel) setState(() => _selectedFilterFlow = 'PENGELUARAN');
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              if (transactionsToShow.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 54, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          _monthlyTransactions.isEmpty
                              ? 'Belum ada transaksi di bulan $currentMonthLabel'
                              : 'Tidak ada transaksi yang cocok dengan filter',
                          style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _monthlyTransactions.isEmpty
                              ? 'Catat manual atau pindai bukti transfer dari galeri'
                              : 'Coba ubah kata kunci pencarian atau filter arus',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                        ),
                        if (_monthlyTransactions.isEmpty) ...[
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _showImageSourceDialog,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Tambah Transaksi Pertama'),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                ...transactionsToShow.map((tx) {
                  final originalIndex = _allTransactions.indexOf(tx);
                  return _buildTransactionCard(tx, originalIndex);
                }),
            ],
          ),

          // Loading Overlay saat scanning lokal
          if (_isScanning)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'Sedang membaca bukti transfer...',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showImageSourceDialog,
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add),
        label: const Text(
          'Tambah Transaksi',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(TransactionModel tx, int originalIndex) {
    final isIncome = tx.flowType == 'PEMASUKAN';
    return Dismissible(
      key: Key('${tx.transactionDate}_${tx.referenceNumber}_$originalIndex'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade600,
          borderRadius: BorderRadius.circular(16),
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
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: ListTile(
          onTap: () => _showTransactionDetailDialog(tx, originalIndex),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: isIncome ? Colors.green.shade50 : Colors.red.shade50,
            child: Icon(
              isIncome ? Icons.arrow_downward : Icons.arrow_upward,
              color: isIncome ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),
          title: Text(
            tx.description?.isNotEmpty == true ? tx.description! : tx.recipientName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          subtitle: Text(
            '${tx.sourcePlatform} • ${tx.category}\n${tx.transactionDate} ${tx.transactionTime ?? ""}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          isThreeLine: true,
          trailing: Text(
            '${isIncome ? '+' : '-'}${currencyFormatter.format(tx.totalAmount)}',
            style: TextStyle(
              color: isIncome ? Colors.green.shade700 : Colors.red.shade700,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}
