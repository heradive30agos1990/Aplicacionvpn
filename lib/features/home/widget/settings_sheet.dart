import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Ajustes sencillos: solo el tiempo de revisión de la suscripción.
class SettingsSheet extends HookConsumerWidget {
  const SettingsSheet({super.key});

  static const options = <int, String>{
    15: '15 segundos',
    30: '30 segundos',
    60: '1 minuto',
    300: '5 minutos',
    900: '15 minutos',
    3600: '1 hora',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final prefs = ref.watch(sharedPreferencesProvider).requireValue;
    final selected = useState(
      prefs.getInt(ForegroundProfilesUpdateNotifier.intervalPrefKey) ?? ForegroundProfilesUpdateNotifier.defaultCheckSeconds,
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ajustes', style: theme.textTheme.headlineSmall),
            const Gap(16),
            Text('Revisar cambios de la suscripción cada:', style: theme.textTheme.titleSmall),
            const Gap(12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in options.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: selected.value == entry.key,
                    onSelected: (_) async {
                      selected.value = entry.key;
                      await prefs.setInt(ForegroundProfilesUpdateNotifier.intervalPrefKey, entry.key);
                    },
                  ),
              ],
            ),
            const Gap(12),
            Text(
              'Cuando el servidor cambia, la suscripción se carga sola y la app avisa.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
