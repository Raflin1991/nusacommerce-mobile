import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Lifecycle-safe wrapper around [MobileScanner] that explicitly creates,
/// stops, and disposes its [MobileScannerController] so camera streams and
/// browser WebCodecs VideoFrames are cleanly released when dialogs/sheets close.
class NusaBarcodeScannerView extends StatefulWidget {
  final void Function(String rawValue) onDetect;
  final bool stopOnFirstDetection;

  const NusaBarcodeScannerView({
    super.key,
    required this.onDetect,
    this.stopOnFirstDetection = true,
  });

  @override
  State<NusaBarcodeScannerView> createState() => _NusaBarcodeScannerViewState();
}

class _NusaBarcodeScannerViewState extends State<NusaBarcodeScannerView> {
  late final MobileScannerController _controller;
  bool _handled = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(autoStart: true);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_stopAndDispose());
    super.dispose();
  }

  Future<void> _stopAndDispose() async {
    try {
      await _controller.stop();
    } catch (_) {}
    try {
      await _controller.dispose();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return MobileScanner(
      controller: _controller,
      onDetect: (capture) {
        if (_disposed || (widget.stopOnFirstDetection && _handled)) return;
        final barcodes = capture.barcodes;
        if (barcodes.isEmpty) return;
        final rawValue = barcodes.first.rawValue;
        if (rawValue == null || rawValue.trim().isEmpty) return;

        if (widget.stopOnFirstDetection) {
          _handled = true;
          unawaited(_controller.stop().catchError((_) {}));
        }
        widget.onDetect(rawValue);
      },
    );
  }
}
