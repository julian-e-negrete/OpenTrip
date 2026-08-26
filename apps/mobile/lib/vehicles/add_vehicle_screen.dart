import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../auth/current_user.dart';
import '../data/catalog/vehicle_catalog.dart';
import '../data/local_image_store.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/vehicle_repository.dart';

/// Vehicle creation is deliberately brand -> model, not free text, for
/// motorcycles and cars: a model in the catalog (data/catalog/vehicle_catalog.dart)
/// can carry a known [VehicleBleConnector], so picking e.g. "Kawasaki" +
/// "Z500 ABS" auto-wires the same BLE connector this app already ships,
/// instead of the user having to know to check a box. Bicycle/other keep
/// simple free-text naming — there's no connector catalog for those yet.
///
/// Doubles as the edit screen — pass [vehicle] to prefill every field from
/// an existing one and save via [VehicleRepository.update] instead of
/// [VehicleRepository.create]. A stored brand/model is matched back to a
/// catalog entry by name; if nothing matches (the catalog changed, or it
/// was saved under "Other" originally) it falls back to the free-text
/// "Other" fields instead of silently losing the value.
class AddVehicleScreen extends StatefulWidget {
  const AddVehicleScreen({super.key, this.vehicle});

  final Vehicle? vehicle;

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  VehicleType _type = VehicleType.motorcycle;
  CatalogBrand? _brand;
  CatalogModel? _model;
  final _customBrandController = TextEditingController();
  final _customModelController = TextEditingController();
  final _freeNameController = TextEditingController();
  final _startingOdometerController = TextEditingController();
  final _serviceIntervalController = TextEditingController();
  File? _photoFile;
  // The vehicle's photo before this screen touched anything — kept
  // separate from [_photoFile] (only set once the user picks a *new*
  // photo) so save knows whether to actually replace the file on disk.
  String? _existingPhotoPath;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.vehicle != null;
  bool get _usesCatalog => _type == VehicleType.motorcycle || _type == VehicleType.car;
  bool get _isOtherBrand => _brand?.name == otherBrandName;

  @override
  void initState() {
    super.initState();
    final vehicle = widget.vehicle;
    if (vehicle != null) _prefillFrom(vehicle);
  }

  void _prefillFrom(Vehicle vehicle) {
    _type = vehicle.type;
    _existingPhotoPath = vehicle.photoPath;
    if (_usesCatalog) {
      final brands = brandsFor(vehicle.type);
      CatalogBrand? matchedBrand;
      for (final b in brands) {
        if (b.name == vehicle.brand) {
          matchedBrand = b;
          break;
        }
      }
      if (matchedBrand != null) {
        _brand = matchedBrand;
        for (final m in matchedBrand.models) {
          if (m.name == vehicle.model) {
            _model = m;
            break;
          }
        }
      } else {
        // Not in the catalog (or the catalog changed since this vehicle
        // was saved) — fall back to "Other" rather than dropping the
        // stored brand/model on the floor.
        _brand = brands.firstWhere((b) => b.name == otherBrandName);
        _customBrandController.text = vehicle.brand;
        _customModelController.text = vehicle.model;
      }
    } else {
      _freeNameController.text = vehicle.name;
    }
    if (vehicle.startingOdometerKm != null) {
      _startingOdometerController.text = _trimZero(vehicle.startingOdometerKm!);
    }
    if (vehicle.serviceIntervalKm != null) {
      _serviceIntervalController.text = _trimZero(vehicle.serviceIntervalKm!);
    }
  }

  /// "5000.0" reads oddly in a form field meant for a whole-km estimate —
  /// drop the trailing ".0" a plain [toString] would otherwise show.
  String _trimZero(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

  @override
  void dispose() {
    _customBrandController.dispose();
    _customModelController.dispose();
    _freeNameController.dispose();
    _startingOdometerController.dispose();
    _serviceIntervalController.dispose();
    super.dispose();
  }

  void _onTypeChanged(VehicleType? type) {
    if (type == null) return;
    setState(() {
      _type = type;
      _brand = null;
      _model = null;
    });
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600);
    if (picked == null) return;
    setState(() => _photoFile = File(picked.path));
  }

