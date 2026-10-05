import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/pricing.dart';
import '../services/printer_settings.dart';
import '../services/receipt_service.dart';
import '../services/staff_profile.dart';
import '../theme.dart';
import '../widgets/printer_picker.dart';

/// Branches, categories and pricing needed to quote a booking.
class BookingSetup {
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> categories;
  final PricingRules rules;

  const BookingSetup({required this.branches, required this.categories, required this.rules});

  static Future<BookingSetup> load() async {
    final supabase = Supabase.instance.client;
    final branches = await supabase.from('branches').select('id, name, code, latitude, longitude').eq('status', 'active').order('name');
    final categories = await supabase.from('parcel_categories').select('id, name').eq('status', 'active').order('name');

    var rules = const PricingRules(); // Defaults if no rule is set up yet
    try {
      final businessId = (await supabase.from('businesses').select('id').limit(1).single())['id'];
      final row = await supabase.from('pricing_rules').select('*').eq('business_id', businessId).maybeSingle();
      if (row != null) rules = PricingRules.fromRow(row);
    } catch (e) {
      debugPrint('Error loading pricing rules: $e');
    }

    return BookingSetup(
      branches: List<Map<String, dynamic>>.from(branches),
      categories: List<Map<String, dynamic>>.from(categories),
      rules: rules,
    );
  }
}

enum PayMethod {
  cash('CASH', 'Cash'),
  mpesa('MPESA_PROMPT', 'M-Pesa'), // prompt on the customer's phone (supabase/mpesa.sql)
  card('CARD', 'Card');

  final String code;
  final String label;
  const PayMethod(this.code, this.label);
}

class BookingScreen extends StatefulWidget {
  final StaffProfile profile;
  final Future<BookingSetup> Function() loadSetup;

  const BookingScreen({super.key, required this.profile, this.loadSetup = BookingSetup.load});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  BookingSetup? _setup;
  String? _loadError;
  bool _isSaving = false;
  bool _showErrors = false;

  final _senderName = TextEditingController();
  final _senderPhone = TextEditingController();
  final _receiverName = TextEditingController();
  final _receiverPhone = TextEditingController();
  final _weight = TextEditingController();
  final _cashReceived = TextEditingController();
  final _mpesaPhone = TextEditingController(); // number that gets the M-Pesa prompt

  late final _controllers = [_senderName, _senderPhone, _receiverName, _receiverPhone, _weight, _cashReceived, _mpesaPhone];

  String? _originId;
  String? _destId;
  String? _categoryId;
  PayMethod _method = PayMethod.cash;

