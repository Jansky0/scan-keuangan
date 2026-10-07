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
    if (mounted) {
      setState(() {
        _allTransactions = list;
        _userName = name;
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
                  child: const Icon(Icons.edit_note, color: Color(0xFFB45309)),
                ),
                title: const Text('Catat Manual (Tunai / Kasir)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Catat transaksi tunai/kas tanpa bukti struk fisik', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  Navigator.pop(ctx);
                  _showManualInputDialog();
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
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }
                          if (mounted) {
                            setState(() {
                              _allTransactions = updated;
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

  // Modal Input Transaksi Manual (Kas / Tunai)
  void _showManualInputDialog() {
    String flowType = 'PENGELUARAN';
    String category = 'Makanan & Minuman';
    String platform = 'Tunai / Cash';
    DateTime selectedDate = DateTime.now();

    final nominalController = TextEditingController();
    final descController = TextEditingController();

    final categories = [
      'Makanan & Minuman',
      'Belanja',
      'Transportasi',
      'Tagihan & Utilitas',
      'Transfer / Patungan',
      'Hiburan',
      'Gaji / Pendapatan',
      'Lainnya',
    ];

    final platforms = [
      'Tunai / Cash',
      'BCA',
      'Livin\' Mandiri',
      'BRImo',
      'BNI',
      'DANA',
      'GoPay',
      'ShopeePay',
      'QRIS',
      'Lainnya',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final isIncome = flowType == 'PEMASUKAN';
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
                      'Catat Transaksi Manual',
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
                                flowType = 'PEMASUKAN';
                                if (category == 'Makanan & Minuman') {
                                  category = 'Gaji / Pendapatan';
                                }
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
                                flowType = 'PENGELUARAN';
                                if (category == 'Gaji / Pendapatan') {
                                  category = 'Makanan & Minuman';
                                }
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

                    // Input Nominal
                    TextField(
                      controller: nominalController,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        prefixText: 'Rp ',
                        labelText: 'Nominal Transaksi',
                        hintText: '0',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Input Keterangan / Toko
                    TextField(
                      controller: descController,
                      decoration: InputDecoration(
                        labelText: 'Keterangan / Nama Toko',
                        hintText: isIncome ? 'Contoh: Gaji, Bonus, dll' : 'Contoh: Warteg, Kopi, Bensin, dll',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Row: Kategori & Metode
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: category,
                            decoration: InputDecoration(
                              labelText: 'Kategori',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            items: categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat, style: const TextStyle(fontSize: 13)))).toList(),
                            onChanged: (val) {
                              if (val != null) setModalState(() => category = val);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: platform,
                            decoration: InputDecoration(
                              labelText: 'Metode',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            items: platforms.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 13)))).toList(),
                            onChanged: (val) {
                              if (val != null) setModalState(() => platform = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Pilihan Tanggal Transaksi
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setModalState(() => selectedDate = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 18, color: Color(0xFF0F766E)),
                                const SizedBox(width: 10),
                                Text(
                                  'Tanggal: ${DateFormat('yyyy-MM-dd').format(selectedDate)}',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                              ],
                            ),
                            const Text('Ganti', style: TextStyle(color: Color(0xFF0F766E), fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Tombol Simpan
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final cleaned = nominalController.text.replaceAll(RegExp(r'[^0-9]'), '');
                          final amount = double.tryParse(cleaned);
                          if (amount == null || amount <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Harap masukkan nominal yang valid!')),
                            );
                            return;
                          }

                          final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
                          final timeStr = DateFormat('HH:mm').format(DateTime.now());
                          final desc = descController.text.trim();

                          final newTx = TransactionModel(
                            status: 'SUCCESS',
                            flowType: flowType,
                            sourcePlatform: platform,
                            transactionType: flowType == 'PEMASUKAN' ? 'Uang Masuk' : 'Pembelian / Pengeluaran',
                            amount: amount,
                            adminFee: 0,
                            totalAmount: amount,
                            senderName: flowType == 'PEMASUKAN' ? (desc.isNotEmpty ? desc : 'Pendapatan Lain') : _userName,
                            recipientName: flowType == 'PENGELUARAN' ? (desc.isNotEmpty ? desc : 'Pengeluaran Tunai') : (_userName ?? 'Saya'),
                            destinationBankOrWallet: platform,
                            transactionDate: dateStr,
                            transactionTime: timeStr,
                            description: desc.isNotEmpty ? desc : null,
                            category: category,
                          );

                          final updated = await StorageService.addTransaction(newTx);
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            setState(() {
                              _allTransactions = updated;
                              _selectedMonth = DateTime(selectedDate.year, selectedDate.month);
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Transaksi ${currencyFormatter.format(amount)} berhasil dicatat!'),
                                backgroundColor: Colors.green.shade800,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Simpan Transaksi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
