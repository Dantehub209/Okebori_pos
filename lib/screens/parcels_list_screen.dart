import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'parcel_details_screen.dart';

class ParcelsListScreen extends StatefulWidget {
  const ParcelsListScreen({super.key});

  @override
  State<ParcelsListScreen> createState() => _ParcelsListScreenState();
}

class _ParcelsListScreenState extends State<ParcelsListScreen> {
  List<Map<String, dynamic>> _allParcels = [];
  List<Map<String, dynamic>> _filteredParcels = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchParcels();
    // Listen to search bar changes
    _searchController.addListener(() {
      _filterParcels(_searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchParcels() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('parcels')
          .select('id, booking_number, status, shipping_charge, created_at, weight_kg, customers!sender_id(name, phone)')
          .order('created_at', ascending: false);

      setState(() {
        _allParcels = List<Map<String, dynamic>>.from(response);
        _filteredParcels = _allParcels; // Initially show all
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // Local filtering for instant search results
  void _filterParcels(String query) {
    if (query.isEmpty) {
      setState(() => _filteredParcels = _allParcels);
      return;
    }
    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredParcels = _allParcels.where((parcel) {
        final bookingNum = (parcel['booking_number'] ?? '').toString().toLowerCase();
        final senderPhone = (parcel['customers']?['phone'] ?? '').toString().toLowerCase();
        final senderName = (parcel['customers']?['name'] ?? '').toString().toLowerCase();
        
        return bookingNum.contains(lowerQuery) || 
               senderPhone.contains(lowerQuery) || 
               senderName.contains(lowerQuery);
      }).toList();
    });
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'BOOKED': return Colors.blue;
      case 'RECEIVED': return Colors.orange;
      case 'DISPATCHED': return Colors.purple;
      case 'IN_TRANSIT': return Colors.purple;
      case 'ARRIVED': return Colors.teal;
      case 'READY_FOR_COLLECTION': return Colors.teal;
      case 'DELIVERED': case 'PICKED': return Colors.green;
      case 'CANCELLED': return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parcels Dashboard'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // --- SEARCH BAR ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search Booking No, Name, or Phone...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty 
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchController.clear()) 
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[100],
              ),
            ),
          ),
          
          // --- LIST ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _fetchParcels,
                    child: _filteredParcels.isEmpty
                        ? const Center(child: Text('No parcels found.'))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _filteredParcels.length,
                            itemBuilder: (context, index) {
                              final parcel = _filteredParcels[index];
                              final sender = parcel['customers'] as Map<String, dynamic>?;
                              final status = parcel['status'] as String;
                              final date = DateTime.parse(parcel['created_at']);
                              
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(16),
                                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ParcelDetailsScreen(parcelId: parcel['id']))),
                                  leading: CircleAvatar(
                                    backgroundColor: _getStatusColor(status).withOpacity(0.2),
                                    child: Icon(Icons.inventory_2, color: _getStatusColor(status)),
                                  ),
                                  title: Text(parcel['booking_number'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text('Sender: ${sender?['name'] ?? 'N/A'} (${sender?['phone'] ?? ''})'),
                                      const SizedBox(height: 4),
                                      Text('Weight: ${parcel['weight_kg']} kg | Charge: KES ${parcel['shipping_charge']}'),
                                      const SizedBox(height: 4),
                                      Text(DateFormat('MMM dd, yyyy - hh:mm a').format(date), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    ],
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(status).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: _getStatusColor(status)),
                                    ),
                                    child: Text(status.replaceAll('_', ' '), style: TextStyle(color: _getStatusColor(status), fontWeight: FontWeight.bold, fontSize: 12)),
                                  ),
                                  isThreeLine: true,
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}