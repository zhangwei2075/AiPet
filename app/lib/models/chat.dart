import 'package:flutter/foundation.dart';

import 'pet.dart';

enum ChatRole { user, pet }

@immutable
class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    required this.at,
    this.mood = PetMood.talk,
  });

  final ChatRole role;
  final String text;
  final DateTime at;
  final PetMood mood;

  Map<String, String> toJson() => {
        'role': role.name,
        'text': text,
        'at': at.toIso8601String(),
        'mood': mood.name,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] == 'user' ? ChatRole.user : ChatRole.pet,
        text: json['text']?.toString() ?? '',
        at: DateTime.tryParse(json['at']?.toString() ?? '') ?? DateTime.now(),
        mood: PetMoodParsing.fromKey(json['mood']?.toString()),
      );
}

@immutable
class PetReply {
  const PetReply(this.text, [this.mood = PetMood.happy]);

  final String text;
  final PetMood mood;
}
