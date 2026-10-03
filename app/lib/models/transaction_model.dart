class TransactionModel {
  final String status;
  final String flowType; // 'PEMASUKAN' atau 'PENGELUARAN'
  final String sourcePlatform;
  final String transactionType;
  final double amount;
  final double adminFee;
  final double totalAmount;
  final String? senderName;
  final String recipientName;
  final String? destinationBankOrWallet;
  final String? destinationAccount;
  final String transactionDate;
  final String? transactionTime;
  final String? referenceNumber;
  final String? description;
  final String category;

  TransactionModel({
    required this.status,
    required this.flowType,
    required this.sourcePlatform,
    required this.transactionType,
    required this.amount,
    this.adminFee = 0.0,
    required this.totalAmount,
    this.senderName,
    required this.recipientName,
    this.destinationBankOrWallet,
    this.destinationAccount,
    required this.transactionDate,
    this.transactionTime,
    this.referenceNumber,
    this.description,
    required this.category,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      status: json['status'] ?? 'BERHASIL',
      flowType: json['flow_type'] ?? 'PENGELUARAN',
      sourcePlatform: json['source_platform'] ?? 'Bank/E-Wallet',
      transactionType: json['transaction_type'] ?? 'TRANSFER_BANK',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      adminFee: (json['admin_fee'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      senderName: json['sender_name'],
      recipientName: json['recipient_name'] ?? 'Penerima',
      destinationBankOrWallet: json['destination_bank_or_wallet'],
      destinationAccount: json['destination_account'],
      transactionDate: json['transaction_date'] ?? DateTime.now().toIso8601String().substring(0, 10),
      transactionTime: json['transaction_time'],
      referenceNumber: json['reference_number'],
      description: json['description'],
      category: json['category'] ?? 'Lainnya',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'flow_type': flowType,
      'source_platform': sourcePlatform,
      'transaction_type': transactionType,
      'amount': amount,
      'admin_fee': adminFee,
      'total_amount': totalAmount,
      'sender_name': senderName,
      'recipient_name': recipientName,
      'destination_bank_or_wallet': destinationBankOrWallet,
      'destination_account': destinationAccount,
      'transaction_date': transactionDate,
      'transaction_time': transactionTime,
      'reference_number': referenceNumber,
      'description': description,
      'category': category,
    };
  }
}
