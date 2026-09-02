import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/admin_pin_store.dart';

/// Lunghezza consentita per il PIN Admin (M48) — stesso vincolo usato sia
/// nella schermata di primo accesso (`admin_pin_gate.dart`) sia nel dialog
/// "Cambia PIN" dentro Admin, un solo punto invece di duplicare i numeri.
const int adminPinMinLength = 4;
const int adminPinMaxLength = 6;

final adminPinStoreProvider = Provider<AdminPinStore>((ref) {
  return AdminPinStore();
});
