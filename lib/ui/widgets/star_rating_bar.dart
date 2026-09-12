import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StarRatingBar extends StatelessWidget {
  final int rating;
  final Function(int rating)? onRatingChanged;
  final double size;
  final bool readOnly;

  const StarRatingBar({
    super.key,
    required this.rating,
    this.onRatingChanged,
    this.size = 24.0,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starNumber = index + 1;
        final isFilled = starNumber <= rating;

        return GestureDetector(
          onTap: readOnly || onRatingChanged == null
              ? null
              : () {
                  // If tapping already active star, can reset to 0 or set to starNumber
                  if (rating == starNumber) {
                    onRatingChanged!(0);
                  } else {
                    onRatingChanged!(starNumber);
                  }
                },
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: size * 0.08),
            child: Icon(
              isFilled ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: isFilled ? AppTheme.starColor : AppTheme.textSecondary.withOpacity(0.4),
            ),
          ),
        );
      }),
    );
  }
}