  Future<void> _save() async {
    final String name;
    final String brand;
    final String model;
    final VehicleBleConnector connector;

    if (_usesCatalog) {
      if (_isOtherBrand) {
        brand = _customBrandController.text.trim();
        model = _customModelController.text.trim();
        connector = VehicleBleConnector.none;
      } else {
        brand = _brand?.name ?? '';
        model = _model?.name ?? '';
        connector = _model?.connector ?? VehicleBleConnector.none;
      }
      if (brand.isEmpty || model.isEmpty) {
        setState(() => _error = 'Pick a brand and model (or fill in both under "Other").');
        return;
      }
      name = '$brand $model';
    } else {
      final freeName = _freeNameController.text.trim();
      if (freeName.isEmpty) {
        setState(() => _error = 'Enter a name.');
        return;
      }
      name = freeName;
      brand = '';
      model = '';
      connector = VehicleBleConnector.none;
    }

    final startingOdometerText = _startingOdometerController.text.trim();
    final serviceIntervalText = _serviceIntervalController.text.trim();
    final startingOdometerKm = startingOdometerText.isEmpty ? null : double.tryParse(startingOdometerText);
    final serviceIntervalKm = serviceIntervalText.isEmpty ? null : double.tryParse(serviceIntervalText);
    if (startingOdometerText.isNotEmpty && (startingOdometerKm == null || startingOdometerKm < 0)) {
      setState(() => _error = 'Starting odometer must be a positive number.');
      return;
    }
    if (serviceIntervalText.isNotEmpty && (serviceIntervalKm == null || serviceIntervalKm <= 0)) {
      setState(() => _error = 'Service interval must be a positive number.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      var photoPath = _existingPhotoPath;
      final newPhoto = _photoFile;
      if (newPhoto != null) {
        photoPath = await LocalImageStore.save(newPhoto);
        // Only reachable in edit mode ­— replacing a photo that was never
        // set has nothing to clean up.
        await LocalImageStore.deleteIfExists(_existingPhotoPath);
      }

      final vehicle = widget.vehicle;
      if (vehicle != null) {
        await VehicleRepository.instance.update(
          vehicle.copyWith(
            name: name,
            type: _type,
            brand: brand,
            model: model,
            bleConnector: connector,
            photoPath: photoPath,
            startingOdometerKm: startingOdometerKm,
            serviceIntervalKm: serviceIntervalKm,
            clearServiceInterval: serviceIntervalKm == null,
            // Every field above just changed locally — re-push on next sync
            // rather than leaving the remote row stale.
            synced: false,
          ),
        );
      } else {
        await VehicleRepository.instance.create(
          userId: await CurrentUser.instance.id(),
          name: name,
          type: _type,
          brand: brand,
          model: model,
          bleConnector: connector,
          photoPath: photoPath,
          startingOdometerKm: startingOdometerKm,
          serviceIntervalKm: serviceIntervalKm,
        );
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayedPhoto = _photoFile ?? (_existingPhotoPath != null ? File(_existingPhotoPath!) : null);
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit vehicle' : 'Add vehicle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: CircleAvatar(
                radius: 48,
                backgroundImage: displayedPhoto != null ? FileImage(displayedPhoto) : null,
                child: displayedPhoto == null ? const Icon(Icons.add_a_photo_outlined, size: 32) : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _pickPhoto,
              child: Text(displayedPhoto == null ? 'Add photo' : 'Change photo'),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<VehicleType>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
            items: VehicleType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.name))).toList(),
            onChanged: _onTypeChanged,
          ),
          const SizedBox(height: 16),
          if (_usesCatalog) ..._buildCatalogFields() else _buildFreeNameField(),
          if (_model?.connector != null && _model!.connector != VehicleBleConnector.none) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.bluetooth),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This model supports Kawasaki Rideology BLE — telemetry '
                        'can connect automatically when recording a trip.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Mileage & service',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _startingOdometerController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Starting odometer (km)',
              helperText: 'Mileage before this vehicle started being tracked here — leave blank if unknown.',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _serviceIntervalController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Service interval (km)',
              helperText: 'Leave blank to turn off service tracking for this vehicle.',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_editing ? 'Save changes' : 'Save vehicle'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCatalogFields() {
    final brands = brandsFor(_type);
    return [
      DropdownButtonFormField<CatalogBrand>(
        initialValue: _brand,
        decoration: const InputDecoration(labelText: 'Brand', border: OutlineInputBorder()),
        items: brands.map((b) => DropdownMenuItem(value: b, child: Text(b.name))).toList(),
        onChanged: (b) => setState(() {
          _brand = b;
          _model = null;
        }),
      ),
      const SizedBox(height: 16),
      if (_brand != null)
        if (_isOtherBrand) ...[
          TextField(
            controller: _customBrandController,
            decoration: const InputDecoration(labelText: 'Brand name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _customModelController,
            decoration: const InputDecoration(labelText: 'Model name', border: OutlineInputBorder()),
          ),
        ] else
          DropdownButtonFormField<CatalogModel>(
            initialValue: _model,
            decoration: const InputDecoration(labelText: 'Model', border: OutlineInputBorder()),
            items: _brand!.models
                .map((m) => DropdownMenuItem(value: m, child: Text(m.name)))
                .toList(),
            onChanged: (m) => setState(() => _model = m),
          ),
    ];
  }

  Widget _buildFreeNameField() {
    return TextField(
      controller: _freeNameController,
      decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
      autofocus: true,
    );
  }
}
