import 'package:flutter/foundation.dart';

/// Fires whenever local vehicle/trip data changes (create/update/delete).
///
/// Screens live inside HomeShell's IndexedStack, which keeps all five tabs
/// mounted so an in-progress GPS recording survives switching tabs — but
/// that also means a screen's initState only runs once, ever, so it can't
/// rely on "I'll just reload next time I'm opened" the way a normally
/// pushed/popped screen could. Repositories notify here after a write;
/// screens that cache a loaded list listen and reload instead of quietly
/// showing stale data (e.g. Record tab still showing "no vehicles" after
/// one was just added from the Vehicles tab).
class DataEvents {
  DataEvents._();
  static final instance = DataEvents._();

  final ValueNotifier<int> _tick = ValueNotifier(0);

  Listenable get listenable => _tick;

  void notifyChanged() => _tick.value++;
}
