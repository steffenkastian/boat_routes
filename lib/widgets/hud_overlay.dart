import 'package:flutter/material.dart';

// Small telemetry/status overlay rendered on top of the map. This is the
// seam for future regatta info (distance/bearing to next mark) — add
// optional fields here rather than a separate overlay.
class HudOverlay extends StatelessWidget {
  const HudOverlay({
    this.speedKnots,
    this.headingDegrees,
    this.statusMessage,
    this.onJumpToLocation,
    super.key,
  });

  final double? speedKnots;
  final double? headingDegrees;
  final String? statusMessage;
  final VoidCallback? onJumpToLocation;

  @override
  Widget build(BuildContext context) {
    final hasTelemetry = speedKnots != null;

    if (!hasTelemetry && statusMessage == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 8,
      top: 8,
      child: Card(
        color: Colors.black.withValues(alpha: 0.6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              hasTelemetry
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
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    )
                  : Text(
                      statusMessage!,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
              if (onJumpToLocation != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.my_location, color: Colors.white),
                  tooltip: 'Zu meinem Standort springen',
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: onJumpToLocation,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
