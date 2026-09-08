import 'package:flutter/material.dart';

/// Toggle switch for enabling/disabling emergency protection.
class ProtectionToggle extends StatelessWidget {
  final bool isOn;
  final ValueChanged<bool> onChanged;

  const ProtectionToggle({
    super.key,
    required this.isOn,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!isOn),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: isOn
              ? Colors.green.withValues(alpha: 0.15)
              : Colors.grey.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isOn
                ? Colors.green.withValues(alpha: 0.4)
                : Colors.grey.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isOn ? Icons.shield_rounded : Icons.shield_outlined,
              color: isOn ? Colors.green : Colors.grey,
              size: 24,
            ),
            const SizedBox(width: 10),
            Text(
              isOn ? 'Protection: ON' : 'Protection: OFF',
              style: TextStyle(
                color: isOn ? Colors.green : Colors.grey,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
