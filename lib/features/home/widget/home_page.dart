import 'package:dartx/dartx.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/home/widget/empty_profiles_home_body.dart';
import 'package:hiddify/features/home/widget/settings_sheet.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sliver_tools/sliver_tools.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    // final hasAnyProfile = ref.watch(hasAnyProfileProvider);
    final activeProfile = ref.watch(activeProfileProvider);

    return Scaffold(
      appBar: AppBar(
        // leading: (RootScaffold.stateKey.currentState?.hasDrawer ?? false) && showDrawerButton(context)
        //     ? DrawerButton(
        //         onPressed: () {
        //           RootScaffold.stateKey.currentState?.openDrawer();
        //         },
        //       )
        //     : null,
        title: Row(
          children: [
            Image.asset('assets/images/source/ic_launcher_border.png', height: 28),
            const Gap(8),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Internet Ilimitado'),
                  const TextSpan(text: " "),
                  const WidgetSpan(child: AppVersionLabel(), alignment: PlaceholderAlignment.middle),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const SettingsSheet(),
            ),
          ),
          const Gap(8),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/images/world_map.png'), // Replace with your image path
            fit: BoxFit.cover,
            opacity: 0.09,
            colorFilter: theme.brightness == Brightness.dark
                ? ColorFilter.mode(Colors.white.withValues(alpha: .15), BlendMode.srcIn) //
                : ColorFilter.mode(
                    Colors.grey.withValues(alpha: 1),
                    BlendMode.srcATop,
                  ), // Apply white tint in dark mode
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 600, // Set the maximum width here
                ),
                child: CustomScrollView(
                  slivers: [
                    // switch (activeProfile) {
                    // AsyncData(value: final profile?) =>
                    if (!(ref.watch(hasAnyProfileProvider).value ?? true)) const EmptyProfilesHomeBody(),
                    if (ref.watch(hasAnyProfileProvider).value ?? true)
                    MultiSliver(
                      children: [
                        // const Gap(100),
                        switch (activeProfile) {
                          AsyncData(value: final profile?) => SliverToBoxAdapter(child: _PerfilCard(profile: profile)),
                          _ => const SliverToBoxAdapter(),
                        },
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [ConnectionButton(), ActiveProxyDelayIndicator()],
                                ),
                              ),
                              Gap(32),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // AsyncData() => switch (hasAnyProfile) {
                    //     AsyncData(value: true) => const EmptyActiveProfileHomeBody(),
                    //     _ => const EmptyProfilesHomeBody(),
                    //   },
                    // AsyncError(:final error) => SliverErrorBodyPlaceholder(t.presentShortError(error)),
                    // _ => const SliverToBoxAdapter(),
                    // },
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppVersionLabel extends HookConsumerWidget {
  const AppVersionLabel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final version = ref.watch(appInfoProvider).requireValue.presentVersion;
    if (version.isBlank) return const SizedBox();

    return Semantics(
      label: t.common.version,
      button: false,
      child: Container(
        decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          version,
          textDirection: TextDirection.ltr,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
        ),
      ),
    );
  }
}

String _gb(num bytes) => '${(bytes / 1073741824).toStringAsFixed(1)} GB';

String _hace(DateTime t) {
  final d = DateTime.now().difference(t).inSeconds;
  if (d < 5) return 'ahora mismo';
  if (d < 60) return 'hace $d s';
  if (d < 3600) return 'hace ${d ~/ 60} min';
  return 'hace ${d ~/ 3600} h';
}

class _PerfilCard extends HookConsumerWidget {
  const _PerfilCard({required this.profile});
  final ProfileEntity profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // refresca el "hace X s" cada segundo
    final tick = useState(0);
    useEffect(() {
      final timer = Timer.periodic(const Duration(seconds: 1), (_) => tick.value++);
      return timer.cancel;
    }, const []);
    final info = useValueListenable(syncInfo);

    String vence = '';
    if (profile is RemoteProfileEntity) {
      final si = (profile as RemoteProfileEntity).subInfo;
      // Sin fecha de vencimiento el servidor manda 0 y la app lo guarda como año ~4900: no se muestra nada.
      if (si != null && si.expire.year > 2000 && si.expire.year < 2100) {
        final e = si.expire.toLocal();
        final fecha =
            '${e.day.toString().padLeft(2, '0')}/${e.month.toString().padLeft(2, '0')}/${e.year}';
        vence = si.isExpired ? 'Venció el $fecha' : 'Vence el $fecha (${si.remaining.inDays} días)';
      }
    }
    const blanco = Colors.white;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF00E5FF), Color(0xFF2979FF), Color(0xFF9C27FF), Color(0xFFFF2DAA)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .55), width: 1.5),
        boxShadow: [
          BoxShadow(color: const Color(0xFF00E5FF).withValues(alpha: .55), blurRadius: 22, offset: const Offset(-4, 4)),
          BoxShadow(color: const Color(0xFFFF2DAA).withValues(alpha: .45), blurRadius: 22, offset: const Offset(4, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.white.withValues(alpha: .25),
                child: const Icon(Icons.verified_user_rounded, color: blanco),
              ),
              const Gap(12),
              Expanded(
                child: Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: blanco,
                    shadows: const [Shadow(color: Colors.black38, blurRadius: 6)],
                  ),
                ),
              ),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: .28), foregroundColor: blanco),
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger(),
              ),
              IconButton(
                tooltip: 'Cambiar suscripción',
                icon: const Icon(Icons.delete_outline_rounded, color: blanco),
                onPressed: () async {
                  final ok = await ref
                      .read(dialogNotifierProvider.notifier)
                      .showConfirmation(
                        title: 'Cambiar suscripción',
                        message: 'Se quitará esta suscripción y podrás ingresar otra. ¿Continuar?',
                      );
                  if (ok) {
                    await ref.read(profilesNotifierProvider.notifier).deleteProfile(profile);
                  }
                },
              ),
            ],
          ),
          if (vence.isNotEmpty) ...[
            const Gap(4),
            Row(
              children: [
                const Icon(Icons.event_rounded, size: 16, color: blanco),
                const Gap(6),
                Text(vence, style: theme.textTheme.bodyMedium?.copyWith(color: blanco)),
              ],
            ),
          ],
          if (info != null) ...[
            const Gap(10),
            Row(
              children: [
                Icon(
                  info.ok ? Icons.sync_rounded : Icons.sync_problem_rounded,
                  size: 16,
                  color: info.ok ? blanco : Colors.yellowAccent,
                ),
                const Gap(6),
                Expanded(
                  child: Text(
                    'Revisada ${_hace(info.time)} · ${info.text}',
                    style: theme.textTheme.bodySmall?.copyWith(color: info.ok ? blanco : Colors.yellowAccent),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
