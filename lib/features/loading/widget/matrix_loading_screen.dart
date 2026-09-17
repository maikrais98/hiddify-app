import 'package:flutter/material.dart';
import 'package:hiddify/features/loading/widget/matrix_rain.dart';
import 'package:hiddify/features/loading/widget/running_rabbit.dart';

class MatrixLoadingScreen extends StatelessWidget {
  const MatrixLoadingScreen({super.key, this.error, this.onRetry, this.rabbit, this.matrixFontFamily});

  final Object? error;
  final VoidCallback? onRetry;
  final Widget? rabbit;
  final String? matrixFontFamily;

  @override
  Widget build(BuildContext context) {
    final animationsEnabled = !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    final hasError = error != null;

    return Semantics(
      label: 'Запуск Woman in Red',
      container: true,
      child: Material(
        color: const Color(0xFF030306),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MatrixRain(animate: animationsEnabled, fontFamily: matrixFontFamily),
            const _CenterScrim(),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: hasError
                    ? _ErrorContent(onRetry: onRetry)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Следуй за белым кроликом',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.1,
                              shadows: [Shadow(blurRadius: 14)],
                            ),
                          ),
                          const SizedBox(height: 14),
                          rabbit ?? RunningRabbit(animate: animationsEnabled),
                        ],
                      ),
              ),
            ),
            const SafeArea(
              minimum: EdgeInsets.only(bottom: 22),
              child: Align(alignment: Alignment.bottomCenter, child: _BrandSignature()),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterScrim extends StatelessWidget {
  const _CenterScrim();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 0.68,
            colors: [
              const Color(0xFF030306).withValues(alpha: 0.88),
              const Color(0xFF030306).withValues(alpha: 0.18),
              Colors.transparent,
            ],
            stops: const [0, 0.54, 1],
          ),
        ),
      ),
    );
  }
}

class _ErrorContent extends StatelessWidget {
  const _ErrorContent({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Не удалось запустить приложение',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 18),
        FilledButton.tonal(
          onPressed: onRetry,
          style: FilledButton.styleFrom(foregroundColor: Colors.white, backgroundColor: const Color(0xFF8E092C)),
          child: const Text('Повторить'),
        ),
      ],
    );
  }
}

class _BrandSignature extends StatelessWidget {
  const _BrandSignature();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: const Color(0xB8030306), borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/source/woman_in_red_splash.png', width: 24, height: 24),
            const SizedBox(width: 7),
            const Text(
              'Woman in Red',
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.25),
            ),
          ],
        ),
      ),
    );
  }
}
