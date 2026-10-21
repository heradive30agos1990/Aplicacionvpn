import 'package:dartx/dartx.dart';
import 'package:dio/dio.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:meta/meta.dart';
import 'package:neat_periodic_task/neat_periodic_task.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profiles_update_notifier.g.dart';

typedef ProfileUpdateStatus = ({String name, bool success});

@Riverpod(keepAlive: true)
class ForegroundProfilesUpdateNotifier extends _$ForegroundProfilesUpdateNotifier with AppLogger {
  static const prefKey = "profiles_update_check";
  static const interval = Duration(minutes: 5);
  static const watchInterval = Duration(seconds: 15);
  static const loadedMessage = "Se cargó el servidor exitosamente";

  @override
  Stream<ProfileUpdateStatus?> build() {
    var cycleCount = 0;
    _scheduler = NeatPeriodicTaskScheduler(
      name: 'profiles update worker',
      interval: interval,
      timeout: const Duration(minutes: 5),
      task: () async {
        loggy.debug("cycle [${cycleCount++}]");
        await updateProfiles();
      },
    );

    // Vigilante: cada 15 s mira si el contenido de la suscripción cambió en el servidor
    // y, si cambió, la recarga al instante y avisa.
    _watcher = NeatPeriodicTaskScheduler(
      name: 'profiles change watcher',
      interval: watchInterval,
      timeout: const Duration(minutes: 2),
      task: () async => await _checkChanges(),
    );

    ref.onDispose(() async {
      await _scheduler?.stop();
      _scheduler = null;
      await _watcher?.stop();
      _watcher = null;
    });

    if (ref.watch(Preferences.introCompleted)) {
      loggy.debug("intro done, starting");
      _scheduler?.start();
      _watcher?.start();
    } else {
      loggy.debug("intro in process, skipping");
    }
    return const Stream.empty();
  }

  NeatPeriodicTaskScheduler? _scheduler;
  NeatPeriodicTaskScheduler? _watcher;
  final Map<String, String> _lastBody = {};
  bool _busy = false;
  bool _forceNextRun = false;
  // La primera revisión después de abrir la app siempre se hace y avisa.
  bool _firstRun = true;

  Future<void> trigger() async {
    loggy.debug("triggering update");
    _forceNextRun = true;
    await _scheduler?.trigger();
  }

  Future<void> _checkChanges() async {
    if (_busy) return;
    _busy = true;
    try {
      final remoteProfiles = await ref
          .read(profileRepositoryProvider)
          .requireValue
          .watchAll()
          .map((event) => event.getOrElse((f) => throw f).whereType<RemoteProfileEntity>())
          .first;
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          responseType: ResponseType.plain,
        ),
      );
      final changed = <RemoteProfileEntity>[];
      for (final profile in remoteProfiles) {
        try {
          final response = await dio.get<String>(profile.url);
          final body = response.data ?? '';
          final previous = _lastBody[profile.id];
          _lastBody[profile.id] = body;
          if (previous != null && previous != body) changed.add(profile);
        } catch (_) {
          // sin conexión con el servidor de la suscripción: se intenta de nuevo en el próximo ciclo
        }
      }
      var ok = 0;
      for (final profile in changed) {
        await ref.read(updateProfileNotifierProvider(profile.id).notifier).updateProfile(profile, isBulk: true);
        if (!ref.read(updateProfileNotifierProvider(profile.id)).hasError) ok++;
      }
      if (ok > 0) {
        ref.read(inAppNotificationControllerProvider).showSuccessToast(loadedMessage);
        await _verificarInternet();
      }
    } catch (e) {
      loggy.warning("change watcher failed: $e");
    } finally {
      _busy = false;
    }
  }

  /// Si la app está conectada, comprueba que el servidor recién cargado tenga internet.
  /// Si lo tiene, sigue conectada; si no, se desconecta y avisa.
  Future<void> _verificarInternet() async {
    try {
      if (!ref.read(serviceRunningProvider)) return;
      // da tiempo a que el núcleo se reconecte con la configuración nueva
      await Future<void>.delayed(const Duration(seconds: 8));
      for (var intento = 0; intento < 3; intento++) {
        if (!ref.read(serviceRunningProvider)) return;
        await ref.read(activeProxyNotifierProvider.notifier).urlTest("");
        await Future<void>.delayed(const Duration(seconds: 5));
        final delay = ref.read(activeProxyNotifierProvider).valueOrNull?.urlTestDelay ?? 0;
        if (ConnectionConst.isValidDelay(delay)) {
          loggy.info("el servidor nuevo tiene internet, sigue conectado");
          return;
        }
      }
      loggy.warning("el servidor nuevo no tiene internet, desconectando");
      await ref.read(connectionNotifierProvider.notifier).abortConnection();
      ref.read(inAppNotificationControllerProvider).showErrorToast("El servidor no tiene internet. Se desconectó.");
    } catch (e) {
      loggy.warning("no se pudo verificar el internet: $e");
    }
  }

  @visibleForTesting
  Future<void> updateProfiles() async {
    if (_busy) return;
    _busy = true;
    var force = false;
    if (_forceNextRun || _firstRun) {
      force = true;
      _forceNextRun = false;
      _firstRun = false;
    }

    try {
      final previousRun = DateTime.tryParse(ref.read(sharedPreferencesProvider).requireValue.getString(prefKey) ?? "");

      if (!force && previousRun != null && previousRun.add(interval) > DateTime.now()) {
        loggy.debug("too soon! previous run: [$previousRun]");
        return;
      }
      loggy.debug("${force ? "[FORCED] " : ""}running, previous run: [$previousRun]");

      final remoteProfiles = await ref
          .read(profileRepositoryProvider)
          .requireValue
          .watchAll()
          .map(
            (event) => event.getOrElse((f) {
              loggy.error("error getting profiles");
              throw f;
            }).whereType<RemoteProfileEntity>(),
          )
          .first;

      final toUpdate = remoteProfiles.where((profile) {
        final updateInterval = profile.options?.updateInterval;
        final shouldUpdate =
            true;
        if (!shouldUpdate) {
          loggy.debug(
            "skipping profile [${profile.id}] update. last successful update: [${profile.lastUpdate}] - interval: [${profile.options?.updateInterval}]",
          );
        }
        return shouldUpdate;
      }).toList();

      var successCount = 0;
      final failedNames = <String>[];
      // Sequential on purpose: validation and the active-profile reconnect share
      // one native core that is not safe to call concurrently (it can hang).
      for (final profile in toUpdate) {
        await ref.read(updateProfileNotifierProvider(profile.id).notifier).updateProfile(profile, isBulk: true);
        if (ref.read(updateProfileNotifierProvider(profile.id)).hasError) {
          failedNames.add(profile.name);
        } else {
          successCount++;
        }
      }

      // Only a manual run (forced) reports; the periodic background run stays silent.
      if (force && (successCount > 0 || failedNames.isNotEmpty)) {
        final t = ref.read(translationsProvider).requireValue;
        final notification = ref.read(inAppNotificationControllerProvider);
        if (failedNames.isEmpty) {
          notification.showSuccessToast(loadedMessage);
        } else {
          notification.showErrorToast(
            t.pages.profiles.msg.update.bulkPartial(
              success: successCount,
              failed: failedNames.length,
              names: failedNames.join(", "),
            ),
          );
        }
      }
    } finally {
      _busy = false;
      await ref.read(sharedPreferencesProvider).requireValue.setString(prefKey, DateTime.now().toIso8601String());
    }
  }
}


