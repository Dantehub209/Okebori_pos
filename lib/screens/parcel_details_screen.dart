import 'package:flutter/material.dart';
import '../theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class ParcelDetailsScreen extends StatefulWidget {
  final String parcelId;

  const ParcelDetailsScreen({super.key, required this.parcelId});

  @override
  State<ParcelDetailsScreen> createState() => _ParcelDetailsScreenState();
}

class _ParcelDetailsScreenState extends State<ParcelDetailsScreen> {
  Map<String, dynamic>? _parcel;
  List<Map<String, dynamic>> _history = [];
  String _userRole = 'Cashier';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;

      // Fetch user role
      final userRes = await supabase
          .from('users')
          .select('role_id')
          .eq('id', userId)
          .single();

      String roleName = 'Cashier';
      if (userRes['role_id'] != null) {
        final roleRes = await supabase
            .from('roles')
            .select('name')
            .eq('id', userRes['role_id'])
            .single();
        roleName = roleRes['name'] ?? 'Cashier';
      }

      // Fetch Parcel Details
      final parcelRes = await supabase
          .from('parcels')
          .select('*, sender:customers!sender_id(name, phone), receiver:customers!receiver_id(name, phone), origin:branches!origin_branch_id(name), destination:branches!destination_branch_id(name), category:parcel_categories(name)')
          .eq('id', widget.parcelId)
          .single();

      // Fetch Status History
      final historyRes = await supabase
          .from('parcel_status_history')
          .select('*, branches(name), users(name)')
          .eq('parcel_id', widget.parcelId)
          .order('created_at', ascending: false);

      setState(() {
        _parcel = parcelRes;
        _history = List<Map<String, dynamic>>.from(historyRes);
        _userRole = roleName;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;
      
      await supabase.from('parcels').update({'status': newStatus}).eq('id', widget.parcelId);

      await supabase.from('parcel_status_history').insert({
        'parcel_id': widget.parcelId,
        'status': newStatus,
        'user_id': userId,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status updated to $newStatus'), backgroundColor: Colors.green));
        _loadDetails();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update Error: $e')));
    }
  }

  // NEW: Verify receiver phone and mark as picked
  Future<void> _verifyAndMarkPicked() async {
    final phoneController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verify Receiver'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please enter the receiver\'s phone number for verification:', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'Receiver Phone Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final enteredPhone = phoneController.text.trim();
              final receiverPhone = _parcel!['receiver']?['phone'] ?? '';
              
              if (enteredPhone.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a phone number'), backgroundColor: Colors.orange),
                );
                return;
              }

              // Verify phone matches
              if (enteredPhone == receiverPhone) {
                Navigator.pop(context);
                await _updateStatus('PICKED');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Parcel marked as PICKED!'), backgroundColor: Colors.green),
                  );
                }
              } else {
                Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Phone number does not match! Cannot mark as picked.'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 4),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('Verify & Mark Picked'),
          ),
        ],
      ),
    );
  }

  void _showStatusOptions() {
    final currentStatus = _parcel!['status'];
    final isBranchManager = _userRole == 'Branch Manager' || _userRole == 'Super Admin';
    
    // Define available statuses based on role and current status
    List<String> options = [];
    
    if (isBranchManager) {
      // Branch Manager can confirm received parcels
      if (currentStatus == 'IN_TRANSIT' || currentStatus == 'DISPATCHED') {
        options.add('ARRIVED');
      }
      if (currentStatus == 'ARRIVED') {
        options.add('READY_FOR_COLLECTION');
      }
    }
    
    // All roles can mark as picked if ready
    if (currentStatus == 'READY_FOR_COLLECTION') {
      // Don't add to options, we'll handle it separately with phone verification
    }
    
    // Add other standard options
    if (currentStatus == 'BOOKED') {
      options.add('RECEIVED');
    }
    if (!options.contains('CANCELLED') && currentStatus != 'DELIVERED' && currentStatus != 'PICKED') {
      options.add('CANCELLED');
    }

    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No status updates available'), backgroundColor: Colors.orange),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Update Parcel Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            ...options.map((status) => ListTile(
              title: Text(status.replaceAll('_', ' ')),
              onTap: () {
                Navigator.pop(context);
                _updateStatus(status);
              },
            )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_parcel == null) return const Scaffold(body: Center(child: Text('Parcel not found')));

    final sender = _parcel!['sender'] as Map<String, dynamic>?;
    final receiver = _parcel!['receiver'] as Map<String, dynamic>?;
    final origin = _parcel!['origin'] as Map<String, dynamic>?;
    final destination = _parcel!['destination'] as Map<String, dynamic>?;
    final category = _parcel!['category'] as Map<String, dynamic>?;
    final currentStatus = _parcel!['status'];
    final isBranchManager = _userRole == 'Branch Manager' || _userRole == 'Super Admin';

    return Scaffold(
      appBar: AppBar(
        title: Text(_parcel!['booking_number']),
        actions: [
          IconButton(
            icon: const Icon(Icons.update),
            onPressed: _showStatusOptions,
            tooltip: 'Update Status',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Badge
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.navy.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.navy),
                ),
                child: Text(currentStatus.replaceAll('_', ' '), style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 16),

            // BRANCH MANAGER ACTIONS
            if (isBranchManager) ...[
              if (currentStatus == 'IN_TRANSIT' || currentStatus == 'DISPATCHED')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _updateStatus('ARRIVED'),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Confirm Parcel Arrived'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
              if (currentStatus == 'ARRIVED')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _updateStatus('READY_FOR_COLLECTION'),
                    icon: const Icon(Icons.inventory),
                    label: const Text('Mark Ready for Collection'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
              if (currentStatus == 'READY_FOR_COLLECTION')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _verifyAndMarkPicked,
                    icon: const Icon(Icons.phone_android),
                    label: const Text('Verify Receiver & Mark Picked'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
              const SizedBox(height: 16),
            ],

            // Route Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Route', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy)),
                    const SizedBox(height: 8),
                    Row(children: [const Icon(Icons.location_on, size: 16), const SizedBox(width: 8), Text('From: ${origin?['name'] ?? 'N/A'}')]),
                    const SizedBox(height: 8),
                    Row(children: [const Icon(Icons.flag, size: 16), const SizedBox(width: 8), Text('To: ${destination?['name'] ?? 'N/A'}')]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Sender & Receiver
            Row(
              children: [
                Expanded(child: _buildInfoCard('Sender', sender?['name'], sender?['phone'])),
                const SizedBox(width: 16),
                Expanded(child: _buildInfoCard('Receiver', receiver?['name'], receiver?['phone'])),
              ],
            ),
            const SizedBox(height: 16),

            // Parcel Details
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Parcel Info', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy)),
                    const SizedBox(height: 8),
                    Text('Category: ${category?['name'] ?? 'N/A'}'),
                    Text('Weight: ${_parcel!['weight_kg']} kg'),
                    Text('Charge: KES ${_parcel!['shipping_charge']}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Tracking History
            const Text('Tracking History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ..._history.map((item) {
              final date = DateTime.parse(item['created_at']);
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['status'].replaceAll('_', ' '), style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(DateFormat('MMM dd, yyyy - hh:mm a').format(date), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, String? name, String? phone) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy, fontSize: 12)),
            const SizedBox(height: 4),
            Text(name ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(phone ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}