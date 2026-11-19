import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import 'wifi_share_protocol.dart';

/// Escáner de código QR para conectar rápido a otro teléfono en "Compartir
/// por Wi-Fi" sin escribir el PIN ni la dirección IP.
class WifiShareQrScannerScreen extends StatefulWidget {
  const WifiShareQrScannerScreen({super.key});

  @override
  State<WifiShareQrScannerScreen> createState() =>
      _WifiShareQrScannerScreenState();
}

class _WifiShareQrScannerScreenState extends State<WifiShareQrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  bool _done = false;
  bool _torchOn = false;
  String? _notice;
  Timer? _noticeTimer;

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final payload = ShareQrPayload.tryParse(raw);
      if (payload != null) {
        _done = true;
        HapticFeedback.mediumImpact();
        unawaited(_controller.stop());
        if (mounted) Navigator.of(context).pop(payload);
        return;
      }
      _showNotice('Este código QR no es de QvaTube.');
    }
  }

  void _showNotice(String text) {
    _noticeTimer?.cancel();
    if (mounted) setState(() => _notice = text);
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.45),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
        ),
        title: const Text(
          'Escanear código QR',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: _torchOn ? 'Apagar linterna' : 'Encender linterna',
            onPressed: _toggleTorch,
            icon: Icon(
              _torchOn ? LucideIcons.flashlightOff : LucideIcons.flashlight,
              color: _torchOn ? AppColors.accent : Colors.white,
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraErrorView(error: error),
          ),
          // Marco de enfoque central.
          IgnorePointer(child: CustomPaint(painter: _ScannerOverlayPainter())),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_notice != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(AppRadii.md),
                        ),
                        child: Text(
                          _notice!,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Text(
                        'Apunta al código QR que se muestra en el otro teléfono.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body(
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.cameraOff,
              size: 48,
              color: AppColors.accent,
            ),
            const SizedBox(height: 16),
            Text(
              denied
                  ? 'Permiso de cámara denegado'
                  : 'No se pudo abrir la cámara',
              textAlign: TextAlign.center,
              style: AppTextStyles.body(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              denied
                  ? 'Activa el permiso de cámara en los ajustes del teléfono '
                        'para escanear el código QR, o conéctate usando el PIN.'
                  : 'Comprueba que ninguna otra app esté usando la cámara o '
                        'conéctate usando el PIN.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Oscurece el exterior y dibuja las esquinas del recuadro de escaneo.
class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final boxSize = (size.shortestSide * 0.66).clamp(200.0, 290.0);
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 20),
      width: boxSize,
      height: boxSize,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(18));

    final bgPath = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      bgPath,
      Paint()..color = Colors.black.withValues(alpha: 0.58),
    );

    final cornerPaint = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    const len = 28.0;
    const r = 18.0;

    // Esquina superior izquierda
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.top + len)
        ..lineTo(rect.left, rect.top + r)
        ..quadraticBezierTo(rect.left, rect.top, rect.left + r, rect.top)
        ..lineTo(rect.left + len, rect.top),
      cornerPaint,
    );
    // Esquina superior derecha
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - len, rect.top)
        ..lineTo(rect.right - r, rect.top)
        ..quadraticBezierTo(rect.right, rect.top, rect.right, rect.top + r)
        ..lineTo(rect.right, rect.top + len),
      cornerPaint,
    );
    // Esquina inferior izquierda
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.bottom - len)
        ..lineTo(rect.left, rect.bottom - r)
        ..quadraticBezierTo(rect.left, rect.bottom, rect.left + r, rect.bottom)
        ..lineTo(rect.left + len, rect.bottom),
      cornerPaint,
    );
    // Esquina inferior derecha
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - len, rect.bottom)
        ..lineTo(rect.right - r, rect.bottom)
        ..quadraticBezierTo(
          rect.right,
          rect.bottom,
          rect.right,
          rect.bottom - r,
        )
        ..lineTo(rect.right, rect.bottom - len),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
