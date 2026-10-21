import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/profile/add/widgets/widgets.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Solo se puede agregar una suscripción por enlace (sin QR, portapapeles,
/// configuración manual ni perfiles gratis).
class AddProfileModal extends HookConsumerWidget {
  const AddProfileModal({super.key, this.url});
  final String? url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isLoading = ref.watch(addProfileNotifierProvider).isLoading;
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final urlController = useTextEditingController(text: url ?? '');

    ref.listen(addProfileNotifierProvider, (previous, next) {
      if (next case AsyncData(value: final _?)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted && context.canPop()) context.pop();
        });
      }
    });

    if (isLoading) return const SafeArea(child: ProfileLoading());

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Agregar suscripción', style: theme.textTheme.headlineSmall),
              const Gap(16),
              TextFormField(
                controller: urlController,
                maxLines: 1,
                decoration: const InputDecoration(
                  labelText: 'Enlace de suscripción',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty || !isUrl(value.trim())) ? 'Enlace no válido' : null,
              ),
              const Gap(16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  child: const Text('Agregar'),
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      await ref
                          .read(addProfileNotifierProvider.notifier)
                          .addManual(
                            url: urlController.text.trim(),
                            userOverride: UserOverride(
                              name: null,
                              isAutoUpdateDisable: false,
                              updateInterval: null,
                            ),
                          );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
