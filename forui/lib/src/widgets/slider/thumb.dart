import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:meta/meta.dart';

import 'package:forui/forui.dart';
import 'package:forui/src/widgets/slider/inherited_controller.dart';
import 'package:forui/src/widgets/slider/inherited_data.dart';
import 'package:forui/src/widgets/slider/inherited_state.dart';

class _ShrinkIntent extends Intent {
  const _ShrinkIntent();
}

class _ExtendIntent extends Intent {
  const _ExtendIntent();
}

@internal
class Thumb extends StatefulWidget {
  final bool min;

  const Thumb({
    required this.min,
    super.key,
  });

  @override
  State<Thumb> createState() => _ThumbState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(FlagProperty('min', value: min, ifTrue: 'min', ifFalse: 'max'));
  }
}

class _ThumbState extends State<Thumb> with SingleTickerProviderStateMixin {
  late FSliderController _controller;
  late final FTooltipController _tooltip;
  late UniqueKey _key;
  MouseCursor _cursor = SystemMouseCursors.grab;
  ({double min, double max})? _origin;
  bool _gesture = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _tooltip = FTooltipController(vsync: this);
    _key = widget.min ? FSliderTooltipsController.min : FSliderTooltipsController.max;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = InheritedController.of(context);
    _controller.tooltips.add(_key, _tooltip);
  }

  @override
  Widget build(BuildContext context) {
    final thumbStyle = InheritedState.of(context).style.thumbStyle;
    final InheritedData(:style, :layout, :tooltipBuilder, :semanticValueFormatterCallback, :enabled) =
        InheritedData.of(context);

    String? increasedValue;
    if (_controller.selection.step(min: widget.min, extend: !widget.min) case final selection
        when _controller.selection != selection) {
      increasedValue = semanticValueFormatterCallback(_offset(selection));
    }

    String? decreasedValue;
    if (_controller.selection.step(min: widget.min, extend: widget.min) case final selection
        when _controller.selection != selection) {
      decreasedValue = semanticValueFormatterCallback(_offset(selection));
    }

    Widget thumb = Semantics(
      enabled: enabled,
      value: semanticValueFormatterCallback(_offset(_controller.selection)),
      increasedValue: increasedValue,
      decreasedValue: decreasedValue,
      child: FocusableActionDetector(
        shortcuts: _shortcuts(layout),
        actions: {
          _ExtendIntent: CallbackAction(onInvoke: (_) => _controller.step(min: widget.min, extend: true)),
          _ShrinkIntent: CallbackAction(onInvoke: (_) => _controller.step(min: widget.min, extend: false)),
        },
        enabled: enabled,
        mouseCursor: enabled ? _cursor : MouseCursor.defer,
        includeFocusSemantics: false,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: FFocusedOutline(
          style: thumbStyle.focusedOutlineStyle,
          focused: _focused,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: thumbStyle.color,
              border: Border.all(
                color: thumbStyle.borderColor,
                width: thumbStyle.borderWidth,
              ),
            ),
            child: SizedBox.square(
              dimension: style.thumbSize,
            ),
          ),
        ),
      ),
    );

    if (!enabled) {
      return thumb;
    }

    if (_controller.tooltips.enabled) {
      thumb = MouseRegion(
        onEnter: (_) => _controller.tooltips.show(_key),
        onExit: (_) {
          if (!_gesture) {
            _controller.tooltips.hide(_key);
          }
        },
        child: FTooltip(
          controller: _tooltip,
          tipAnchor: style.tooltipTipAnchor,
          childAnchor: style.tooltipThumbAnchor,
          tipBuilder: (context, style, _) => tooltipBuilder(style, _offset(_controller.selection)),
          longPress: false,
          hover: false,
          child: thumb,
        ),
      );
    }

    void down(TapDownDetails details) {
      setState(() => _cursor = SystemMouseCursors.grabbing);
      _gesture = true;
      _controller.tooltips.show(_key);
    }

    void up(TapUpDetails details) {
      setState(() => _cursor = SystemMouseCursors.grab);
      _gesture = false;
      _controller.tooltips.hide(_key);
    }

    void start(DragStartDetails details) {
      setState(() => _cursor = SystemMouseCursors.grabbing);
      _origin = null;
      _origin = _controller.selection.rawOffset;
      _gesture = true;
      _controller.tooltips.show(_key);
    }

    void end(DragEndDetails details) {
      setState(() => _cursor = SystemMouseCursors.grab);
      _origin = null;
      _gesture = false;
      _controller.tooltips.hide(_key);
    }

    if (layout.vertical) {
      return GestureDetector(
        onTapDown: down,
        onTapUp: up,
        onVerticalDragStart: start,
        onVerticalDragUpdate: _drag(_controller, style.thumbSize, layout),
        onVerticalDragEnd: end,
        child: thumb,
      );
    } else {
      return GestureDetector(
        onTapDown: down,
        onTapUp: up,
        onHorizontalDragStart: start,
        onHorizontalDragUpdate: _drag(_controller, style.thumbSize, layout),
        onHorizontalDragEnd: end,
        child: thumb,
      );
    }
  }

  double _offset(FSliderSelection selection) => widget.min ? selection.offset.min : selection.offset.max;

  Map<ShortcutActivator, Intent> _shortcuts(Layout layout) => switch ((layout, widget.min)) {
        (Layout.ltr, true) || (Layout.rtl, false) => const {
            SingleActivator(LogicalKeyboardKey.arrowLeft): _ExtendIntent(),
            SingleActivator(LogicalKeyboardKey.arrowRight): _ShrinkIntent(),
          },
        (Layout.ltr, false) || (Layout.rtl, true) => const {
            SingleActivator(LogicalKeyboardKey.arrowLeft): _ShrinkIntent(),
            SingleActivator(LogicalKeyboardKey.arrowRight): _ExtendIntent(),
          },
        (Layout.ttb, true) || (Layout.btt, false) => const {
            SingleActivator(LogicalKeyboardKey.arrowUp): _ExtendIntent(),
            SingleActivator(LogicalKeyboardKey.arrowDown): _ShrinkIntent(),
          },
        (Layout.ttb, false) || (Layout.btt, true) => const {
            SingleActivator(LogicalKeyboardKey.arrowUp): _ShrinkIntent(),
            SingleActivator(LogicalKeyboardKey.arrowDown): _ExtendIntent(),
          },
      };

  GestureDragUpdateCallback? _drag(FSliderController controller, double thumbSize, Layout layout) {
    if (controller.allowedInteraction == FSliderInteraction.tap) {
      return null;
    }

    final translate = layout.translateThumbDrag(thumbSize);

    void drag(DragUpdateDetails details) {
      final origin = widget.min ? _origin!.min : _origin!.max;
      controller.slide(origin + translate(details.localPosition), min: widget.min);
    }

    return drag;
  }

  @override
  void dispose() {
    _controller.tooltips.remove(_key);
    _tooltip.dispose();
    super.dispose();
  }
}

