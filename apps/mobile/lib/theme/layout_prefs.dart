import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the live ride screen leads with. [cluster] only makes sense over
/// a BLE-connected bike — screens fall back to [numbers] at render time
/// when there's no telemetry, per the design handoff.
enum RecordVariant { map, numbers, cluster }

enum TripListVariant { cards, dense }

enum TripDetailVariant { grid, report }

enum RanksVariant { bars, podium }

/// The four layout variants from the Nocturne redesign are user-facing
/// settings (Account → Appearance), not build-time choices — every
/// screen builds all of its variants and switches on this at render
/// time. Persisted with shared_preferences; [load] must complete before
/// the first frame so screens don't flash a default and then jump (see
/// main.dart, which awaits it before runApp).
class LayoutPrefs extends ChangeNotifier {
  LayoutPrefs._();
  static final instance = LayoutPrefs._();

  static const _kRecord = 'layout.record';
  static const _kTripList = 'layout.tripList';
  static const _kTripDetail = 'layout.tripDetail';
  static const _kRanks = 'layout.ranks';

  RecordVariant record = RecordVariant.map;
  TripListVariant tripList = TripListVariant.cards;
  TripDetailVariant tripDetail = TripDetailVariant.grid;
  RanksVariant ranks = RanksVariant.bars;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    record = _read(prefs, _kRecord, RecordVariant.values, record);
    tripList = _read(prefs, _kTripList, TripListVariant.values, tripList);
    tripDetail = _read(prefs, _kTripDetail, TripDetailVariant.values, tripDetail);
    ranks = _read(prefs, _kRanks, RanksVariant.values, ranks);
  }

  /// A stored index this build doesn't know (saved by a newer build that
  /// had an extra variant, then downgraded) falls back to the default
  /// rather than throwing a RangeError before the first frame — which,
  /// since main() awaits [load], would keep the app from starting at all.
  static T _read<T>(SharedPreferences prefs, String key, List<T> values, T fallback) {
    final i = prefs.getInt(key);
    return i != null && i >= 0 && i < values.length ? values[i] : fallback;
  }

  Future<void> setRecord(RecordVariant v) async {
    record = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_kRecord, v.index);
  }

  Future<void> setTripList(TripListVariant v) async {
    tripList = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_kTripList, v.index);
  }

  Future<void> setTripDetail(TripDetailVariant v) async {
    tripDetail = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_kTripDetail, v.index);
  }

  Future<void> setRanks(RanksVariant v) async {
    ranks = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_kRanks, v.index);
  }
}
