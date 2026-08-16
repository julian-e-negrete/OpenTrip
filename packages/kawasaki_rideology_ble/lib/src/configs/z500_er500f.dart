// Ported from configs/z500_er500f_config.json in
// https://github.com/Zen3515/homeassistant-kawasaki-rideology-ble
// (Apache License 2.0). See /NOTICE.md at the repo root.
//
// Covers the ER500F platform: Z500 / Z500 ABS / Ninja 500 (2024+
// generation). Captured and validated against a real Z500. NOT yet
// independently re-validated against a 2026 Z500 ABS unit specifically —
// see /README.md "Z500 ABS 2026 validation status" and
// /docs/CAPTURE_GUIDE.md if you have one and want to confirm/correct this.
//
// The original JSON this was translated from ships alongside this file
// (z500_er500f_config.json) for provenance/diffing; the app uses this Dart
// version so the package needs no asset-bundling setup.

import '../bike_config.dart';

const BikeConfig z500Er500fConfig = BikeConfig(
  model: 'Kawasaki-ER500F',
  startupFrames: [
    0x03, 0x40, 0x1A, 0x1D, 0x47, 0x0B, 0x41, 0x1B, 0x48, 0x1E, 0x08, 0x45, 0x42,
  ],
  startupNoWaitFrames: {0x42},
  controlWriteWithResponse: true,
  requireStartupResponses: true,
  startupWaitTimeout: Duration(seconds: 3),
  startupInterFrameDelay: Duration(milliseconds: 200),
  startupRetries: 3,
  startupRetryDelay: Duration(seconds: 1),
  rpmMode: 'raw',
  wheelMode: 'raw1',
  // Full true/false support map as captured from this bike's app traffic.
  // `true` fields are confirmed present; `false` fields are confirmed
  // ABSENT and always come back null (this is a denylist — see
  // BikeConfig.supportedFields doc). Anything not listed at all (e.g.
  // front brake pressure, ABS status) wasn't exercised during capture and
  // is parsed opportunistically from the raw bytes instead.
  supportedFields: {
    'accel_g': false,
    'engine_torque_actual': false,
    'engine_torque_request': false,
    'gear': true,
    'lean_deg': false,
    'rider_torque_request': false,
    'rpm': true,
    'status_fuel_injection': true,
    'tcs_level_hb': false,
    'tcs_level_lb': false,
    'throttle': true,
    'ecu_battery12V': true,
    'meter_battery12V': false,
    'total_fuel_consumed': false,
    'fuel_gauge': false,
    'average_fuel_mileage': false,
    'tripA': false,
    'tripB': false,
    'average_speed': false,
    'outer_air_temperature': false,
    'range_symbol': false,
    'range': false,
    'fuel_consumption': false,
    'total_time': false,
    'odometer': false,
    'total_distance_traveled': false,
    'engine_fuel_rate': false,
    'water_temperature': true,
    'oil_temperature': false,
    'inlet_air_temperature': true,
    'instant_fuel_consumption': false,
    'rr_suspension_stroke': false,
    'fr_suspension_stroke': false,
    'rr_suspension_stroke_vp': false,
    'fr_suspension_stroke_vp': false,
    'ay_psip1': false,
    'ay': false,
    'ax_psip3': false,
    'ax': false,
    'az_psip2': false,
    'az': false,
    'tire_pressure_fr': false,
    'tire_pressure_rr': false,
    'air_pressure_drop_fr': false,
    'air_pressure_drop_rr': false,
    'low_battery_voltage_fr': false,
    'low_battery_voltage_rr': false,
    'wheel_kph': true,
    'wheelie_angle': false,
    'wheelie_flag': false,
  },
  infoConfigFlags: {
    'acceleration': 3,
    'average_fuel_mileage': 3,
    'average_speed': 3,
    'boost_pressure': 3,
    'boost_temperature': 3,
    'ecu_battery12V': 0,
    'engine_fuel_rate': 3,
    'engine_oil_temperature': 3,
    'engine_speed': 0,
    'engine_torque_actual': 3,
    'engine_torque_request': 3,
    'engine_water_temperature': 1,
    'fuel_consumption': 3,
    'fuel_gauge': 3,
    'fuel_injection': 1,
    'gear_position': 1,
    'inlet_air_temperature': 1,
    'lean_angle': 3,
    'meter_battery12V': 3,
    'odometer': 3,
    'outer_air_temperature': 3,
    'range': 3,
    'range_symbol': 3,
    'rider_torque_request': 3,
    'tcs_level_hb': 3,
    'tcs_level_lb': 3,
    'throttle_position': 1,
    'total_fuel_consumed': 3,
    'total_time': 3,
    'tripA': 3,
    'tripB': 3,
    'instant_fuel_consumption': 3,
    'total_distance_traveled': 3,
    'wheel_speed': 1,
    'wheelie_angle': 3,
    'wheelie_flag': 3,
  },
);
