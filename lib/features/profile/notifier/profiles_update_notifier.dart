import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hiddify/core/http_client/http_client_provider.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profiles_update_notifier.g.dart';

typedef ProfileUpdateStatus = ({String name, bool success});

/// Estado visible de la última revisión (lo muestra la tarjeta de la suscripción).
typedef SyncInfo = ({DateTime time, String text, bool ok});
final ValueNotifier<SyncInfo?> syncInfo = ValueNotifier<SyncInfo?>(null);
void _setInfo(String text, {bool ok = true}) => syncInfo.value = (time: DateTime.now(), text: text, ok: ok);

/// Vigila la suscripción del servidor:
/// - Cada X segundos (se elige en Ajustes) descarga la suscripción y la compara con la anterior.
/// - Si es igual: no hace nada y la conexión sigue como está.
/// - Si cambió: desconecta, carga la configuración nueva y avisa "Se cargó el servidor exitosamente".
/// - Si no se puede descargar y la app está conectada, comprueba el internet durante 20 s;
///   si sigue sin internet, se desconecta sola.
@Riverpod(keepAlive: true)
class ForegroundProfilesUpdateNotifier extends _$ForegroundProfilesUpdateNotifier with AppLogger {
  static const watchInterval = Duration(seconds: 1);
  static const intervalPrefKey = "sub_check_seconds";
  static const defaultCheckSeconds = 15;
  static const loadedMessage = "Se cargó el servidor exitosamente";
  static const noInternetSeconds = 20;

