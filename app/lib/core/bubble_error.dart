import 'package:supabase_flutter/supabase_flutter.dart';

/// Converts backend failures into messages that are safe and useful to show users.
/// Database exceptions raised by BubbleApp functions carry human-readable text, which
/// is surfaced as-is; anything unexpected is generalised.
String friendlyError(Object error) {
  if (error is AuthException) {
    return error.message;
  }
  if (error is PostgrestException) {
    final message = error.message;
    if (error.code == '42501' || message.toLowerCase().contains('permission denied')) {
      return 'You do not have permission to do that.';
    }
    if (message.isNotEmpty) {
      return message;
    }
    return 'The request could not be completed.';
  }
  if (error is StorageException) {
    return error.message;
  }
  return 'Something went wrong. Please try again.';
}
