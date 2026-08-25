import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math'; // For math calculations (Haversine formula)
import 'payment_screen.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = true;

  // Controllers
  final _senderName = TextEditingController();
  final _senderPhone = TextEditingController();
  final _senderEmail = TextEditingController();
  final _receiverName = TextEditingController();
  final _receiverPhone = TextEditingController();
  final _receiverEmail = TextEditingController();
  final _weight = TextEditingController();

  String? _originId;
  String? _destId;
  String? _categoryId;

  // Dynamic Pricing Variables
  double _basePrice = 150.0;
  double _baseWeight = 5.0;
  double _extraKgPrice = 50.0;
  double _fuelCostPerKm = 30.0;
  bool _rulesLoaded = false;
  
  double _calculatedPrice = 0.0;
  double _distanceKm = 0.0;

  @override
  void initState() {
    super.initState();
    _loadData(); // Loads branches and categories
    _loadPricingRules(); // Loads dynamic pricing
  }

  @override
  void dispose() {
    _senderName.dispose(); _senderPhone.dispose(); _senderEmail.dispose();
    _receiverName.dispose(); _receiverPhone.dispose(); _receiverEmail.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final supabase = Supabase.instance.client;
      final branches = await supabase.from('branches').select('id, name, latitude, longitude').eq('status', 'active');
      final categories = await supabase.from('parcel_categories').select('id, name').eq('status', 'active');
      
      setState(() {
        _branches = List<Map<String, dynamic>>.from(branches);
        _categories = List<Map<String, dynamic>>.from(categories);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
    }
  }

  Future<void> _loadPricingRules() async {
    try {
      final supabase = Supabase.instance.client;
      final businessId = (await supabase.from('businesses').select('id').limit(1).single())['id'];
      
      final response = await supabase
          .from('pricing_rules')
          .select('*')
          .eq('business_id', businessId)
          .maybeSingle();

      if (response != null) {
        setState(() {
          _basePrice = (response['base_price'] as num).toDouble();
          _baseWeight = (response['base_weight_kg'] as num).toDouble();
          _extraKgPrice = (response['price_per_extra_kg'] as num).toDouble();
          _fuelCostPerKm = (response['fuel_cost_per_km'] as num).toDouble();
          _rulesLoaded = true;
        });
      } else {
        setState(() => _rulesLoaded = true); // Fallback to defaults if no rule exists
      }
    } catch (e) {
      print("Error loading pricing rules: $e");
      setState(() => _rulesLoaded = true); // Fallback to defaults
    }
  }

  // --- Haversine Formula to calculate distance between two GPS points ---
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295; // Pi/180
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // Earth radius approx 6371km * 2
  }

  // --- Calculate Price Logic ---
  Future<void> _calculateAndBook() async {
    // 1. Validation
    if (_originId == null || _destId == null || _categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select Origin, Destination, and Category'), backgroundColor: Colors.orange));
      return;
    }
    if (_senderName.text.isEmpty || _senderPhone.text.isEmpty || _receiverName.text.isEmpty || _receiverPhone.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sender and Receiver names/phones are required'), backgroundColor: Colors.orange));
      return;
    }
    if (_weight.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Weight is required'), backgroundColor: Colors.orange));
      return;
    }

    if (!_rulesLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Loading pricing rules, please wait a moment'), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 2. Get Branch Coordinates
      final originBranch = _branches.firstWhere((b) => b['id'] == _originId);
      final destBranch = _branches.firstWhere((b) => b['id'] == _destId);

      final lat1 = (originBranch['latitude'] as num?)?.toDouble() ?? 0.0;
      final lon1 = (originBranch['longitude'] as num?)?.toDouble() ?? 0.0;
      final lat2 = (destBranch['latitude'] as num?)?.toDouble() ?? 0.0;
      final lon2 = (destBranch['longitude'] as num?)?.toDouble() ?? 0.0;

      // 3. Calculate Distance
      _distanceKm = _calculateDistance(lat1, lon1, lat2, lon2);

      // 4. Calculate Cost using the DYNAMIC state variables
      final weight = double.parse(_weight.text);

      double weightCost = 0;
      if (weight <= _baseWeight) {
        weightCost = _basePrice;
      } else {
        double extraWeight = weight - _baseWeight;
        weightCost = _basePrice + (extraWeight * _extraKgPrice);
      }

      double distanceCost = _distanceKm * _fuelCostPerKm;
      _calculatedPrice = weightCost + distanceCost;

      setState(() => _isLoading = false);

      // 5. Show Confirmation Dialog
      _showConfirmationDialog();

    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Calculation Error: $e')));
    }
  }

  void _showConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Booking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Distance: ${_distanceKm.toStringAsFixed(2)} km'),
            Text('Weight: ${_weight.text} kg'),
            const Divider(),
            Text('Total Shipping Charge: KES ${_calculatedPrice.toStringAsFixed(2)}', 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _saveBooking();
            },
            child: const Text('Confirm & Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveBooking() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;
      final businessId = (await supabase.from('businesses').select('id').limit(1).single())['id'];

      // 1. Save or Find Sender Customer
      String? senderId = await _getOrCreateCustomer(_senderName.text, _senderPhone.text, _senderEmail.text, businessId);

      // 2. Save or Find Receiver Customer
      String? receiverId = await _getOrCreateCustomer(_receiverName.text, _receiverPhone.text, _receiverEmail.text, businessId);

      // 3. Create Parcel
      final parcelData = {
        'business_id': businessId,
        'sender_id': senderId,
        'receiver_id': receiverId,
        'origin_branch_id': _originId,
        'destination_branch_id': _destId,
        'category_id': _categoryId,
        'weight_kg': double.parse(_weight.text),
        'declared_value': 0.0,
        'is_fragile': false,
        'shipping_charge': _calculatedPrice,
        'distance_km': _distanceKm,
        'status': 'BOOKED',
        'booked_by': userId,
      };

      final parcelRes = await supabase.from('parcels').insert(parcelData).select().single();
      
      setState(() => _isLoading = false);

      // 4. Navigate to Payment Screen
      if (mounted) {
        final destBranch = _branches.firstWhere((b) => b['id'] == _destId);
        
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => PaymentScreen(
              parcelId: parcelRes['id'],
              bookingNumber: parcelRes['booking_number'],
              amount: _calculatedPrice,
              senderName: _senderName.text,
              receiverName: _receiverName.text,
              destination: destBranch['name'],
              weight: double.parse(_weight.text),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save Error: $e')));
    }
  }

  // Helper to avoid duplicate customers
  Future<String> _getOrCreateCustomer(String name, String phone, String? email, String businessId) async {
    final supabase = Supabase.instance.client;
    
    // Try to find existing customer by phone
    final existing = await supabase.from('customers').select('id').eq('phone', phone).maybeSingle();
    
    if (existing != null) {
      return existing['id'];
    }

    // Create new
    final newCustomer = await supabase.from('customers').insert({
      'business_id': businessId,
      'name': name,
      'phone': phone,
      'email': email,
    }).select().single();

    return newCustomer['id'];
  }

  // --- UI BUILDERS ---
  Widget _buildSection(String title, IconData icon, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, color: Colors.indigo, size: 20), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo))]),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('New Booking'), backgroundColor: Colors.indigo, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildSection('Route Information', Icons.route, [
              DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: 'Origin Branch *'), value: _originId, items: _branches.map((b) => DropdownMenuItem(value: b['id'].toString(), child: Text(b['name']))).toList(), onChanged: (v) => setState(() => _originId = v)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: 'Destination Branch *'), value: _destId, items: _branches.map((b) => DropdownMenuItem(value: b['id'].toString(), child: Text(b['name']))).toList(), onChanged: (v) => setState(() => _destId = v)),
            ]),
            _buildSection('Sender Details', Icons.person_outline, [
              TextField(controller: _senderName, decoration: const InputDecoration(labelText: 'Full Name *', prefixIcon: Icon(Icons.person))),
              const SizedBox(height: 16),
              TextField(controller: _senderPhone, decoration: const InputDecoration(labelText: 'Phone Number *', prefixIcon: Icon(Icons.phone)), keyboardType: TextInputType.phone),
              const SizedBox(height: 16),
              TextField(controller: _senderEmail, decoration: const InputDecoration(labelText: 'Email (Optional)', prefixIcon: Icon(Icons.email_outlined)), keyboardType: TextInputType.emailAddress),
            ]),
            _buildSection('Receiver Details', Icons.person_pin_outlined, [
              TextField(controller: _receiverName, decoration: const InputDecoration(labelText: 'Full Name *', prefixIcon: Icon(Icons.person))),
              const SizedBox(height: 16),
              TextField(controller: _receiverPhone, decoration: const InputDecoration(labelText: 'Phone Number *', prefixIcon: Icon(Icons.phone)), keyboardType: TextInputType.phone),
              const SizedBox(height: 16),
              TextField(controller: _receiverEmail, decoration: const InputDecoration(labelText: 'Email (Optional)', prefixIcon: Icon(Icons.email_outlined)), keyboardType: TextInputType.emailAddress),
            ]),
            _buildSection('Parcel Details', Icons.inventory_2_outlined, [
              DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: 'Category *'), value: _categoryId, items: _categories.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name']))).toList(), onChanged: (v) => setState(() => _categoryId = v)),
              const SizedBox(height: 16),
              TextField(controller: _weight, decoration: const InputDecoration(labelText: 'Weight (kg) *', prefixIcon: Icon(Icons.scale), suffixText: 'kg'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _calculateAndBook,
                icon: const Icon(Icons.calculate),
                label: const Text('Calculate & Book', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}