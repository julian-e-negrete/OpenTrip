// Ported from custom_components/kawasaki/kawi_ble5_client.py and const.py
// in https://github.com/Zen3515/homeassistant-kawasaki-rideology-ble
// (Apache License 2.0). See /NOTICE.md at the repo root.

/// The GATT service every supported Kawasaki Rideology-equipped bike
/// exposes its control/notify characteristics under.
const String kServiceUuid = '92faec07-c075-4b7c-a6c2-bbd1d1a150f5';

/// Write frames here to send commands/requests to the bike.
const String kControlCharacteristicUuid =
    'acf1b15c-10f9-4942-a32d-f9e019b95402';

/// Subscribe to all three: different frame types are pushed on different
/// notify characteristics (the split is the bike's choice, not ours).
const List<String> kNotifyCharacteristicUuids = [
  '3aabbb34-eac0-40f5-9d50-3a1ee6787136',
  '02fad1bd-358e-441c-b296-fe874af38a7e',
  '5e119eba-35a7-4463-a7af-7fa40a302350',
];

/// Bikes advertise their BLE name as `Kawasaki-XXXX`. Scan filters should
/// match on this prefix rather than a fixed name.
const List<String> kAdvertisedNamePrefixes = ['Kawasaki-', 'Kawasaki'];

/// Frame (command/notification) IDs — always the first byte of a frame.
abstract final class KawiFrame {
  static const int generalSettings = 0x1B;
  static const int ack = 0x20;
  static const int modelInfo = 0x03;
  static const int meterIndicationInit = 0x08;
  static const int optionalProbe0A = 0x0A;
  static const int phoneModel = 0x0B;
  static const int generalSettingCapability = 0x1A;
  static const int mcInfoConfig = 0x40;
  static const int vehicleSettingConfig = 0x47;
  static const int mcInfo = 0x41;
  static const int emcInfo = 0x42;
  static const int commonService = 0x1D;
  static const int serviceIndicator = 0x1E;
  static const int ridingLogExt = 0x45;
  static const int vehicleSettings = 0x48;
  static const int statusReport = 0x30;
  static const int ridingLogMid = 0x4A;
  static const int ridingLogHigh = 0x4B;
}

/// The sequence of frames the official app sends right after connecting.
/// Mirrored exactly so bikes that expect this order don't reject requests.
const List<int> kDefaultStartupFrames = [
  KawiFrame.modelInfo,
  KawiFrame.mcInfoConfig,
  KawiFrame.generalSettingCapability,
  KawiFrame.commonService,
  KawiFrame.vehicleSettingConfig,
  KawiFrame.phoneModel,
  KawiFrame.mcInfo,
  KawiFrame.generalSettings,
  KawiFrame.vehicleSettings,
  KawiFrame.serviceIndicator,
  KawiFrame.meterIndicationInit,
  KawiFrame.ridingLogExt,
  KawiFrame.emcInfo,
];

