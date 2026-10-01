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
  String? _userBranchId;
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
          .select('role_id, branch_id')
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
        _userBranchId = userRes['branch_id']?.toString();
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
        'branch_id': _userBranchId,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status updated to $newStatus'), backgroundColor: Colors.green));
        _loadDetails();
      }
    } catch (e) {
      // The database explains refusals, e.g. "Only staff at the destination branch can ..."
      final message = e is PostgrestException ? e.message : '$e';
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
    }
  }

  /// Super Admins only: removes the parcel with its payments, receipts and tracking
  /// (supabase/delete_records.sql).
  Future<void> _deleteParcel() async {
    final booking = _parcel!['booking_number'];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $booking?'),
        content: const Text('Its payment, receipt and tracking history are deleted too, and it disappears from reports. '
            'For a real parcel that will not be sent, use Cancel instead.\n\nThis cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorText, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await Supabase.instance.client.rpc('delete_parcel', params: {'p_parcel_id': widget.parcelId});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$booking deleted'), backgroundColor: AppColors.successText));
      Navigator.pop(context, true);
    } catch (e) {
      final message = e is PostgrestException ? e.message : '$e';
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
    }
  }

  // Who may do what (also enforced in the database by supabase/parcel_rules.sql):
  // the sending branch dispatches or cancels; the destination branch receives and hands over.
  bool get _isSuperAdmin => _userRole == 'Super Admin';
  bool get _atOrigin => _isSuperAdmin || (_userBranchId != null && _userBranchId == _parcel!['origin_branch_id']?.toString());
  bool get _atDestination => _isSuperAdmin || (_userBranchId != null && _userBranchId == _parcel!['destination_branch_id']?.toString());
  bool get _isFinished => const ['PICKED', 'DELIVERED', 'CANCELLED'].contains(_parcel!['status']);

  bool get _canCancel =>
      _isSuperAdmin ? !_isFinished : _atOrigin && const ['BOOKED', 'RECEIVED'].contains(_parcel!['status']);

  static String _digits(String phone) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    return d.length > 9 ? d.substring(d.length - 9) : d; // 0712..., 712..., +254712... all match
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
              if (_digits(enteredPhone) == _digits(receiverPhone)) {
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
    final options = <String>[
      if (_atOrigin && (currentStatus == 'BOOKED' || currentStatus == 'RECEIVED')) 'DISPATCHED',
      if (_atDestination && (currentStatus == 'DISPATCHED' || currentStatus == 'IN_TRANSIT')) 'ARRIVED',
      if (_atDestination && currentStatus == 'ARRIVED') 'READY_FOR_COLLECTION',
      if (_canCancel) 'CANCELLED',
    ];

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
    return Scaffold(
      appBar: AppBar(
        title: Text(_parcel!['booking_number']),
        actions: [
          IconButton(
            icon: const Icon(Icons.update),
            onPressed: _showStatusOptions,
            tooltip: 'Update Status',
          ),
          if (_isSuperAdmin)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.errorText),
              onPressed: _deleteParcel,
              tooltip: 'Delete parcel',
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
                  color: AppColors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.orange),
                ),
                child: Text(currentStatus.replaceAll('_', ' '), style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 16),

            // ACTIONS for this branch (sending branch dispatches, destination branch receives)
            ..._actionButtons(currentStatus, origin?['name'], destination?['name']),
            const SizedBox(height: 16),

            // Route Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Route', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.orange)),
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
                    const Text('Parcel Info', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.orange)),
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

  List<Widget> _actionButtons(String status, String? originName, String? destinationName) {
    Widget button(String label, IconData icon, Color color, VoidCallback onPressed) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label),
              style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ),
        );

    final buttons = <Widget>[
      if (_atOrigin && (status == 'BOOKED' || status == 'RECEIVED'))
        button('Dispatch Parcel', Icons.local_shipping, AppColors.orange, () => _updateStatus('DISPATCHED')),
      if (_atDestination && (status == 'DISPATCHED' || status == 'IN_TRANSIT'))
        button('Confirm Parcel Arrived', Icons.check_circle, AppColors.orange, () => _updateStatus('ARRIVED')),
      if (_atDestination && status == 'ARRIVED')
        button('Mark Ready for Collection', Icons.inventory, Colors.teal, () => _updateStatus('READY_FOR_COLLECTION')),
      if (_atDestination && (status == 'ARRIVED' || status == 'READY_FOR_COLLECTION'))
        button('Verify Receiver & Hand Over', Icons.phone_android, Colors.green, _verifyAndMarkPicked),
    ];
    if (buttons.isNotEmpty) return buttons;

    // Explain why there is nothing to do here
    String? note;
    if (const ['DISPATCHED', 'IN_TRANSIT', 'ARRIVED', 'READY_FOR_COLLECTION'].contains(status)) {
      note = 'Only ${destinationName ?? 'destination'} branch staff can receive and hand over this parcel.';
    } else if (status == 'BOOKED' || status == 'RECEIVED') {
      note = 'Waiting for ${originName ?? 'the sending branch'} to dispatch this parcel.';
    }
    if (note == null) return [];
    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(note, style: const TextStyle(color: AppColors.muted))),
        ]),
      ),
    ];
  }

  Widget _buildInfoCard(String title, String? name, String? phone) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.orange, fontSize: 12)),
            const SizedBox(height: 4),
            Text(name ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(phone ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}