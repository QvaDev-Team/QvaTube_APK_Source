import 'package:flutter/services.dart';

import 'device_channel.dart';

/// Orientación preferida de la pantalla, solo en teléfonos y tablets.
///
/// En un televisor (Google TV) no se puede girar: si se pide vertical,
/// Android encoge toda la app en una franja estrecha en el centro ("modo
/// teléfono"). En la tele y en escritorio no se toca nada.
abstract final class AppOrientation {
  const AppOrientation._();

  static Future<void> set(List<DeviceOrientation> orientations) async {
    if (DeviceChannel.isTelevision || DeviceChannel.isDesktop) return;
    await SystemChrome.setPreferredOrientations(orientations);
  }
}
