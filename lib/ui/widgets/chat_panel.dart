
import 'package:flutter/material.dart';
import 'feedback_bottom_sheet.dart';
import 'tool_call_message.dart';

/// Chat message in the conversation (text or tool call)
class ChatMessage {
  final String id; // Unique ID (eventId for linking to invocations)
  final String role; // 'user', 'assistant', or 'tool'
  final String content; // Message text (empty for tool calls)
  final DateTime timestamp; // When message was created
  final bool feedbackGiven; // Has user rated this message?

  // Tool call fields (only for role == 'tool')
  final String? toolName;
  final bool? toolSuccess;
  final Map<String, dynamic>? toolResult;
  final String? toolError;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.feedbackGiven = false,
    this.toolName,
    this.toolSuccess,
    this.toolResult,
    this.toolError,
  });

  ChatMessage copyWith({
    String? id,
    String? role,
    String? content,
    DateTime? timestamp,
    bool? feedbackGiven,
    String? toolName,
    bool? toolSuccess,
    Map<String, dynamic>? toolResult,
    String? toolError,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      feedbackGiven: feedbackGiven ?? this.feedbackGiven,
      toolName: toolName ?? this.toolName,
      toolSuccess: toolSuccess ?? this.toolSuccess,
      toolResult: toolResult ?? this.toolResult,
      toolError: toolError ?? this.toolError,
    );
  }

  bool get isToolCall => role == 'tool';
}

class ChatPanel extends StatelessWidget {
  final List<ChatMessage> messages;
  final Function(String messageId, bool isPositive)? onMessageFeedback;
  final VoidCallback? onMicrophonePressed;
  final bool isListening;

  const ChatPanel({
    Key? key,
    required this.messages,
    this.onMessageFeedback,
    this.onMicrophonePressed,
    this.isListening = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Conversation',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                if (isListening)
                  Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Listening...',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Text(
                      'Start a conversation',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) => Semantics(
                      label: 'chat_panel.message_$index',
                      child: _buildMessage(
                        context,
                        messages[index],
                      ),
                    ),
                  ),
          ),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Semantics(
                  label: 'chat_panel.mic_button',
                  button: true,
                  child: FloatingActionButton(
                    onPressed: onMicrophonePressed,
                    backgroundColor: isListening ? Colors.red : Colors.blue,
                    child: Icon(
                      isListening ? Icons.stop : Icons.mic,
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(BuildContext context, ChatMessage message) {
    if (message.isToolCall) {
      return ToolCallMessage(
        toolName: message.toolName!,
        success: message.toolSuccess!,
        result: message.toolResult,
        error: message.toolError,
      );
    }

    final isUser = message.role == 'user';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: !isUser && !message.feedbackGiven
            ? () => _handleMessageFeedback(context, message)
            : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: isUser ? Colors.blue.shade100 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isUser ? Colors.blue.shade200 : Colors.grey.shade300,
            ),
          ),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                isUser ? 'You' : 'Assistant',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                message.content,
                style: const TextStyle(fontSize: 14),
              ),

              if (!isUser) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.feedbackGiven)
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green.shade700,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Feedback recorded',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'Long-press to rate',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade500,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleMessageFeedback(
    BuildContext context,
    ChatMessage message,
  ) async {
    if (onMessageFeedback == null) return;

    final result = await showFeedbackBottomSheet(
      context,
      title: 'Rate Response',
      description: 'Was this response helpful and accurate?',
    );

    if (result != null) {
      onMessageFeedback!(message.id, result);
    }
  }
}
