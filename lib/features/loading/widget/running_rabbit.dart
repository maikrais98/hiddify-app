import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class RunningRabbit extends StatelessWidget {
  const RunningRabbit({super.key, this.animate = true});

  final bool animate;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: 72,
        height: 52,
        child: Lottie.asset(
          'assets/animations/rabbit_running.json',
          animate: animate,
          repeat: animate,
          fit: BoxFit.contain,
          delegates: LottieDelegates(
            values: [
              ValueDelegate.colorFilter(const ['**'], value: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
            ],
          ),
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.cruelty_free_rounded, size: 42, color: Colors.white),
        ),
      ),
    );
  }
}
