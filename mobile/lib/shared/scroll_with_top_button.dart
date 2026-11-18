import 'package:flutter/material.dart';

import 'package:pictoiq_mobile/core/config/app_colors.dart';

/// A scrolling [child] with a scroll bar that can be dragged and a round
/// "Back to top" button that appears once the page has been scrolled down.
/// [child] must use [controller] as its scroll controller.
class ScrollWithTopButton extends StatefulWidget {
  const ScrollWithTopButton({
    super.key,
    required this.controller,
    required this.child,
    this.enabled = true,
  });

  final ScrollController controller;
  final Widget child;

  /// False hides the button (for example while something is being made).
  final bool enabled;

  @override
  State<ScrollWithTopButton> createState() => _ScrollWithTopButtonState();
}

class _ScrollWithTopButtonState extends State<ScrollWithTopButton> {
  final ValueNotifier<bool> _far = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
  }

  @override
  void didUpdateWidget(ScrollWithTopButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_update);
      widget.controller.addListener(_update);
    }
  }

  void _update() {
    if (!widget.controller.hasClients) return;
    final far = widget.controller.offset > 400;
    if (far != _far.value) _far.value = far;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    _far.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Scrollbar(
        controller: widget.controller,
        interactive: true,
        thumbVisibility: true,
        thickness: 6,
        child: widget.child,
      ),
      Positioned(
        right: 16,
        bottom: 16,
        child: ValueListenableBuilder<bool>(
          valueListenable: _far,
          builder: (context, far, _) {
            final show = far && widget.enabled;
            return AnimatedSlide(
              duration: const Duration(milliseconds: 200),
              offset: show ? Offset.zero : const Offset(0, 2),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: show ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !show,
                  child: FloatingActionButton.small(
                    heroTag: null,
                    tooltip: 'Back to top',
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    onPressed: () => widget.controller.animateTo(
                      0,
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                    ),
                    child: const Icon(Icons.keyboard_arrow_up),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}
