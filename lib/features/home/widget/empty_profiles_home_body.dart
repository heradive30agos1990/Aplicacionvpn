import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class EmptyProfilesHomeBody extends HookConsumerWidget {
  const EmptyProfilesHomeBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.vpn_key_rounded, size: 56, color: theme.colorScheme.primary),
            const Gap(20),
            Text('Bienvenido', style: theme.textTheme.headlineSmall),
            const Gap(8),
            Text(
              'Ingresa el enlace de tu suscripción para empezar.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const Gap(24),
            FilledButton.icon(
              onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
              icon: const Icon(Icons.link_rounded),
              label: const Text('Agregar suscripción'),
            ),
          ],
        ),
      ),
    );
  }
}
