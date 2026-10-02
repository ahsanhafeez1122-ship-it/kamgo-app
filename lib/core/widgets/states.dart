import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// Friendly empty / error placeholder used inside lists and tabs.
class InfoState extends StatelessWidget {
  const InfoState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.greenSoft,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, color: AppColors.green, size: 34),
            ),
            const SizedBox(height: 18),
            Text(title, style: AppText.display(17), textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppText.body(14, color: AppColors.mutedDark, height: 1.45),
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 18),
              TextButton(
                onPressed: onAction,
                child: Text(
                  actionLabel!,
                  style: AppText.body(15, weight: FontWeight.w600, color: AppColors.green),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
