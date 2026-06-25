import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/services/text_document_reader.dart';

void main() {
  test('cleanExtractedText restores common missing spaces from PDFs', () {
    const rawText =
        'YouOnlyLookOnce:Unified,Real-TimeObjectDetection,[16]N.Wojke,A.Bewley,andD.Paulus;SimpleOnlineandRealTimeTrackingwithaDeepAssociationMetric.';

    final cleaned = TextDocumentReader.cleanExtractedText(rawText);

    expect(cleaned, contains('You Only Look Once: Unified'));
    expect(cleaned, contains('Real-Time Object Detection'));
    expect(cleaned, contains('[16] N. Wojke, A. Bewley, and D. Paulus'));
    expect(cleaned, contains('Simple Online and Real Time Tracking with a Deep'));
  });

  test('cleanExtractedText joins broken lines without deleting words', () {
    const rawText = 'This is a hyphen-\nated word.\nThis line continues.';

    final cleaned = TextDocumentReader.cleanExtractedText(rawText);

    expect(cleaned, 'This is a hyphenated word. This line continues.');
  });
}
