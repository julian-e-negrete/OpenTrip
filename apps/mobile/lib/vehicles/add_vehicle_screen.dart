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
class AddVehicleScreen extends StatefulWidget {
  const AddVehicleScreen({super.key});

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
  File? _photoFile;
  bool _saving = false;
  String? _error;

  bool get _usesCatalog => _type == VehicleType.motorcycle || _type == VehicleType.car;
  bool get _isOtherBrand => _brand?.name == otherBrandName;

  @override
  void dispose() {
    _customBrandController.dispose();
    _customModelController.dispose();
    _freeNameController.dispose();
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

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      String? photoPath;
      final photo = _photoFile;
      if (photo != null) {
        photoPath = await LocalImageStore.save(photo);
      }

      await VehicleRepository.instance.create(
        userId: await CurrentUser.instance.id(),
        name: name,
        type: _type,
        brand: brand,
        model: model,
        bleConnector: connector,
        photoPath: photoPath,
      );

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
    return Scaffold(
      appBar: AppBar(title: const Text('Add vehicle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: CircleAvatar(
                radius: 48,
                backgroundImage: _photoFile != null ? FileImage(_photoFile!) : null,
                child: _photoFile == null ? const Icon(Icons.add_a_photo_outlined, size: 32) : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _pickPhoto,
              child: Text(_photoFile == null ? 'Add photo' : 'Change photo'),
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
                : const Text('Save vehicle'),
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