  @override
  void initState() {
    super.initState();
    _originId = widget.profile.branchId;
    for (final c in _controllers) {
      c.addListener(() => setState(() {}));
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final setup = await widget.loadSetup();
      if (!mounted) return;
      setState(() {
        _setup = setup;
        if (!setup.branches.any((b) => b['id'] == _originId)) _originId = null;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    }
  }

  Map<String, dynamic>? _branch(String? id) {
    if (id == null) return null;
    for (final b in _setup!.branches) {
      if (b['id'] == id) return b;
    }
    return null;
  }

  double? get _weightKg => double.tryParse(_weight.text.trim());
  double? get _cashAmount => double.tryParse(_cashReceived.text.trim());

  /// Straight-line distance between the chosen branches, or null if either lacks GPS.
  double? get _distanceKm {
    final from = _branch(_originId), to = _branch(_destId);
    if (from == null || to == null || from['id'] == to['id']) return null;
    if (!_hasGps(from) || !_hasGps(to)) return null;
    double v(Map<String, dynamic> b, String key) => (b[key] as num).toDouble();
    return distanceBetween(v(from, 'latitude'), v(from, 'longitude'), v(to, 'latitude'), v(to, 'longitude'));
  }

  /// Older branches were saved as 0,0 when GPS was left empty; treat that as missing.
  static bool _hasGps(Map<String, dynamic> b) {
    final lat = b['latitude'] as num?, lon = b['longitude'] as num?;
    return lat != null && lon != null && !(lat == 0 && lon == 0);
  }

  Quote? get _quote {
    final weight = _weightKg, distance = _distanceKm;
    if (weight == null || weight <= 0 || distance == null) return null;
    return calculateQuote(_setup!.rules, weight, distance);
  }

  /// Everything still missing before the booking can be taken, in form order.
  List<String> _problems(Quote? quote) {
    final from = _branch(_originId), to = _branch(_destId);
    final sameBranch = from != null && from['id'] == to?['id'];
    return [
      if (from == null) 'Choose the branch the parcel is sent from.',
      if (to == null) 'Choose the destination branch.',
      if (sameBranch) 'Destination must be a different branch.',
      if (from != null && to != null && !sameBranch && _distanceKm == null)
        '${_hasGps(from) ? to['name'] : from['name']} has no GPS location. Ask an admin to add it under Branches in the web admin.',
      if (_senderName.text.trim().isEmpty) "Enter the sender's name.",
      if (_senderPhone.text.trim().isEmpty) "Enter the sender's phone number.",
      if (_receiverName.text.trim().isEmpty) "Enter the receiver's name.",
      if (_receiverPhone.text.trim().isEmpty) "Enter the receiver's phone number.",
      if (_categoryId == null) 'Choose a parcel category.',
      if (_weightKg == null || _weightKg! <= 0) 'Enter the parcel weight in kg.',
      if (quote != null && _method == PayMethod.cash && (_cashAmount ?? 0) < quote.total)
        'Cash received must be at least KSh ${formatKsh(quote.total)}.',
      if (_method == PayMethod.mpesa && normalizeKenyanPhone(_mpesaPhone.text) == null)
        "Enter the customer's M-Pesa number, e.g. 0712 345 678.",
    ];
  }

  void _clearForm() {
    for (final c in _controllers) {
      c.clear();
    }
    setState(() {
      _destId = null;
      _categoryId = null;
      _method = PayMethod.cash;
      _showErrors = false;
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final quote = _quote;
    if (_problems(quote).isNotEmpty || quote == null) {
      setState(() => _showErrors = true);
      return;
    }

    if (_method == PayMethod.mpesa) {
      await _bookWithMpesa(quote);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final result = await _saveBooking(quote);
      if (!mounted) return;
      setState(() => _isSaving = false);
      await _showDone(result, quote);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking failed: $e'), backgroundColor: AppColors.errorText));
    }
  }

  /// Saves customers, parcel, payment and receipt in one database call
  /// (supabase/book_parcel.sql), so a dropped connection can't leave half a booking.
  Future<({String bookingNumber, String receiptNumber})> _saveBooking(Quote quote) async {
    final result = await Supabase.instance.client.rpc('book_parcel', params: {
      'p_origin_branch_id': _originId,
      'p_destination_branch_id': _destId,
      'p_category_id': _categoryId,
      'p_weight_kg': _weightKg,
      'p_distance_km': double.parse(quote.distanceKm.toStringAsFixed(2)),
      'p_shipping_charge': double.parse(quote.total.toStringAsFixed(2)),
      'p_sender_name': _senderName.text.trim(),
      'p_sender_phone': _senderPhone.text.trim(),
      'p_receiver_name': _receiverName.text.trim(),
      'p_receiver_phone': _receiverPhone.text.trim(),
      'p_payment_method': _method.code,
    }) as Map<String, dynamic>;
    return (bookingNumber: result['booking_number'].toString(), receiptNumber: result['receipt_number'].toString());
  }

  /// M-Pesa: book as AWAITING_PAYMENT, send the prompt, wait for Safaricom's confirmation.
  /// The amount is the server's price; the parcel only becomes BOOKED when paid.
  Future<void> _bookWithMpesa(Quote quote) async {
    setState(() => _isSaving = true);
    Map<String, dynamic> booking;
    try {
      booking = await Supabase.instance.client.rpc('book_parcel', params: {
        'p_origin_branch_id': _originId,
        'p_destination_branch_id': _destId,
        'p_category_id': _categoryId,
        'p_weight_kg': _weightKg,
        'p_distance_km': double.parse(quote.distanceKm.toStringAsFixed(2)),
        'p_shipping_charge': quote.total,
        'p_sender_name': _senderName.text.trim(),
        'p_sender_phone': _senderPhone.text.trim(),
        'p_receiver_name': _receiverName.text.trim(),
        'p_receiver_phone': _receiverPhone.text.trim(),
        'p_payment_method': PayMethod.mpesa.code,
      }) as Map<String, dynamic>;
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      final message = e is PostgrestException ? e.message : '$e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking failed: $message'), backgroundColor: AppColors.errorText));
      return;
    }
    if (!mounted) return;
    setState(() => _isSaving = false);

    final bookingNumber = booking['booking_number'].toString();
    final receiptNumber = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => MpesaWaitDialog(
        parcelId: booking['parcel_id'].toString(),
        bookingNumber: bookingNumber,
        phone: _mpesaPhone.text.trim(),
        amount: (booking['amount'] as num).toDouble(),
        branchId: widget.profile.branchId,
      ),
    );
    if (!mounted) return;
    if (receiptNumber != null) {
      await _showDone((bookingNumber: bookingNumber, receiptNumber: receiptNumber), quote);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('M-Pesa booking cancelled. You can take cash or card instead and book again.'),
      ));
    }
  }

  Future<bool> _printReceipt(({String bookingNumber, String receiptNumber}) result, Quote quote) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      await Future.delayed(const Duration(seconds: 2)); // No Bluetooth printing on Windows: simulate
      return true;
    }
    var printer = await PrinterSettings.load();
    if (printer == null && mounted) {
      await showPrinterPicker(context);
      printer = await PrinterSettings.load();
    }
    if (printer == null) return false;

    return ReceiptService.printReceipt(
      macAddress: printer.mac,
      branchName: widget.profile.branchName,
      bookingNumber: result.bookingNumber,
      receiptNumber: result.receiptNumber,
      senderName: _senderName.text.trim(),
      senderPhone: _senderPhone.text.trim(),
      receiverName: _receiverName.text.trim(),
      receiverPhone: _receiverPhone.text.trim(),
      destination: _branch(_destId)?['name'] ?? '',
      weight: _weightKg!,
      amount: double.parse(quote.total.toStringAsFixed(2)),
      paymentMethod: _method.label,
      cashierName: widget.profile.name,
    );
  }

  Future<void> _showDone(({String bookingNumber, String receiptNumber}) result, Quote quote) async {
    final change = _method == PayMethod.cash ? (_cashAmount ?? 0) - quote.total : 0.0;
    var printing = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: AppColors.successText, size: 48),
          title: const Text('Parcel booked'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _summaryRow('Booking no.', result.bookingNumber),
              _summaryRow('Receipt no.', result.receiptNumber),
              _summaryRow('Paid (${_method.label})', 'KSh ${formatKsh(quote.total)}'),
              if (change > 0) ...[
                const SizedBox(height: 12),
                _messageBox('Change to give: KSh ${formatKsh(change)}', AppColors.successBg, AppColors.successText, margin: false),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: printing ? null : () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
              onPressed: printing
                  ? null
                  : () async {
                      setDialogState(() => printing = true);
                      final ok = await _printReceipt(result, quote);
                      if (!dialogContext.mounted || !mounted) return;
                      setDialogState(() => printing = false);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok ? 'Receipt printed' : 'Printing failed. Check the printer and try again.'),
                        backgroundColor: ok ? AppColors.successText : AppColors.errorText,
                      ));
                      if (ok) Navigator.pop(dialogContext);
                    },
              icon: printing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.print),
              label: const Text('Print receipt'),
            ),
          ],
        ),
      ),
    );
    if (mounted) _clearForm();
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Could not load branches and prices.\n$_loadError', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );
    }
    if (_setup == null) return const Center(child: CircularProgressIndicator());

    final quote = _quote;
    final problems = _problems(quote);
    final change = quote != null && _method == PayMethod.cash && _cashAmount != null ? _cashAmount! - quote.total : null;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          _card([
            _sectionTitle('Route'),
            _branchDropdown('From', _originId, (v) => setState(() => _originId = v)),
            const SizedBox(height: 12),
            _branchDropdown('To', _destId, (v) => setState(() => _destId = v)),
          ]),
          _card([
            _sectionTitle('Sender'),
            _textField(_senderName, 'Full name', capitalize: true),
            const SizedBox(height: 12),
            _textField(_senderPhone, 'Phone number', phone: true),
          ]),
          _card([
            _sectionTitle('Receiver'),
            _textField(_receiverName, 'Full name', capitalize: true),
            const SizedBox(height: 12),
            _textField(_receiverPhone, 'Phone number', phone: true),
          ]),
          _card([
            _sectionTitle('Parcel'),
            DropdownButtonFormField<String>(
              key: ValueKey('category-$_categoryId'),
              initialValue: _categoryId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: _setup!.categories.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name']))).toList(),
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 12),
            _textField(_weight, 'Weight (kg)', decimal: true, suffix: 'kg'),
          ]),
          _card([
            _sectionTitle('Payment'),
            _methodSelector(),
            const SizedBox(height: 12),
            if (_method == PayMethod.cash) _textField(_cashReceived, 'Cash received (KSh)', decimal: true),
            if (_method == PayMethod.mpesa) ...[
              _textField(_mpesaPhone, "Customer's M-Pesa number", phone: true),
              const SizedBox(height: 6),
              const Text('They get a prompt on this phone and enter their M-Pesa PIN.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
            if (_method == PayMethod.card)
              const Text('Charge the card on the card machine before booking.', style: TextStyle(color: AppColors.muted)),
          ]),
          if (quote != null) _quoteCard(quote),
          if (change != null && change >= 0)
            _messageBox('Change to give: KSh ${formatKsh(change)}', AppColors.successBg, AppColors.successText),
          if (_showErrors && problems.isNotEmpty) _messageBox(problems.first, AppColors.errorBg, AppColors.errorText),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _submit,
              child: _isSaving
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(_submitLabel(quote), textAlign: TextAlign.center),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _isSaving ? null : _clearForm, child: const Text('Clear form')),
        ],
      ),
    );
  }

  String _submitLabel(Quote? quote) {
    if (quote == null) return 'Book parcel';
    final amount = 'KSh ${formatKsh(quote.total)}';
    return switch (_method) {
      PayMethod.cash => 'Take $amount cash and book',
      PayMethod.mpesa => 'Send $amount M-Pesa prompt',
      PayMethod.card => 'Record $amount card and book',
    };
  }

  Widget _card(List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      );

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.muted)),
      );

  Widget _textField(TextEditingController controller, String label,
      {bool phone = false, bool decimal = false, bool capitalize = false, bool upper = false, String? suffix}) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 17),
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      keyboardType: phone
          ? TextInputType.phone
          : decimal
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
      inputFormatters: decimal ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
      textCapitalization: upper
          ? TextCapitalization.characters
          : capitalize
              ? TextCapitalization.words
              : TextCapitalization.none,
    );
  }

  Widget _branchDropdown(String label, String? value, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: _setup!.branches.map((b) => DropdownMenuItem(value: b['id'].toString(), child: Text(b['name']))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _methodSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: PayMethod.values.map((m) {
          final selected = m == _method;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _method = m;
                if (m == PayMethod.mpesa && _mpesaPhone.text.trim().isEmpty) _mpesaPhone.text = _senderPhone.text.trim();
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? AppColors.selected : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: selected ? Border.all(color: AppColors.border) : null,
                ),
                child: Text(m.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppColors.text : AppColors.muted,
                    )),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _quoteCard(Quote quote) {
    final from = _branch(_originId)!, to = _branch(_destId)!;
    final rules = _setup!.rules;
    final km = quote.distanceKm.round();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AppColors.navy,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(flex: 2, child: _routeEnd(from, CrossAxisAlignment.start)),
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(children: [
                        Text('$km km', style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(height: 4),
                        Container(height: 2, color: AppColors.orange),
                        const SizedBox(height: 6),
                      ]),
                    ),
                  ),
                  Expanded(flex: 2, child: _routeEnd(to, CrossAxisAlignment.end)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(children: [
                _priceRow('Base rate', quote.baseRate),
                _priceRow(
                  quote.extraWeightKg > 0
                      ? 'Weight over ${formatKsh(rules.baseWeightKg)} kg (+${formatKsh(quote.extraWeightKg)} kg)'
                      : 'Weight, up to ${formatKsh(rules.baseWeightKg)} kg',
                  quote.weightCharge,
                ),
                _priceRow('Distance, $km km', quote.distanceCharge),
              ]),
            ),
            Container(
              color: AppColors.background,
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const Text('Total', style: TextStyle(color: AppColors.muted, fontSize: 15)),
                const SizedBox(width: 12),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text('KSh ${formatKsh(quote.total)}',
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.text)),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _routeEnd(Map<String, dynamic> branch, CrossAxisAlignment align) {
    final name = branch['name'].toString();
    final code = (branch['code'] ?? (name.length > 3 ? name.substring(0, 3) : name)).toString().toUpperCase();
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(code, style: const TextStyle(color: AppColors.text, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      ],
    );
  }

  Widget _priceRow(String label, double amount) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15, color: AppColors.muted))),
          Text(formatKsh(amount), style: const TextStyle(fontSize: 15, color: AppColors.text)),
        ]),
      );

  Widget _summaryRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Text(label, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(width: 12),
          Expanded(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );

  Widget _messageBox(String text, Color background, Color foreground, {bool margin = true}) => Container(
        width: double.infinity,
        margin: margin ? const EdgeInsets.only(bottom: 14) : null,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(color: foreground, fontSize: 15)),
      );
}