String frameName(int? frameId) {
  if (frameId == null) return 'unknown';
  const names = <int, String>{
    KawiFrame.modelInfo: 'model_info',
    KawiFrame.meterIndicationInit: 'meter_indication_init',
    KawiFrame.optionalProbe0A: 'optional_probe_0a',
    KawiFrame.phoneModel: 'phone_model',
    KawiFrame.generalSettingCapability: 'general_setting_capability',
    KawiFrame.generalSettings: 'general_settings',
    KawiFrame.commonService: 'common_service',
    KawiFrame.serviceIndicator: 'service_indicator',
    KawiFrame.statusReport: 'status_report',
    KawiFrame.mcInfoConfig: 'mc_info_config',
    KawiFrame.mcInfo: 'mc_info',
    KawiFrame.emcInfo: 'emc_info',
    KawiFrame.ridingLogExt: 'riding_log_ext',
    KawiFrame.vehicleSettingConfig: 'vehicle_setting_config',
    KawiFrame.vehicleSettings: 'vehicle_settings',
    KawiFrame.ridingLogMid: 'riding_log_mid',
    KawiFrame.ridingLogHigh: 'riding_log_high',
  };
  return names[frameId] ?? 'unknown_0x${frameId.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

String ackResultText(int? resultCode) {
  if (resultCode == null) return 'unknown';
  if (resultCode == 0x00) return 'accepted';
  if (resultCode == 0x01) return 'rejected_or_unsupported';
  return 'error_0x${resultCode.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

/// (fieldName, byteIndex, mask, shift) — how each 2-bit support/scaling
/// flag is packed into the 0x40 (MC info config) frame. A decoded value of
/// 3 means "not supported by this bike"; 0 or 1 means "supported".
const List<(String, int, int, int)> infoConfigFieldLayout = [
  ('total_distance_traveled', 7, 0xC0, 6),
  ('total_fuel_consumed', 7, 0x30, 4),
  ('engine_fuel_rate', 7, 0x0C, 2),
  ('ecu_battery12V', 7, 0x03, 0),
  ('engine_water_temperature', 8, 0xC0, 6),
  ('engine_oil_temperature', 8, 0x30, 4),
  ('inlet_air_temperature', 8, 0x0C, 2),
  ('boost_temperature', 8, 0x03, 0),
  ('boost_pressure', 9, 0xC0, 6),
  ('fuel_injection', 9, 0x30, 4),
  ('wheel_speed', 9, 0x0C, 2),
  ('engine_speed', 9, 0x03, 0),
  ('gear_position', 10, 0xF0, 4),
  ('throttle_position', 10, 0x0C, 2),
  ('acceleration', 10, 0x03, 0),
  ('lean_angle', 11, 0xC0, 6),
  ('wheelie_flag', 11, 0x30, 4),
  ('wheelie_angle', 11, 0x0C, 2),
  ('tcs_level_hb', 11, 0x03, 0),
  ('tcs_level_lb', 12, 0xC0, 6),
  ('rider_torque_request', 12, 0x30, 4),
  ('engine_torque_request', 12, 0x0C, 2),
  ('engine_torque_actual', 12, 0x03, 0),
  ('odometer', 27, 0xC0, 6),
  ('fuel_gauge', 27, 0x30, 4),
  ('average_fuel_mileage', 27, 0x0C, 2),
  ('meter_battery12V', 27, 0x03, 0),
  ('tripA', 28, 0xC0, 6),
  ('tripB', 28, 0x30, 4),
  ('average_speed', 28, 0x0C, 2),
  ('outer_air_temperature', 28, 0x03, 0),
  ('range_symbol', 29, 0xC0, 6),
  ('range', 29, 0x30, 4),
  ('fuel_consumption', 29, 0x0C, 2),
  ('total_time', 29, 0x03, 0),
  ('instant_fuel_consumption', 31, 0x0C, 2),
];

/// (fieldName, byteIndex, mask, shift) for the 0x1D common-service config
/// frame (maintenance-reminder capability flags), also reused inside the
/// EV/HEV variant of the 0x42 EMC info frame.
const List<(String, int, int, int)> commonServiceConfigFieldLayout = [
  ('kawasaki_service_setting_capability', 7, 0xC0, 6),
  ('user_setting_capability', 7, 0x30, 4),
  ('oil_change_setting_capability', 7, 0x0C, 2),
  ('kawasaki_service_notify', 8, 0xC0, 6),
  ('kawasaki_service_month', 8, 0x30, 4),
  ('kawasaki_service_day', 8, 0x0C, 2),
  ('kawasaki_service_year', 8, 0x03, 0),
  ('kawasaki_service_distance', 9, 0x30, 4),
  ('user_setting_notify', 9, 0x0C, 2),
  ('user_setting_month', 9, 0x03, 0),
  ('user_setting_day', 10, 0xC0, 6),
  ('user_setting_year', 10, 0x30, 4),
  ('user_setting_distance', 10, 0x03, 0),
  ('oil_change_notify', 11, 0xC0, 6),
  ('oil_change_month', 11, 0x30, 4),
  ('oil_change_day', 11, 0x0C, 2),
  ('oil_change_year', 11, 0x03, 0),
  ('oil_change_distance', 12, 0x30, 4),
];
