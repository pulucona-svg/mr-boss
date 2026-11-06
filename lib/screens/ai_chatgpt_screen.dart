import 'package:flutter/material.dart';
import '../models/ai_provider.dart';
import 'ai_assistant_screen.dart';

/// Backward-compatible wrapper for [AiAssistantScreen] configured with [AiProvider.chatGpt].
class AiChatGptScreen extends StatelessWidget {
  final String materialTitle;
  final String? initialPrompt;

  const AiChatGptScreen({
    super.key,
    required this.materialTitle,
    this.initialPrompt,
  });

  @override
  Widget build(BuildContext context) {
    return AiAssistantScreen(
      provider: AiProviderConfig.getConfig(AiProvider.chatGpt),
      materialTitle: materialTitle,
      initialPrompt: initialPrompt,
    );
  }
}
