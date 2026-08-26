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

  /// Odometer reading before this vehicle started being tracked in the
  /// app — a used vehicle, or one ridden before this app existed, has
  /// mileage the app never recorded a trip for. Null means "unknown",
  /// treated as 0 (so current mileage is estimated as just the sum of
  /// every recorded trip's distance) rather than blocking mileage/service
  /// tracking on a number the user might not know.
  final double? startingOdometerKm;

  /// Distance between services (oil change, chain, tires — whatever this
  /// vehicle needs) — null disables service tracking entirely for this
  /// vehicle, since not every vehicle type has a meaningful fixed
  /// interval and the interval itself varies a lot by
  /// vehicle/manufacturer, so there's no sane app-wide default to assume.
  final double? serviceIntervalKm;

  /// Odometer reading at the last logged service. Null means "never
  /// serviced since tracking began" — the interval is then measured from
  /// [startingOdometerKm] (or 0) instead. See
  /// vehicles/vehicle_detail_screen.dart's "Log service" action, which is
  /// the only thing that sets this to anything other than null.
  final double? lastServiceOdometerKm;

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
    this.startingOdometerKm,
    this.serviceIntervalKm,
    this.lastServiceOdometerKm,
    this.synced = false,
  });

  Vehicle copyWith({
    String? name,
    VehicleType? type,
    String? brand,
    String? model,
    VehicleBleConnector? bleConnector,
    String? photoPath,
    double? startingOdometerKm,
    double? serviceIntervalKm,
    double? lastServiceOdometerKm,
    bool clearServiceInterval = false,
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
      startingOdometerKm: startingOdometerKm ?? this.startingOdometerKm,
      // Unlike every other field, service tracking needs a real way to
      // turn back off (a vehicle's owner decides they don't want to
      // track it anymore) — `?? this.x` alone can only ever set a value,
      // never clear one back to null.
      serviceIntervalKm: clearServiceInterval ? null : (serviceIntervalKm ?? this.serviceIntervalKm),
      lastServiceOdometerKm: lastServiceOdometerKm ?? this.lastServiceOdometerKm,
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
    'starting_odometer_km': startingOdometerKm,
    'service_interval_km': serviceIntervalKm,
    'last_service_odometer_km': lastServiceOdometerKm,
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
    startingOdometerKm: row['starting_odometer_km'] as double?,
    serviceIntervalKm: row['service_interval_km'] as double?,
    lastServiceOdometerKm: row['last_service_odometer_km'] as double?,
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
    'starting_odometer_km': startingOdometerKm,
    'service_interval_km': serviceIntervalKm,
    'last_service_odometer_km': lastServiceOdometerKm,
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
    startingOdometerKm: (row['starting_odometer_km'] as num?)?.toDouble(),
    serviceIntervalKm: (row['service_interval_km'] as num?)?.toDouble(),
    lastServiceOdometerKm: (row['last_service_odometer_km'] as num?)?.toDouble(),
    synced: true,
  );
}
