import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_first_app/main.dart';

void main() {
  testWidgets('summarizer app accepts pasted text and creates a summary',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Text Summarizer'), findsWidgets);

    const sourceText = '''
The goal of the system is to help users read long documents quickly.
The app accepts content from files or from the text input area on screen.
The summarization method prioritizes sentences with important keywords and keeps the original order.
The result is a shorter summary that is easy to copy and still captures the main ideas.
Users can adjust the summary length to match practical reading needs.
This solution is suitable for a prototype on Android and iOS phones.
''';

    await tester.enterText(find.byKey(const Key('sourceInput')), sourceText);
    await tester.ensureVisible(find.byKey(const Key('summarizeButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('summarizeButton')));
    await tester.pumpAndSettle();

    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Download .txt'), findsOneWidget);
  });
}
