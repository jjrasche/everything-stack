/// Compact widget showing a tool call execution (success or failure).
///
/// Design:
/// - Compact height (~40px collapsed)
/// - Icon + tool name + status indicator
/// - Tap to expand/collapse full result
/// - Different colors for success vs failure

import 'package:flutter/material.dart';
import 'dart:convert';

class ToolCallMessage extends StatefulWidget {
  final String toolName;
  final bool success;
  final Map<String, dynamic>? result;
  final String? error;

  const ToolCallMessage({
    super.key,
    required this.toolName,
    required this.success,
    this.result,
    this.error,
  });

  @override
  State<ToolCallMessage> createState() => _ToolCallMessageState();
}

class _ToolCallMessageState extends State<ToolCallMessage> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Material(
        color: widget.success
            ? Colors.green.shade50
            : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Collapsed view: icon + tool name + status
                Row(
                  children: [
                    Icon(
                      widget.success ? Icons.check_circle : Icons.error,
                      color: widget.success ? Colors.green : Colors.red,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.toolName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: widget.success
                              ? Colors.green.shade900
                              : Colors.red.shade900,
                        ),
                      ),
                    ),
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: Colors.grey.shade600,
                    ),
                  ],
                ),

                // Expanded view: full result or error
                if (_isExpanded) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: widget.success
                            ? Colors.green.shade200
                            : Colors.red.shade200,
                      ),
                    ),
                    child: SelectableText(
                      widget.success
                          ? _formatResult(widget.result)
                          : widget.error ?? 'Unknown error',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatResult(Map<String, dynamic>? result) {
    if (result == null) return 'Success (no data)';
    try {
      // Pretty-print JSON
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(result);
    } catch (e) {
      return result.toString();
    }
  }
}
