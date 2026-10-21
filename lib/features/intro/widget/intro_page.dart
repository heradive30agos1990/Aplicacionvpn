import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/analytics/analytics_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class IntroPage extends HookConsumerWidget with PresLogger {
  const IntroPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isStarting = useState(false);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/images/source/ic_launcher_border.png', width: 200, height: 200),
              const Gap(24),
              Text('Internet Ilimitado', style: theme.textTheme.headlineMedium),
              const Gap(8),
              Text('Conéctate con tu suscripción', style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: isStarting.value
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
            : const Icon(Icons.rocket_launch),
        label: Text('Empezar', style: theme.textTheme.titleMedium),
        onPressed: () async {
          if (isStarting.value) return;
          isStarting.value = true;
          try {
            await ref.read(analyticsControllerProvider.notifier).disableAnalytics();
          } catch (error, stackTrace) {
            loggy.error("could not disable analytics", error, stackTrace);
          }
          await ref.read(Preferences.introCompleted.notifier).update(true);
        },
      ),
    );
  }
}
