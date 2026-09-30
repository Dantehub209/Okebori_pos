import 'package:flutter/material.dart';
import '../theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class BranchReportsScreen extends StatefulWidget {
  final String? branchId; // Null for Super Admin (shows all branches)
  final String reportTitle;

  const BranchReportsScreen({
    super.key, 
    required this.branchId, 
    required this.reportTitle,
  });

  @override
  State<BranchReportsScreen> createState() => _BranchReportsScreenState();
}

class _BranchReportsScreenState extends State<BranchReportsScreen> {
  bool _isLoading = true;
  double _totalRevenue = 0.0;
  double _cashRevenue = 0.0;
  double _mpesaRevenue = 0.0;
  int _totalParcels = 0;

  @override
  void initState() {
    super.initState();
    _loadDailyReport();
  }

  Future<void> _loadDailyReport() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      
      // Get today's date range
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59).toIso8601String();

      // Build the query
      var query = supabase
          .from('payments')
          .select('amount, payment_method, parcel_id')
          .eq('status', 'COMPLETED')
          .gte('paid_at', startOfDay)
          .lte('paid_at', endOfDay);

      // If it's a Branch Manager, filter by their branch. If Super Admin, get all.
      if (widget.branchId != null) {
        query = query.eq('branch_id', widget.branchId!); // <-- FIXED: Added '!'
      }

      final response = await query;
      final List<Map<String, dynamic>> payments = List<Map<String, dynamic>>.from(response);

      double total = 0.0;
      double cash = 0.0;
      double mpesa = 0.0;
      Set<String> uniqueParcels = {};

      for (var pay in payments) {
        final amount = (pay['amount'] as num).toDouble();
        final method = pay['payment_method'] as String;
        final parcelId = pay['parcel_id'] as String;

        total += amount;
        uniqueParcels.add(parcelId);

        if (method == 'CASH') {
          cash += amount;
        } else if (method == 'MPESA') {
          mpesa += amount;
        }
      }

      setState(() {
        _totalRevenue = total;
        _cashRevenue = cash;
        _mpesaRevenue = mpesa;
        _totalParcels = uniqueParcels.length;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading report: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(symbol: 'KES ', decimalDigits: 2);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.reportTitle),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDailyReport,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Daily Collections - ${DateFormat('EEEE, MMM d, yyyy').format(DateTime.now())}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy),
                    ),
                    const SizedBox(height: 24),

                    if (_totalParcels == 0)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Text(
                            'No payments recorded today.\nPull down to refresh.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        ),
                      )
                    else ...[
                      // Total Revenue Card
                      Card(
                        color: Colors.green.shade50,
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Total Revenue Today', style: TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 8),
                              Text(
                                currencyFormat.format(_totalRevenue),
                                style: const TextStyle(color: Colors.green, fontSize: 32, fontWeight: FontWeight.bold),
                              ),
                              const Divider(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('${_totalParcels} Parcels Processed', style: const TextStyle(color: Colors.grey)),
                                  const Icon(Icons.analytics, color: Colors.green),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Payment Methods Breakdown
                      const Text('Payment Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(children: [Icon(Icons.money, color: Colors.blue), SizedBox(width: 8), Text('Cash', style: TextStyle(fontWeight: FontWeight.bold))]),
                                    const SizedBox(height: 12),
                                    Text(currencyFormat.format(_cashRevenue), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(children: [Icon(Icons.phone_android, color: Colors.green), SizedBox(width: 8), Text('M-Pesa', style: TextStyle(fontWeight: FontWeight.bold))]),
                                    const SizedBox(height: 12),
                                    Text(currencyFormat.format(_mpesaRevenue), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}