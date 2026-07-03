import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/api_exception.dart';
import '../../../domain/enums/categorie.dart';
import '../../client/providers/commune_providers.dart';
import '../../shared/widgets/category_dropdown.dart';
import '../../../providers/core_providers.dart';

/// Auto-inscription (specs §3.2, voie 1) — sans passage agent requis.
class CommercantRegisterScreen extends ConsumerStatefulWidget {
  const CommercantRegisterScreen({super.key});

  @override
  ConsumerState<CommercantRegisterScreen> createState() => _CommercantRegisterScreenState();
}

class _CommercantRegisterScreenState extends ConsumerState<CommercantRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _telephoneController = TextEditingController();
  final _nomController = TextEditingController();
  final _adresseController = TextEditingController();
  Categorie? _categorie;
  String? _communeId;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _telephoneController.dispose();
    _nomController.dispose();
    _adresseController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _communeId == null) {
      setState(() => _error = _communeId == null ? 'Commune requise' : null);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ref.read(commercantApiProvider).register(
            telephone: _telephoneController.text.trim(),
            nom: _nomController.text.trim(),
            adresse: _adresseController.text.trim(),
            categorie: _categorie!,
            communeId: _communeId!,
          );
      if (mounted) {
        context.push(
          '/commercant/otp',
          extra: {'telephone': _telephoneController.text.trim(), 'purpose': 'inscription'},
        );
      }
    } catch (error) {
      setState(() => _error = extractApiErrorMessage(error, fallback: 'Inscription impossible.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final communesAsync = ref.watch(communeListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Créer un compte commerçant')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _telephoneController,
                decoration: const InputDecoration(labelText: 'Téléphone', hintText: '+213...'),
                keyboardType: TextInputType.phone,
                validator: (v) => (v == null || v.isEmpty) ? 'Téléphone requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nomController,
                decoration: const InputDecoration(labelText: 'Nom du commerce'),
                validator: (v) => (v == null || v.isEmpty) ? 'Nom requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _adresseController,
                decoration: const InputDecoration(labelText: 'Adresse'),
                validator: (v) => (v == null || v.isEmpty) ? 'Adresse requise' : null,
              ),
              const SizedBox(height: 12),
              CategoryDropdown(value: _categorie, onChanged: (v) => setState(() => _categorie = v)),
              const SizedBox(height: 12),
              communesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text('Erreur communes : $error'),
                data: (communes) => DropdownButtonFormField<String>(
                  value: _communeId,
                  decoration: const InputDecoration(labelText: 'Commune'),
                  items: [
                    for (final commune in communes)
                      DropdownMenuItem(value: commune.id, child: Text(commune.nom)),
                  ],
                  onChanged: (v) => setState(() => _communeId = v),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("S'inscrire"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
