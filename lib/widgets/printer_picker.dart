import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../services/printer_settings.dart';
import '../theme.dart';

/// Lets the cashier choose which paired Bluetooth printer receipts go to.
Future<void> showPrinterPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => const _PrinterPicker(),
  );
}

class _PrinterPicker extends StatefulWidget {
  const _PrinterPicker();

  @override
  State<_PrinterPicker> createState() => _PrinterPickerState();
}

class _PrinterPickerState extends State<_PrinterPicker> {
  List<BluetoothInfo>? _devices;
  String? _selectedMac;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _devices = null;
      _error = null;
    });
    try {
      final saved = await PrinterSettings.load();
      if (!await PrintBluetoothThermal.bluetoothEnabled) {
        setState(() {
          _devices = [];
          _error = 'Bluetooth is off. Turn it on and tap Refresh.';
        });
        return;
      }
      final devices = await PrintBluetoothThermal.pairedBluetooths;
      if (!mounted) return;
      setState(() {
        _selectedMac = saved?.mac;
        _devices = devices;
        if (devices.isEmpty) _error = 'No paired printers. Pair the printer in the phone\'s Bluetooth settings first.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _devices = [];
          _error = 'Could not list Bluetooth devices: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Text('Receipt printer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Refresh')),
            ]),
            const SizedBox(height: 8),
            if (_devices == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(_error!, style: const TextStyle(color: AppColors.muted)))
            else
              ..._devices!.map((d) => ListTile(
                    leading: const Icon(Icons.print),
                    title: Text(d.name.isEmpty ? d.macAdress : d.name),
                    subtitle: Text(d.macAdress),
                    trailing: d.macAdress == _selectedMac ? const Icon(Icons.check_circle, color: AppColors.orange) : null,
                    onTap: () async {
                      await PrinterSettings.save(d.macAdress, d.name.isEmpty ? d.macAdress : d.name);
                      if (context.mounted) Navigator.pop(context);
                    },
                  )),
          ],
        ),
      ),
    );
  }
}
