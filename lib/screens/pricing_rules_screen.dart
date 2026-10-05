import 'package:flutter/material.dart';
import '../theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PricingRulesScreen extends StatefulWidget {
  const PricingRulesScreen({super.key});

  @override
  State<PricingRulesScreen> createState() => _PricingRulesScreenState();
}

class _PricingRulesScreenState extends State<PricingRulesScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _ruleId;

  final _basePriceController = TextEditingController();
  final _baseWeightController = TextEditingController();
  final _extraKgPriceController = TextEditingController();
  final _fuelCostController = TextEditingController();
  final _vatController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPricingRules();
  }

  @override
  void dispose() {
    _basePriceController.dispose();
    _baseWeightController.dispose();
    _extraKgPriceController.dispose();
    _fuelCostController.dispose();
    _vatController.dispose();
    super.dispose();
  }

  Future<void> _loadPricingRules() async {
    setState(() => _isLoading = true);
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
          _ruleId = response['id'];
          _basePriceController.text = response['base_price'].toString();
          _baseWeightController.text = response['base_weight_kg'].toString();
          _extraKgPriceController.text = response['price_per_extra_kg'].toString();
          _fuelCostController.text = response['fuel_cost_per_km'].toString();
          _vatController.text = (response['vat_rate'] ?? 0).toString();
          _isLoading = false;
        });
      } else {
        setState(() {
          _basePriceController.text = '150';
          _baseWeightController.text = '5';
          _extraKgPriceController.text = '50';
          _fuelCostController.text = '30';
          _vatController.text = '0';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading rules: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveRules() async {
    if (_basePriceController.text.isEmpty || _baseWeightController.text.isEmpty || 
        _extraKgPriceController.text.isEmpty || _fuelCostController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All fields are required'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final supabase = Supabase.instance.client;
      final businessId = (await supabase.from('businesses').select('id').limit(1).single())['id'];

      final ruleData = {
        'business_id': businessId,
        'base_price': double.parse(_basePriceController.text),
        'base_weight_kg': double.parse(_baseWeightController.text),
        'price_per_extra_kg': double.parse(_extraKgPriceController.text),
        'fuel_cost_per_km': double.parse(_fuelCostController.text),
        'vat_rate': double.tryParse(_vatController.text.trim()) ?? 0,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (_ruleId != null) {
        await supabase.from('pricing_rules').update(ruleData).eq('id', _ruleId!);
      } else {
        final res = await supabase.from('pricing_rules').insert(ruleData).select().single();
        _ruleId = res['id'];
      }

      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pricing rules updated successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving rules: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pricing Rules'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Configure how parcel prices are calculated.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),

                  _buildTextField(_basePriceController, 'Base Price (KES)', 'e.g., 150', Icons.attach_money),
                  const SizedBox(height: 16),
                  _buildTextField(_baseWeightController, 'Base Weight Limit (KG)', 'e.g., 5', Icons.scale),
                  const SizedBox(height: 16),
                  _buildTextField(_extraKgPriceController, 'Price per Extra KG (KES)', 'e.g., 50', Icons.add_circle_outline),
                  const SizedBox(height: 16),
                  _buildTextField(_fuelCostController, 'Fuel Cost per KM (KES)', 'e.g., 30', Icons.local_gas_station),
                  const SizedBox(height: 16),
                  _buildTextField(_vatController, 'VAT % added on top (0 = off)', 'e.g., 16', Icons.receipt_long),
                  const SizedBox(height: 6),
                  const Text(
                    'Prices above exclude VAT; customers pay price + VAT, rounded up to whole shillings. '
                    'Turn VAT on only after every branch has the app version that shows it.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),

                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveRules,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Save Pricing Rules', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, String hint, IconData icon) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.orange),
        border: const OutlineInputBorder(),
      ),
    );
  }
}