  @override
  Stream<ProfileUpdateStatus?> build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });

    if (ref.watch(Preferences.introCompleted)) {
      loggy.debug("intro done, starting");
      _timer = Timer.periodic(watchInterval, (_) => _tick());
      Timer(const Duration(seconds: 2), _tick);
    } else {
      loggy.debug("intro in process, skipping");
    }
    return const Stream.empty();
  }

  Timer? _timer;
  DateTime? _busySince;
  final Map<String, String> _lastBody = {};
  DateTime? _lastCheck;
  bool _busy = false;
  bool _forceNext = false;
  // La primera revisión después de abrir la app se hace enseguida.
  bool _firstRun = true;

  /// Botón "actualizar": siempre vuelve a cargar la suscripción, sin esperar el tiempo elegido.
  Future<void> trigger() async {
    _forceNext = true;
    await _tick(manual: true);
  }

  Future<void> _tick({bool manual = false}) async {
    final seconds = ref.read(sharedPreferencesProvider).requireValue.getInt(intervalPrefKey) ?? defaultCheckSeconds;
    final now = DateTime.now();
    final force = manual || _firstRun;
    final last = _lastCheck;
    if (!force && last != null && now.difference(last) < Duration(seconds: seconds)) return;
    if (_busy) {
      // Si una revisión quedó colgada más de 2 minutos, se libera.
      final since = _busySince;
      if (since != null && now.difference(since) > const Duration(minutes: 2)) {
        _busy = false;
      } else {
        if (manual) _setInfo("Ya se está revisando…");
        return;
      }
    }
    _busy = true;
    _busySince = now;
    _lastCheck = now;
    _forceNext = false;
    _firstRun = false;
    try {
      _setInfo("Revisando…");
      await _sync(manual: manual).timeout(const Duration(seconds: 90));
    } on TimeoutException {
      _setInfo("La revisión tardó demasiado", ok: false);
      if (manual) ref.read(inAppNotificationControllerProvider).showErrorToast("No se pudo cargar el servidor.");
    } catch (e) {
      loggy.warning("sync failed: $e");
      _setInfo("Error al revisar", ok: false);
    } finally {
      _busy = false;
    }
  }

  Future<void> _sync({required bool manual}) async {
    final profiles = await ref
        .read(profileRepositoryProvider)
        .requireValue
        .watchAll()
        .map((event) => event.getOrElse((f) => throw f).whereType<RemoteProfileEntity>())
        .first;
    if (profiles.isEmpty) return;

    final client = ref.read(httpClientProvider);
    final toUpdate = <RemoteProfileEntity>[];
    final changedIds = <String>{};
    var downloadedAny = false;
    var downloadFailed = false;

    for (final profile in profiles) {
      String body;
      try {
        final response = await client.get<String>(_noCache(profile.url), responseType: ResponseType.plain);
        body = response.data ?? '';
      } catch (e) {
        loggy.debug("no se pudo descargar la suscripción: $e");
        downloadFailed = true;
        continue;
      }
      downloadedAny = true;
      final previous = _lastBody[profile.id];
      _lastBody[profile.id] = body;
      final changed = previous != null && previous != body;
      if (changed) {
        changedIds.add(profile.id);
        toUpdate.add(profile);
      } else if (manual) {
        // actualización manual: siempre recarga (si está conectado, sin cortar el túnel)
        toUpdate.add(profile);
      }
    }

    // No se pudo descargar nada y la app está conectada: ¿hay internet?
    if (downloadFailed && !downloadedAny && ref.read(serviceRunningProvider)) {
      _setInfo("Sin conexión", ok: false);
      await _disconnectIfNoInternet();
      return;
    }

    final notification = ref.read(inAppNotificationControllerProvider);

    if (toUpdate.isEmpty) {
      _setInfo(downloadedAny ? "Sin cambios" : "Sin conexión", ok: downloadedAny);
      return;
    }

    var ok = 0;
    var failed = 0;
    // En fila a propósito: el núcleo nativo no soporta llamadas al mismo tiempo.
    for (final profile in toUpdate) {
      // Evita que un estado "cargando" viejo bloquee la actualización.
      ref.invalidate(updateProfileNotifierProvider(profile.id));
      try {
        await ref
            .read(updateProfileNotifierProvider(profile.id).notifier)
            .updateProfile(profile, isBulk: true)
            .timeout(const Duration(seconds: 60));
      } catch (e) {
        loggy.warning("updateProfile falló: $e");
      }
      if (ref.read(updateProfileNotifierProvider(profile.id)).hasError) {
        failed++;
        _lastBody.remove(profile.id); // se reintenta en la próxima revisión
      } else {
        ok++;
      }
    }

    if (ok > 0) {
      _setInfo(changedIds.isNotEmpty ? "Servidor actualizado" : "Actualizada");
      notification.showSuccessToast(loadedMessage);
      // La configuración cambió: 5 segundos después de cargarla, se desconecta.
      if (changedIds.isNotEmpty && ref.read(serviceRunningProvider)) {
        unawaited(
          Future<void>.delayed(const Duration(seconds: 5), () async {
            if (ref.read(serviceRunningProvider)) {
              loggy.info("configuración cambiada, desconectando");
              await ref.read(connectionNotifierProvider.notifier).abortConnection();
            }
          }),
        );
      }
    } else if (failed > 0) {
      _setInfo("No se pudo cargar", ok: false);
      notification.showErrorToast("No se pudo cargar el servidor.");
    }
  }

  /// Agrega un parámetro cambiante para que ningún intermediario devuelva una copia vieja.
  String _noCache(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null) return url;
    return u.replace(queryParameters: {...u.queryParameters, '_t': DateTime.now().millisecondsSinceEpoch.toString()}).toString();
  }

  /// Comprueba el internet por el túnel durante 20 s. Si no hay, se desconecta sola.
  Future<void> _disconnectIfNoInternet() async {
    final deadline = DateTime.now().add(const Duration(seconds: noInternetSeconds));
    while (true) {
      if (!ref.read(serviceRunningProvider)) return;
      try {
        await ref.read(activeProxyNotifierProvider.notifier).urlTest("");
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 4));
      final delay = ref.read(activeProxyNotifierProvider).valueOrNull?.urlTestDelay ?? 0;
      if (ConnectionConst.isValidDelay(delay)) {
        loggy.info("hay internet, sigue conectado");
        return;
      }
      if (DateTime.now().isAfter(deadline)) break;
    }
    loggy.warning("sin internet por 20 s, desconectando");
    await ref.read(connectionNotifierProvider.notifier).abortConnection();
    ref.read(inAppNotificationControllerProvider).showErrorToast("Sin internet. Se desconectó.");
  }
}