/// Sends the M-Pesa prompt and waits for the customer. Returns the receipt number when
/// Safaricom confirms payment, or null if the booking was cancelled.
class MpesaWaitDialog extends StatefulWidget {
  final String parcelId;
  final String bookingNumber;
  final String phone;
  final double amount;
  final String? branchId;

  const MpesaWaitDialog({
    super.key,
    required this.parcelId,
    required this.bookingNumber,
    required this.phone,
    required this.amount,
    required this.branchId,
  });

  @override
  State<MpesaWaitDialog> createState() => _MpesaWaitDialogState();
}

class _MpesaWaitDialogState extends State<MpesaWaitDialog> {
  static const _checkEvery = Duration(seconds: 4);
  static const _giveUpAfter = Duration(minutes: 2);

  String? _checkoutId;
  String _state = 'sending'; // sending | waiting | failed
  String? _message;
  Timer? _timer;
  DateTime _startedAt = DateTime.now();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _send();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      final res = await Supabase.instance.client.functions.invoke('mpesa-pay', body: body);
      return Map<String, dynamic>.from(res.data as Map);
    } on FunctionException catch (e) {
      throw Exception(e.details is Map ? e.details['error'] : 'M-Pesa error (${e.status})');
    }
  }

  Future<void> _send() async {
    _timer?.cancel();
    setState(() {
      _state = 'sending';
      _message = null;
    });
    try {
      final res = await _call({'action': 'send', 'parcel_id': widget.parcelId, 'phone': widget.phone});
      if (!mounted) return;
      _checkoutId = res['checkout_request_id'];
      _startedAt = DateTime.now();
      setState(() => _state = 'waiting');
      _timer = Timer.periodic(_checkEvery, (_) => _check());
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = 'failed';
          _message = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _check() async {
    if (_busy || _checkoutId == null) return;
    _busy = true;
    try {
      final res = await _call({'action': 'check', 'checkout_request_id': _checkoutId});
      if (!mounted) return;
      switch (res['status']) {
        case 'success':
          _timer?.cancel();
          Navigator.pop(context, (res['receipt_number'] ?? '').toString());
        case 'cancelled':
          _stop('The customer cancelled the M-Pesa prompt.');
        case 'failed':
        case 'amount_mismatch':
          _stop(res['result_desc']?.toString() ?? 'The payment did not go through.');
        default:
          if (DateTime.now().difference(_startedAt) > _giveUpAfter) {
            _stop('No answer from the customer yet. Ask them to check their phone, then send again.');
          }
      }
    } catch (_) {
      // Network blip: keep waiting, the next check will retry
    } finally {
      _busy = false;
    }
  }

  void _stop(String message) {
    _timer?.cancel();
    setState(() {
      _state = 'failed';
      _message = message;
    });
  }

  Future<void> _cancelBooking() async {
    _timer?.cancel();
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('parcels').update({'status': 'CANCELLED'}).eq('id', widget.parcelId);
      await supabase.from('parcel_status_history').insert({
        'parcel_id': widget.parcelId,
        'status': 'CANCELLED',
        'user_id': supabase.auth.currentUser!.id,
        'branch_id': widget.branchId,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Still close: an unpaid AWAITING_PAYMENT parcel never counts as booked
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _state != 'failed';
    return AlertDialog(
      icon: waiting
          ? const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3))
          : const Icon(Icons.error_outline, color: AppColors.errorText, size: 44),
      title: Text(_state == 'sending'
          ? 'Sending M-Pesa prompt…'
          : waiting
              ? 'Waiting for the customer…'
              : 'Not paid yet'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('KSh ${formatKsh(widget.amount)} to ${widget.phone}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 8),
        Text(
          waiting ? 'Ask the customer to enter their M-Pesa PIN on their phone.' : (_message ?? ''),
          textAlign: TextAlign.center,
          style: TextStyle(color: waiting ? AppColors.muted : AppColors.errorText),
        ),
        const SizedBox(height: 8),
        Text('Booking ${widget.bookingNumber}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      ]),
      actions: [
        TextButton(onPressed: _cancelBooking, child: const Text('Cancel booking')),
        if (!waiting)
          ElevatedButton(
            onPressed: _send,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
            child: const Text('Send again'),
          ),
      ],
    );
  }
}
