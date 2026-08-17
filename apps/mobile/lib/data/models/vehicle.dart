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

  /// Local file path only — never synced (see sync/sync_service.dart;
  /// photo sync needs Supabase Storage, not set up yet).
  final String? photoPath;
  final DateTime createdAt;

  /// Whether this row has been pushed to Supabase. Always true for rows
  /// that came from a pull. See sync/sync_service.dart.
  final bool synced;

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
    this.synced = false,
  });

  Vehicle copyWith({
    String? name,
    VehicleType? type,
    String? brand,
    String? model,
    VehicleBleConnector? bleConnector,
    String? photoPath,
    bool? synced,
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
      synced: synced ?? this.synced,
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
    'synced': synced ? 1 : 0,
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
    synced: (row['synced'] as int? ?? 0) != 0,
  );

  /// What gets pushed to Supabase (supabase/schema.sql's `vehicles` table)
  /// — no photo_path/synced, those are local-only concepts.
  Map<String, Object?> toSupabaseRow() => {
    'id': id,
    'user_id': userId,
    'name': name,
    'type': type.name,
    'brand': brand,
    'model': model,
    'ble_connector': bleConnector.name,
    'created_at': createdAt.toIso8601String(),
  };

  /// A row pulled from Supabase — always synced, never has a local photo.
  static Vehicle fromSupabaseRow(Map<String, Object?> row) => Vehicle(
    id: row['id'] as String,
    userId: row['user_id'] as String,
    name: row['name'] as String,
    type: VehicleType.values.byName(row['type'] as String),
    brand: row['brand'] as String? ?? '',
    model: row['model'] as String? ?? '',
    bleConnector: VehicleBleConnector.values.byName(row['ble_connector'] as String),
    createdAt: DateTime.parse(row['created_at'] as String),
    synced: true,
  );
}
