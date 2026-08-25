import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/receipt_service.dart';

class PaymentScreen extends StatefulWidget {
  final String parcelId;
  final String bookingNumber;
  final double amount;
  final String senderName;
  final String senderPhone;
  final String receiverPhone;
  final String receiverName;
  final String destination;
  final double weight;

  const PaymentScreen({
    super.key,
    required this.parcelId,
    required this.bookingNumber,
    required this.amount,
    required this.senderPhone,
    required this.receiverPhone,
    required this.senderName,
    required this.receiverName,
    required this.destination,
    required this.weight,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String _selectedMethod = 'CASH';
  final _mpesaCodeController = TextEditingController();
  bool _isLoading = false;
  bool _isPrinting = false;

  @override
  void dispose() {
    _mpesaCodeController.dispose();
    super.dispose();
  }

  Future<void> _processPayment() async {
    if (_selectedMethod == 'MPESA' && _mpesaCodeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the M-Pesa Transaction Code'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;
      
      // Fetch the logged-in cashier's name for the receipt
      String cashierName = "System";
      try {
        final userRes = await supabase.from('users').select('name').eq('id', userId).single();
        cashierName = userRes['name'] ?? "System";
      } catch (e) {
        print("Could not fetch cashier name: $e");
      }
      
      // 1. Fetch Business and Branch IDs (use limit to avoid multiple results)
      final business = await supabase.from('businesses').select('id').limit(1).single();
      final businessId = business['id'];
      
      // Get the current user's branch
      final userBranch = await supabase
          .from('users')
          .select('branch_id')
          .eq('id', userId)
          .single();
      final branchId = userBranch['branch_id'];

      // 2. Insert Payment
      final paymentData = {
        'parcel_id': widget.parcelId,
        'business_id': businessId,
        'branch_id': branchId,
        'amount': widget.amount,
        'payment_method': _selectedMethod,
        'mpesa_transaction_code': _selectedMethod == 'MPESA' ? _mpesaCodeController.text.trim() : null,
        'status': 'COMPLETED',
        'received_by': userId,
        'paid_at': DateTime.now().toIso8601String(),
      };

      final paymentRes = await supabase.from('payments').insert(paymentData).select().single();
      final paymentId = paymentRes['id'];

      // 3. Insert Receipt (Trigger will auto-generate receipt_number)
      final receiptData = {
        'business_id': businessId,
        'branch_id': branchId,
        'parcel_id': widget.parcelId,
        'payment_id': paymentId,
        'issued_by': userId,
        'issued_at': DateTime.now().toIso8601String(),
      };

      final receiptRes = await supabase.from('receipts').insert(receiptData).select().single();
      final receiptNumber = receiptRes['receipt_number'];

      setState(() => _isLoading = false);

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Payment Successful!', style: TextStyle(color: Colors.green)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.receipt_long, size: 48, color: Colors.green),
                const SizedBox(height: 16),
                Text('Booking: ${widget.bookingNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Amount Paid: KES ${widget.amount.toStringAsFixed(2)}'),
                const Divider(),
                Text('Receipt No: $receiptNumber', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: const Text('Skip Printing'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.of(dialogContext).pop(); 
                  
                  if (mounted) setState(() => _isPrinting = true);

                  try {
                    bool printSuccess = false;

                    if (Platform.isWindows) {
                      print("Running on Windows: Simulating print...");
                      await Future.delayed(const Duration(seconds: 2));
                      printSuccess = true;
                    } else {
                      const String printerMacAddress = "00:11:22:33:44:55"; 
                      
                      printSuccess = await ReceiptService.printReceipt(
                        macAddress: printerMacAddress,
                        bookingNumber: widget.bookingNumber,
                        receiptNumber: receiptNumber,
                        senderName: widget.senderName,
                        receiverName: widget.receiverName,
                        destination: widget.destination,
                        weight: widget.weight,
                        amount: widget.amount,
                        paymentMethod: _selectedMethod,
                        cashierName: cashierName,
                      );
                    }

                    if (mounted) {
                      if (printSuccess) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Receipt Printed Successfully!'), backgroundColor: Colors.green)
                        );
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Printing Failed. Check Printer.'), backgroundColor: Colors.red)
                        );
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Print Error: $e'), backgroundColor: Colors.red)
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _isPrinting = false);
                  }
                },
                icon: const Icon(Icons.print),
                label: const Text('Print Receipt'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isPrinting) {
      return Stack(
        children: [
          _buildBody(),
          Container(
            color: Colors.black54,
            child: const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Printing Receipt...', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return _buildBody();
  }

  Widget _buildBody() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Process Payment'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: Colors.indigo.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Booking Details', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                    const SizedBox(height: 8),
                    Text('Booking No: ${widget.bookingNumber}', style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    Text('Total Amount: KES ${widget.amount.toStringAsFixed(2)}', 
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Payment Method', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedMethod,
              decoration: const InputDecoration(labelText: 'Select Method', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                DropdownMenuItem(value: 'MPESA', child: Text('M-Pesa')),
                DropdownMenuItem(value: 'CARD', child: Text('Card')),
              ],
              onChanged: (val) => setState(() => _selectedMethod = val!),
            ),
            
            if (_selectedMethod == 'MPESA') ...[
              const SizedBox(height: 16),
              TextField(
                controller: _mpesaCodeController,
                decoration: const InputDecoration(
                  labelText: 'M-Pesa Transaction Code (e.g., QWE123456)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone_android),
                ),
              ),
            ],

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading || _isPrinting ? null : _processPayment,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white) 
                    : const Text('Confirm Payment', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}