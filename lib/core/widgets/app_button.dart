import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../theme/app_colors.dart';

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;
  final bool outlined;
  final Color? color;

  const AppButton({
    super.key,
    required this.label,
    this.onTap,
    this.isLoading = false,
    this.outlined = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return OutlinedButton(
        onPressed: isLoading ? null : onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: BorderSide(color: color ?? AppColors.primary),
        ),
        child: _child(color ?? AppColors.primary),
      );
    }
    return ElevatedButton(
      onPressed: isLoading ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? AppColors.primary,
      ),
      child: _child(Colors.white),
    );
  }

  Widget _child(Color textColor) => isLoading
      ? const SizedBox(
          width: 20,
          height: 20,
          child: CupertinoActivityIndicator(color: Colors.white),
        )
      : Text(label, style: TextStyle(color: textColor));
}
