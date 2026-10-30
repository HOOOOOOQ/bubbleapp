import 'package:bubbleapp/core/bubble_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('permission-denied database errors become a plain message', () {
    final e = PostgrestException(message: 'permission denied for table x', code: '42501');
    expect(friendlyError(e), 'You do not have permission to do that.');
  });

  test('BubbleApp function messages are shown as written', () {
    final e = PostgrestException(message: 'Only pending applications can start review', code: 'P0001');
    expect(friendlyError(e), 'Only pending applications can start review');
  });

  test('unknown errors are generalised and do not leak internals', () {
    expect(friendlyError(StateError('secret stack detail')), 'Something went wrong. Please try again.');
  });
}