/// A slider thumb's style.
///
/// **Note**:
/// The thumb size can be configured inside [FSliderStyle] instead. This is due to an unfortunate limitation of the
/// implementation.
final class FSliderThumbStyle with Diagnosticable {
  /// The thumb's color.
  final Color color;

  /// The border's color.
  final Color borderColor;

  /// The border's width. Defaults to `2`.
  ///
  /// ## Contract
  /// Throws [AssertionError] if [borderWidth] is not positive.
  final double borderWidth;

  /// The thumb's focused outline style.
  final FFocusedOutlineStyle focusedOutlineStyle;

  /// Creates a [FSliderThumbStyle].
  FSliderThumbStyle({
    required this.color,
    required this.borderColor,
    required this.focusedOutlineStyle,
    this.borderWidth = 2,
  }) : assert(0 < borderWidth, 'The border width must be positive');

  /// Returns a copy of this [FSliderThumbStyle] but with the given fields replaced with the new values.
  @useResult
  FSliderThumbStyle copyWith({
    Color? color,
    Color? borderColor,
    double? borderWidth,
    FFocusedOutlineStyle? focusedOutlineStyle,
  }) =>
      FSliderThumbStyle(
        color: color ?? this.color,
        borderColor: borderColor ?? this.borderColor,
        borderWidth: borderWidth ?? this.borderWidth,
        focusedOutlineStyle: focusedOutlineStyle ?? this.focusedOutlineStyle,
      );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(ColorProperty('color', color))
      ..add(ColorProperty('borderColor', borderColor))
      ..add(DoubleProperty('borderWidth', borderWidth))
      ..add(DiagnosticsProperty('focusedOutlineStyle', focusedOutlineStyle));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FSliderThumbStyle &&
          runtimeType == other.runtimeType &&
          color == other.color &&
          borderColor == other.borderColor &&
          borderWidth == other.borderWidth &&
          focusedOutlineStyle == other.focusedOutlineStyle;

  @override
  int get hashCode => color.hashCode ^ borderColor.hashCode ^ borderWidth.hashCode ^ focusedOutlineStyle.hashCode;
}

@internal
extension Layouts on Layout {
  double Function(Offset) translateThumbDrag(double thumbSize) => switch (this) {
        Layout.ltr => (delta) => delta.dx - thumbSize / 2,
        Layout.rtl => (delta) => -delta.dx + thumbSize / 2,
        Layout.ttb => (delta) => delta.dy - thumbSize / 2,
        Layout.btt => (delta) => -delta.dy + thumbSize / 2,
      };
}
