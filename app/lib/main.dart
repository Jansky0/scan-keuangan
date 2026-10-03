import 'dart:async';
import 'package:flutter/material.dart';
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

  // Filter transaksi berdasarkan bulan yang dipilih
  List<TransactionModel> get _monthlyTransactions {
    final year = _selectedMonth.year.toString();
    final month = _selectedMonth.month.toString().padLeft(2, '0');
    final prefix = '$year-$month';

    return _allTransactions.where((t) => t.transactionDate.startsWith(prefix)).toList();
  }

  double get _totalPemasukanBulanIni => _monthlyTransactions
      .where((t) => t.flowType == 'PEMASUKAN')
      .fold(0.0, (acc, item) => acc + item.totalAmount);

  double get _totalPengeluaranBulanIni => _monthlyTransactions
      .where((t) => t.flowType == 'PENGELUARAN')
      .fold(0.0, (acc, item) => acc + item.totalAmount);

  double get _saldoBulanIni => _totalPemasukanBulanIni - _totalPengeluaranBulanIni;

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
            tooltip: 'Atur Nama Pemilik',
            icon: Icon(
              Icons.account_circle,
              color: _userName != null ? Colors.teal.shade700 : Colors.grey.shade600,
            ),
            onPressed: _showProfileDialog,
          ),
          IconButton(
            tooltip: 'Uji Coba Bukti ShopeePay',
            icon: const Icon(Icons.play_circle_fill, color: Colors.teal),
            onPressed: () {
              final sampleTx = ScannerService.getSampleShopeePayData();
              _showConfirmationDialog(sampleTx);
            },
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

              const SizedBox(height: 20),

              // Riwayat Transaksi Bulan Ini
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Transaksi $currentMonthLabel',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${_monthlyTransactions.length} transaksi',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_monthlyTransactions.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 54, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          'Belum ada transaksi di bulan $currentMonthLabel',
                          style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Share dari aplikasi bank atau pilih screenshot dari galeri',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _showImageSourceDialog,
                          icon: const Icon(Icons.add_photo_alternate, size: 18),
                          label: const Text('Pilih Screenshot dari Galeri'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ..._monthlyTransactions.asMap().entries.map((entry) {
                  final index = entry.key;
                  final tx = entry.value;
                  return _buildTransactionCard(tx, index);
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
        icon: const Icon(Icons.add_photo_alternate),
        label: const Text(
          'Pilih Screenshot / Foto',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(TransactionModel tx, int index) {
    final isIncome = tx.flowType == 'PEMASUKAN';
    return Dismissible(
      key: Key('${tx.transactionDate}_${tx.referenceNumber}_$index'),
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
        final originalIndex = _allTransactions.indexOf(tx);
        if (originalIndex != -1) {
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
