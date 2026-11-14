import 'package:flutter/material.dart';

import 'package:pictoiq_mobile/core/config/app_colors.dart';

/// An app bar title with the screen's own icon in a white rounded square,
/// for example the photo-stack icon for Best Moments.
class AppBarTitle extends StatelessWidget {
  const AppBarTitle({super.key, required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 22, color: AppColors.primary),
      ),
      const SizedBox(width: 10),
      Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
    ],
  );
}
