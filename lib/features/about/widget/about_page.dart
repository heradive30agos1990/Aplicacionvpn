import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AboutPage extends HookConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final appInfo = ref.watch(appInfoProvider).requireValue;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(t.pages.about.title)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220, maxHeight: 220),
                child: Image.asset(
                  'assets/images/source/ic_launcher_border.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const Gap(20),
              Text('Internet Ilimitado', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              const Gap(6),
              Text('${t.common.version} ${appInfo.presentVersion}', style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}
