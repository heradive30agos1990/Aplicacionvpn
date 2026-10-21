import 'package:dio/dio.dart';
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
import 'package:neat_periodic_task/neat_periodic_task.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profiles_update_notifier.g.dart';

typedef ProfileUpdateStatus = ({String name, bool success});

/// Vigila la suscripción del servidor:
/// - Cada X segundos (se elige en Ajustes) descarga la suscripción y la compara con la anterior.
/// - Si es igual: no hace nada y la conexión sigue como está.
/// - Si cambió: desconecta, carga la configuración nueva y avisa "Se cargó el servidor exitosamente".
/// - Si no se puede descargar y la app está conectada, comprueba el internet durante 20 s;
///   si sigue sin internet, se desconecta sola.
@Riverpod(keepAlive: true)
class ForegroundProfilesUpdateNotifier extends _$ForegroundProfilesUpdateNotifier with AppLogger {
  static const watchInterval = Duration(seconds: 5);
  static const intervalPrefKey = "sub_check_seconds";
  static const defaultCheckSeconds = 15;
  static const loadedMessage = "Se cargó el servidor exitosamente";
  static const noInternetSeconds = 20;

  @override
  Stream<ProfileUpdateStatus?> build() {
    _watcher = NeatPeriodicTaskScheduler(
      name: 'profiles change watcher',
      interval: watchInterval,
      timeout: const Duration(minutes: 3),
      task: () async => await _tick(),
    );

    ref.onDispose(() async {
      await _watcher?.stop();
      _watcher = null;
    });

    if (ref.watch(Preferences.introCompleted)) {
      loggy.debug("intro done, starting");
      _watcher?.start();
    } else {
      loggy.debug("intro in process, skipping");
    }
    return const Stream.empty();
  }

  NeatPeriodicTaskScheduler? _watcher;
  final Map<String, String> _lastBody = {};
  DateTime? _lastCheck;
  bool _busy = false;
  bool _forceNext = false;
  // La primera revisión después de abrir la app se hace enseguida.
  bool _firstRun = true;

  /// Botón "actualizar": revisa ya, sin esperar el tiempo elegido.
  Future<void> trigger() async {
    _forceNext = true;
    await _tick();
  }

  Future<void> _tick() async {
    final seconds = ref.read(sharedPreferencesProvider).requireValue.getInt(intervalPrefKey) ?? defaultCheckSeconds;
    final now = DateTime.now();
    final force = _forceNext || _firstRun;
    final last = _lastCheck;
    if (!force && last != null && now.difference(last) < Duration(seconds: seconds)) return;
    if (_busy) return;
    _busy = true;
    _lastCheck = now;
    _forceNext = false;
    _firstRun = false;
    try {
      await _sync(force: force);
    } catch (e) {
      loggy.warning("sync failed: $e");
    } finally {
      _busy = false;
    }
  }

  Future<void> _sync({required bool force}) async {
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
        final response = await client.get<String>(profile.url, responseType: ResponseType.plain);
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
      } else if (force && !ref.read(serviceRunningProvider)) {
        // sin conexión activa: aprovecha para refrescar nombre y datos
        toUpdate.add(profile);
      }
    }

    // No se pudo descargar nada y la app está conectada: ¿hay internet?
    if (downloadFailed && !downloadedAny && ref.read(serviceRunningProvider)) {
      await _disconnectIfNoInternet();
      return;
    }

    final notification = ref.read(inAppNotificationControllerProvider);

    if (toUpdate.isEmpty) {
      if (force && downloadedAny) notification.showSuccessToast("La suscripción está al día");
      return;
    }

    // La configuración cambió: se desconecta antes de cargar la nueva.
    if (changedIds.isNotEmpty && ref.read(serviceRunningProvider)) {
      loggy.info("la configuración cambió, desconectando");
      await ref.read(connectionNotifierProvider.notifier).abortConnection();
    }

    var ok = 0;
    var failed = 0;
    // En fila a propósito: el núcleo nativo no soporta llamadas al mismo tiempo.
    for (final profile in toUpdate) {
      await ref.read(updateProfileNotifierProvider(profile.id).notifier).updateProfile(profile, isBulk: true);
      if (ref.read(updateProfileNotifierProvider(profile.id)).hasError) {
        failed++;
        _lastBody.remove(profile.id); // se reintenta en la próxima revisión
      } else {
        ok++;
      }
    }

    if (ok > 0) {
      notification.showSuccessToast(loadedMessage);
    } else if (failed > 0) {
      notification.showErrorToast("No se pudo cargar el servidor.");
    }
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
