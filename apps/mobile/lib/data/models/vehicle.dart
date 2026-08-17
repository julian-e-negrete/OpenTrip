enum VehicleType { motorcycle, car, bicycle, other }

/// How this vehicle's live telemetry (if any) is read. Only one connector
/// exists today — see /packages/kawasaki_rideology_ble — everything else
/// is GPS-only. Normally derived automatically from the selected
/// brand/model (see data/catalog/vehicle_catalog.dart) rather than picked
/// by hand.
enum VehicleBleConnector { none, kawasakiRideology }

class Vehicle {
  final String id;
  final String userId;
  final String name;
  final VehicleType type;

  /// Empty for bicycle/other, which skip the brand/model catalog and use
  /// [name] as free text instead.
  final String brand;
  final String model;

  final VehicleBleConnector bleConnector;
  final String? photoPath;
  final DateTime createdAt;

  const Vehicle({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    this.brand = '',
    this.model = '',
    required this.bleConnector,
    this.photoPath,
    required this.createdAt,
  });

  Vehicle copyWith({
    String? name,
    VehicleType? type,
    String? brand,
    String? model,
    VehicleBleConnector? bleConnector,
    String? photoPath,
  }) {
    return Vehicle(
      id: id,
      userId: userId,
      name: name ?? this.name,
      type: type ?? this.type,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      bleConnector: bleConnector ?? this.bleConnector,
      photoPath: photoPath ?? this.photoPath,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toRow() => {
    'id': id,
    'user_id': userId,
    'name': name,
    'type': type.name,
    'brand': brand,
    'model': model,
    'ble_connector': bleConnector.name,
    'photo_path': photoPath,
    'created_at': createdAt.toIso8601String(),
  };

  static Vehicle fromRow(Map<String, Object?> row) => Vehicle(
    id: row['id'] as String,
    userId: row['user_id'] as String,
    name: row['name'] as String,
    type: VehicleType.values.byName(row['type'] as String),
    brand: row['brand'] as String? ?? '',
    model: row['model'] as String? ?? '',
    bleConnector: VehicleBleConnector.values.byName(row['ble_connector'] as String),
    photoPath: row['photo_path'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
  );
}
