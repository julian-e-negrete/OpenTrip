enum VehicleType { motorcycle, car, bicycle, other }

/// How this vehicle's live telemetry (if any) is read. Only one connector
/// exists today — see /packages/kawasaki_rideology_ble — everything else
/// is GPS-only.
enum VehicleBleConnector { none, kawasakiRideology }

class Vehicle {
  final String id;
  final String userId;
  final String name;
  final VehicleType type;
  final VehicleBleConnector bleConnector;
  final DateTime createdAt;

  const Vehicle({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    required this.bleConnector,
    required this.createdAt,
  });

  Vehicle copyWith({String? name, VehicleType? type, VehicleBleConnector? bleConnector}) {
    return Vehicle(
      id: id,
      userId: userId,
      name: name ?? this.name,
      type: type ?? this.type,
      bleConnector: bleConnector ?? this.bleConnector,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toRow() => {
    'id': id,
    'user_id': userId,
    'name': name,
    'type': type.name,
    'ble_connector': bleConnector.name,
    'created_at': createdAt.toIso8601String(),
  };

  static Vehicle fromRow(Map<String, Object?> row) => Vehicle(
    id: row['id'] as String,
    userId: row['user_id'] as String,
    name: row['name'] as String,
    type: VehicleType.values.byName(row['type'] as String),
    bleConnector: VehicleBleConnector.values.byName(row['ble_connector'] as String),
    createdAt: DateTime.parse(row['created_at'] as String),
  );
}
