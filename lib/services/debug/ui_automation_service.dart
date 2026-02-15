import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class UiAutomationService {
  static final UiAutomationService instance = UiAutomationService._();
  UiAutomationService._();

  int _pointerCounter = 9000; // Start high to avoid conflicts with real pointers

  /// Tap a widget by its semantics label.
  /// Dispatches PointerDown + PointerUp at the widget's center.
  Future<Map<String, dynamic>> tap(String target) async {
    final node = _findNodeByLabel(target);
    if (node == null) {
      return {'success': false, 'error': 'Widget not found: $target', 'available': _listLabels()};
    }

    final center = _getNodeGlobalRect(node)?.center;
    if (center == null) {
      return {'success': false, 'error': 'Could not determine position for: $target'};
    }

    _dispatchTap(center);

    return {
      'success': true,
      'target': target,
      'action': 'tap',
      'position': {'x': center.dx, 'y': center.dy},
    };
  }

  /// Long-press a widget by its semantics label.
  /// Dispatches PointerDown, waits 600ms, then PointerUp.
  Future<Map<String, dynamic>> longPress(String target) async {
    final node = _findNodeByLabel(target);
    if (node == null) {
      return {'success': false, 'error': 'Widget not found: $target', 'available': _listLabels()};
    }

    final center = _getNodeGlobalRect(node)?.center;
    if (center == null) {
      return {'success': false, 'error': 'Could not determine position for: $target'};
    }

    final pointer = _pointerCounter++;
    final now = Duration(milliseconds: DateTime.now().millisecondsSinceEpoch);

    _dispatchPointerEvent(PointerDownEvent(
      pointer: pointer,
      position: center,
      timeStamp: now,
      kind: PointerDeviceKind.touch,
    ));

    // Wait for long press recognition (600ms is Flutter's default)
    await Future<void>.delayed(const Duration(milliseconds: 650));

    _dispatchPointerEvent(PointerUpEvent(
      pointer: pointer,
      position: center,
      timeStamp: Duration(milliseconds: DateTime.now().millisecondsSinceEpoch),
      kind: PointerDeviceKind.touch,
    ));

    return {
      'success': true,
      'target': target,
      'action': 'long_press',
      'position': {'x': center.dx, 'y': center.dy},
    };
  }

  /// Type text into a TextField by its semantics label.
  /// Taps to focus, then finds the focused EditableTextState and sets its value.
  Future<Map<String, dynamic>> type(String target, String text, {bool submit = false}) async {
    final node = _findNodeByLabel(target);
    if (node == null) {
      return {'success': false, 'error': 'Widget not found: $target', 'available': _listLabels()};
    }

    // Tap to focus the field
    final center = _getNodeGlobalRect(node)?.center;
    if (center != null) {
      _dispatchTap(center);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    final editableState = _findFocusedEditableTextState();
    if (editableState == null) {
      return {'success': false, 'error': 'No editable text field found for: $target'};
    }

    editableState.updateEditingValue(TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ));

    if (submit) {
      editableState.performAction(TextInputAction.done);
    }

    return {
      'success': true,
      'target': target,
      'action': 'type',
      'text': text,
      'submitted': submit,
    };
  }

  /// Slide a slider to a specific value (0.0–1.0).
  /// Reads current value from semantics, drags from current thumb to target.
  Future<Map<String, dynamic>> slide(String target, double value) async {
    final node = _findNodeByLabel(target);
    if (node == null) {
      return {'success': false, 'error': 'Widget not found: $target', 'available': _listLabels()};
    }

    final rect = _getNodeGlobalRect(node);
    if (rect == null) {
      return {'success': false, 'error': 'Could not determine bounds for: $target'};
    }

    final currentValue = _parseSliderValue(node);
    final startX = rect.left + (rect.width * currentValue);
    final startY = rect.center.dy;
    final targetX = rect.left + (rect.width * value.clamp(0.0, 1.0));

    final pointer = _pointerCounter++;
    final now = Duration(milliseconds: DateTime.now().millisecondsSinceEpoch);

    _dispatchPointerEvent(PointerDownEvent(
      pointer: pointer,
      position: Offset(startX, startY),
      timeStamp: now,
      kind: PointerDeviceKind.touch,
    ));

    // Move to target position in steps, yielding between each
    const steps = 10;
    for (int i = 1; i <= steps; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      final t = i / steps;
      final x = startX + (targetX - startX) * t;
      _dispatchPointerEvent(PointerMoveEvent(
        pointer: pointer,
        position: Offset(x, startY),
        delta: Offset((targetX - startX) / steps, 0),
        timeStamp: Duration(milliseconds: now.inMilliseconds + (i * 16)),
        kind: PointerDeviceKind.touch,
      ));
    }

    _dispatchPointerEvent(PointerUpEvent(
      pointer: pointer,
      position: Offset(targetX, startY),
      timeStamp: Duration(milliseconds: now.inMilliseconds + (steps * 16) + 16),
      kind: PointerDeviceKind.touch,
    ));

    return {
      'success': true,
      'target': target,
      'action': 'slide',
      'value': value,
      'previousValue': currentValue,
      'position': {'x': targetX, 'y': startY},
    };
  }

  /// Get the full semantics tree as JSON.
  Map<String, dynamic> getTree() {
    final rootNode = _getRootSemanticsNode();
    if (rootNode == null) {
      return {'error': 'Semantics tree not available'};
    }
    return _nodeToJson(rootNode);
  }

  /// Find all semantics nodes matching a label prefix.
  List<Map<String, dynamic>> find(String labelPrefix) {
    final results = <Map<String, dynamic>>[];
    final root = _getRootSemanticsNode();
    if (root == null) return results;

    _walkTree(root, (node) {
      final label = node.label;
      if (label.isNotEmpty && label.startsWith(labelPrefix)) {
        final globalRect = _getNodeGlobalRect(node);
        if (globalRect != null) {
          results.add({
            'label': label,
            'rect': {
              'left': globalRect.left,
              'top': globalRect.top,
              'width': globalRect.width,
              'height': globalRect.height,
            },
            'center': {'x': globalRect.center.dx, 'y': globalRect.center.dy},
            'actions': _getNodeActions(node),
            'hasChildren': node.childrenCount > 0,
          });
        }
      }
    });
    return results;
  }

  // ── Private helpers ──

  SemanticsNode? _getRootSemanticsNode() {
    try {
      final binding = WidgetsBinding.instance;
      binding.ensureSemantics();

      final renderView = binding.renderViews.firstOrNull;
      if (renderView == null) return null;

      final owner = renderView.owner?.semanticsOwner;
      return owner?.rootSemanticsNode;
    } catch (e) {
      return null;
    }
  }

  SemanticsNode? _findNodeByLabel(String label) {
    final root = _getRootSemanticsNode();
    if (root == null) return null;

    SemanticsNode? result;
    _walkTree(root, (node) {
      if (result != null) return;
      if (node.label == label) {
        result = node;
      }
    });
    return result;
  }

  void _walkTree(SemanticsNode node, void Function(SemanticsNode) visitor) {
    visitor(node);
    node.visitChildren((child) {
      _walkTree(child, visitor);
      return true;
    });
  }

  /// Compute global rect by accumulating transforms up the ancestor chain.
  Rect? _getNodeGlobalRect(SemanticsNode node) {
    try {
      var combined = Matrix4.identity();
      SemanticsNode? current = node;
      while (current != null) {
        final transform = current.transform;
        if (transform != null) {
          combined = transform.multiplied(combined);
        }
        current = current.parent;
      }
      return MatrixUtils.transformRect(combined, node.rect);
    } catch (e) {
      return null;
    }
  }

  /// Parse slider's current value (0.0–1.0) from its semantics node.
  double _parseSliderValue(SemanticsNode node) {
    final valueText = node.value;
    if (valueText.isNotEmpty) {
      final parsed = double.tryParse(valueText.replaceAll('%', ''));
      if (parsed != null) {
        // If it looks like a percentage, normalize
        if (valueText.contains('%')) return (parsed / 100).clamp(0.0, 1.0);
        // If it's already 0-1 range
        if (parsed >= 0 && parsed <= 1) return parsed;
        // If it's 0-100 range
        if (parsed > 1 && parsed <= 100) return (parsed / 100).clamp(0.0, 1.0);
      }
    }
    return 0.5; // Default to center if can't determine
  }

  void _dispatchTap(Offset position) {
    final pointer = _pointerCounter++;
    final now = Duration(milliseconds: DateTime.now().millisecondsSinceEpoch);

    _dispatchPointerEvent(PointerDownEvent(
      pointer: pointer,
      position: position,
      timeStamp: now,
      kind: PointerDeviceKind.touch,
    ));

    _dispatchPointerEvent(PointerUpEvent(
      pointer: pointer,
      position: position,
      timeStamp: Duration(milliseconds: now.inMilliseconds + 16),
      kind: PointerDeviceKind.touch,
    ));
  }

  void _dispatchPointerEvent(PointerEvent event) {
    GestureBinding.instance.handlePointerEvent(event);
  }

  /// Find the EditableTextState that currently has focus.
  EditableTextState? _findFocusedEditableTextState() {
    try {
      final focusNode = FocusManager.instance.primaryFocus;
      if (focusNode == null) return null;

      final context = focusNode.context;
      if (context == null || context is! Element) return null;

      EditableTextState? found;
      void visitor(Element element) {
        if (found != null) return;
        if (element is StatefulElement && element.state is EditableTextState) {
          found = element.state as EditableTextState;
          return;
        }
        element.visitChildren(visitor);
      }

      visitor(context);
      return found;
    } catch (e) {
      return null;
    }
  }

  List<String> _listLabels() {
    final labels = <String>[];
    final root = _getRootSemanticsNode();
    if (root == null) return labels;

    _walkTree(root, (node) {
      if (node.label.isNotEmpty) {
        labels.add(node.label);
      }
    });
    return labels;
  }

  List<String> _getNodeActions(SemanticsNode node) {
    final actions = <String>[];
    final data = node.getSemanticsData();
    if (data.hasAction(ui.SemanticsAction.tap)) actions.add('tap');
    if (data.hasAction(ui.SemanticsAction.longPress)) actions.add('long_press');
    if (data.hasAction(ui.SemanticsAction.scrollLeft)) actions.add('scroll_left');
    if (data.hasAction(ui.SemanticsAction.scrollRight)) actions.add('scroll_right');
    if (data.hasAction(ui.SemanticsAction.scrollUp)) actions.add('scroll_up');
    if (data.hasAction(ui.SemanticsAction.scrollDown)) actions.add('scroll_down');
    if (data.hasAction(ui.SemanticsAction.increase)) actions.add('increase');
    if (data.hasAction(ui.SemanticsAction.decrease)) actions.add('decrease');
    if (data.hasAction(ui.SemanticsAction.setText)) actions.add('set_text');
    return actions;
  }

  Map<String, dynamic> _nodeToJson(SemanticsNode node) {
    final data = node.getSemanticsData();
    final children = <Map<String, dynamic>>[];
    node.visitChildren((child) {
      children.add(_nodeToJson(child));
      return true;
    });

    final globalRect = _getNodeGlobalRect(node);
    final result = <String, dynamic>{
      'id': node.id,
    };

    if (node.label.isNotEmpty) result['label'] = node.label;
    if (node.value.isNotEmpty) result['value'] = node.value;
    if (node.hint.isNotEmpty) result['hint'] = node.hint;

    final actions = _getNodeActions(node);
    if (actions.isNotEmpty) result['actions'] = actions;

    final flags = data.flagsCollection;
    if (flags.isButton) result['isButton'] = true;
    if (flags.isTextField) result['isTextField'] = true;
    if (flags.isSlider) result['isSlider'] = true;
    if (flags.isToggled != ui.Tristate.none) result['isToggled'] = flags.isToggled == ui.Tristate.isTrue;
    if (flags.isEnabled != ui.Tristate.none) result['isEnabled'] = flags.isEnabled == ui.Tristate.isTrue;
    if (flags.isFocused != ui.Tristate.none) result['isFocused'] = flags.isFocused == ui.Tristate.isTrue;

    if (globalRect != null) {
      result['rect'] = {
        'left': globalRect.left.round(),
        'top': globalRect.top.round(),
        'width': globalRect.width.round(),
        'height': globalRect.height.round(),
      };
    }

    if (children.isNotEmpty) result['children'] = children;

    return result;
  }
}
