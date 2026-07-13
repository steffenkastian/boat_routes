import 'package:flutter/material.dart';

// Small telemetry/status overlay rendered on top of the map. Doubles as a
// button: tapping it jumps the camera back to the current position (or
// retries the location request if there's no fix yet). This is also the
// seam for future regatta info (distance/bearing to next mark) — add
// optional fields here rather than a separate overlay.
class HudOverlay extends StatelessWidget {
  const HudOverlay({
    this.speedKnots,
    this.headingDegrees,
    this.statusMessage,
    this.onTap,
    super.key,
  });

  final double? speedKnots;
  final double? headingDegrees;
  final String? statusMessage;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasTelemetry = speedKnots != null;

    if (!hasTelemetry && statusMessage == null) {
      return const SizedBox.shrink();
    }

    final content = hasTelemetry
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${speedKnots!.toStringAsFixed(1)} kn',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (headingDegrees != null)
                Text(
                  '${headingDegrees!.toStringAsFixed(0)}°',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
            ],
          )
        : Text(
            statusMessage!,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          );

    return Positioned(
      left: 8,
      top: 8,
      child: Material(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: content,
          ),
        ),
      ),
    );
  }
}
