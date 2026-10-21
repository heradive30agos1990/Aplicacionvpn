import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/app_update/model/remote_version_entity.dart';
import 'package:hiddify/features/app_update/notifier/app_update_state.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:upgrader/upgrader.dart';

part 'app_update_notifier.g.dart';

// App fija: sin avisos ni actualizaciones forzadas.
// El Upgrader apunta a una dirección que no existe, así nunca encuentra versión nueva.
@riverpod
Upgrader upgrader(Ref ref) => Upgrader(
  storeController: UpgraderStoreController(
    onAndroid: () => UpgraderAppcastStore(appcastURL: 'http://127.0.0.1:1/appcast.xml'),
    oniOS: () => UpgraderAppcastStore(appcastURL: 'http://127.0.0.1:1/appcast.xml'),
    onLinux: () => UpgraderAppcastStore(appcastURL: 'http://127.0.0.1:1/appcast.xml'),
    onWindows: () => UpgraderAppcastStore(appcastURL: 'http://127.0.0.1:1/appcast.xml'),
    onMacOS: () => UpgraderAppcastStore(appcastURL: 'http://127.0.0.1:1/appcast.xml'),
    onWeb: () => UpgraderAppcastStore(appcastURL: 'http://127.0.0.1:1/appcast.xml'),
  ),
  durationUntilAlertAgain: const Duration(days: 36500),
  messages: UpgraderMessages(code: ref.watch(localePreferencesProvider).languageCode),
);

@Riverpod(keepAlive: true)
class AppUpdateNotifier extends _$AppUpdateNotifier with AppLogger {
  @override
  AppUpdateState build() => const AppUpdateState.initial();

  PreferencesEntry<String?, dynamic> get _ignoreReleasePref => PreferencesEntry(
    preferences: ref.read(sharedPreferencesProvider).requireValue,
    key: 'ignored_release_version',
    defaultValue: null,
  );

  // Nunca consulta GitHub ni ninguna tienda: las actualizaciones están desactivadas.
  Future<AppUpdateState> check() async {
    loggy.debug("update check disabled");
    return state = const AppUpdateState.disabled();
  }

  Future<void> ignoreRelease(RemoteVersionEntity version) async {
    await _ignoreReleasePref.write(version.version);
    state = AppUpdateStateIgnored(version);
  }
}
