import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../data/pays.dart';

/// Le pays pré-sélectionné à l'ouverture d'un formulaire.
///
/// ⚠️ **Décision produit, pas une déduction** : le pilote est algérien. Le
/// serveur applique exactement le même défaut quand le champ est absent
/// (`PAYS_PAR_DEFAUT`), pour qu'une version d'app antérieure au sélecteur
/// continue de créer des comptes justes.
final Pays kPaysParDefaut = paysParIso('DZ')!;

/// Le champ téléphone, indicatif compris — **un seul widget pour les trois
/// écrans qui saisissent un numéro** (auto-inscription, création par l'agent,
/// connexion commerçant).
///
/// Il était trois `TextFormField` identiques. Ajouter l'indicatif à trois
/// endroits aurait fait vivre la même règle en trois exemplaires, et c'est
/// celui qu'on oublie qui envoie un numéro sans son pays (règle #21).
///
/// ⚠️ **Ce qui part au serveur, c'est le code ISO — jamais l'indicatif.**
/// Le `+213` affiché n'est qu'une aide à la saisie : le serveur redérive
/// l'indicatif depuis le pays avec la **même** bibliothèque
/// (`libphonenumber-js`, voir `apps/backend/src/commercant/telephone.ts`).
/// Envoyer l'indicatif ferait exister deux sources pour la même donnée, et
/// c'est l'app qui aurait tort le jour d'une renumérotation nationale.
class TelephoneField extends StatelessWidget {
  const TelephoneField({
    super.key,
    required this.controller,
    required this.pays,
    required this.onPaysChanged,
    this.autofillHints,
    this.keyboardType = TextInputType.phone,
    this.onChanged,
    this.avecIndicatif = true,
  });

  final TextEditingController controller;
  final Pays pays;
  final ValueChanged<Pays> onPaysChanged;
  final Iterable<String>? autofillHints;

  /// L'écran de connexion garde `emailAddress` : un clavier numérique pur
  /// empêcherait de taper le « @ » qui fait basculer la saisie en mode admin.
  final TextInputType keyboardType;
  final ValueChanged<String>? onChanged;

  /// ⚠️ Faux quand la saisie n'est **plus** un numéro. Sur l'écran de
  /// connexion, ce même champ accepte une adresse e-mail pour ouvrir l'espace
  /// admin : afficher « +213 » devant une adresse e-mail annoncerait un format
  /// que le serveur n'attend pas, sur le seul écran où l'on ne peut pas se
  /// permettre d'égarer quelqu'un.
  final bool avecIndicatif;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return TextFormField(
      controller: controller,
      autofillHints: autofillHints,
      decoration: InputDecoration(
        labelText: l10n.telephoneLabel,
        // Le numéro d'exemple du pays choisi, plutôt qu'un « +213... » figé :
        // l'ancien indice montrait la forme internationale alors que le champ
        // attend la forme nationale, ce qui a produit deux écritures du même
        // numéro en base (voir la migration 1783890000000).
        hintText:
            (!avecIndicatif || pays.exemple.isEmpty) ? null : pays.exemple,
        prefixIcon: avecIndicatif
            ? _BoutonIndicatif(pays: pays, onChanged: onPaysChanged)
            : const Icon(Icons.alternate_email),
        // `prefixIcon` est contraint en largeur par défaut : sans cette borne,
        // « +262 » et le drapeau sont tronqués sur un petit écran.
        prefixIconConstraints:
            avecIndicatif ? const BoxConstraints(minWidth: 96) : null,
      ),
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: theme.textTheme.bodyLarge,
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? l10n.telephoneRequired : null,
    );
  }
}

class _BoutonIndicatif extends StatelessWidget {
  const _BoutonIndicatif({required this.pays, required this.onChanged});

  final Pays pays;
  final ValueChanged<Pays> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () async {
        final choisi = await showModalBottomSheet<Pays>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _ListePays(selection: pays),
        );
        if (choisi != null) onChanged(choisi);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(pays.drapeau, style: theme.textTheme.titleMedium),
            const SizedBox(width: 6),
            Text('+${pays.indicatif}', style: theme.textTheme.bodyLarge),
            Icon(
              Icons.arrow_drop_down,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// La liste des 245 pays, cherchable.
///
/// ⚠️ **Le tri se fait sur le nom localisé, à l'exécution.** Trier la table à
/// la génération aurait figé l'ordre du français : « الجزائر » ne tombe pas au
/// même endroit qu'« Algérie », et une liste triée dans une langue qu'on ne lit
/// pas se parcourt au hasard.
class _ListePays extends StatefulWidget {
  const _ListePays({required this.selection});

  final Pays selection;

  @override
  State<_ListePays> createState() => _ListePaysState();
}

class _ListePaysState extends State<_ListePays> {
  final _recherche = TextEditingController();

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  List<Pays> _resultats(String langue) {
    final terme = _recherche.text.trim().toLowerCase();
    final liste = kTousLesPays.where((pays) {
      if (terme.isEmpty) return true;
      // La recherche porte aussi sur l'indicatif : quelqu'un qui connaît
      // « 213 » n'a pas à deviner comment son téléphone écrit « Algérie ».
      return pays.nomPour(langue).toLowerCase().contains(terme) ||
          pays.indicatif.contains(terme) ||
          pays.iso.toLowerCase() == terme;
    }).toList()
      ..sort((a, b) => a.nomPour(langue).compareTo(b.nomPour(langue)));
    return liste;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final langue = Localizations.localeOf(context).languageCode;
    final resultats = _resultats(langue);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _recherche,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l10n.paysLabel,
                    hintText: l10n.paysRechercheHint,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Expanded(
                child: resultats.isEmpty
                    ? Center(
                        child: Text(
                          l10n.paysAucunResultat,
                          style: theme.textTheme.bodyMedium,
                        ),
                      )
                    : ListView.builder(
                        itemCount: resultats.length,
                        itemBuilder: (context, index) {
                          final pays = resultats[index];
                          return ListTile(
                            leading: Text(
                              pays.drapeau,
                              style: theme.textTheme.titleLarge,
                            ),
                            title: Text(pays.nomPour(langue)),
                            trailing: Text('+${pays.indicatif}'),
                            selected: pays.iso == widget.selection.iso,
                            onTap: () => Navigator.of(context).pop(pays),
                          );
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
