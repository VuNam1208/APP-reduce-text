import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_first_app/main.dart';

void main() {
  testWidgets('summarizer app requires a configured backend',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Text Summarizer'), findsWidgets);

    const sourceText = '''
The goal of the system is to help users read long documents quickly.
The app accepts content from files or from the text input area on screen.
The backend should summarize this content.
The result is a shorter summary that is easy to copy and still captures the main ideas.
Users can adjust the summary length to match practical reading needs.
    This solution is suitable for a prototype on Android and iOS phones.
''';

    await tester.tap(find.byKey(const Key('enterTextButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sourceInput')), sourceText);
    await tester.ensureVisible(find.byKey(const Key('summarizeButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('summarizeButton')));
    await tester.pumpAndSettle();

    expect(
      find.text('Backend URL is not configured. Build the app with SUMMARY_API_URL.'),
      findsOneWidget,
    );
  });

  testWidgets('settings panel changes export actions',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.byKey(const Key('settingsToggleButton')));
    await tester.pumpAndSettle();

    expect(find.text('Language'), findsOneWidget);
    expect(find.text('OCR'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);

    await tester.tap(find.byKey(const Key('languageDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vietnamese').last);
    await tester.pumpAndSettle();

    expect(find.text('Vietnamese'), findsWidgets);

    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    expect(find.text('PDF only'), findsOneWidget);
  });
}
