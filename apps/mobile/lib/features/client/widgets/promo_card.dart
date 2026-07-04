import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../domain/models/promo.dart';

class PromoCard extends StatelessWidget {
  const PromoCard({
    super.key,
    required this.promo,
    required this.isFavorite,
    required this.onTap,
  });

  final Promo promo;
  final bool isFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'fr_DZ', symbol: 'DA', decimalDigits: 0);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (promo.photoUrl != null)
                    CachedNetworkImage(imageUrl: promo.photoUrl!, fit: BoxFit.cover)
                  else
                    Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                  if (isFavorite)
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: Icon(Icons.favorite, color: Colors.redAccent),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(promo.description, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        currency.format(promo.prixAvant),
                        style: const TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        currency.format(promo.prixApres),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
