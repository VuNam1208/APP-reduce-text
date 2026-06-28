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

  test('cleanExtractedText joins common words split by OCR spaces', () {
    const rawText =
        'Noi dung chinh tro ng tai lieu nay co ph uong phap ng hien c uu va ket qua.';

    final cleaned = TextDocumentReader.cleanExtractedText(rawText);

    expect(cleaned, contains('trong tai lieu nay co phuong phap nghien cuu'));
  });

  test('looksUnreadableExtractedText detects broken PDF font encoding', () {
    const brokenText =
        '„IHÅCQUÈCGIAH€NËITR×ÍNG „IHÅCCÆNGNGH› Tr¦n Minh Tu§n '
        'PH THI›NV€PH...NLO„IM, ËCDÜATR–NC CKž THUŠ THÅCS...'
        'VIETNAMNATIONALUNIVERSITY, HANOIUNIVERSITYOFENGINEERINGANDTECHNOLOGY';

    expect(TextDocumentReader.looksUnreadableExtractedText(brokenText), isTrue);
  });

  test('looksUnreadableExtractedText keeps normal English and Vietnamese text', () {
    const readableText =
        'Vietnam National University, Hanoi University of Engineering and Technology. '
        'Trần Minh Tuấn nghiên cứu phát hiện mã độc bằng học sâu.';

    expect(
      TextDocumentReader.looksUnreadableExtractedText(readableText),
      isFalse,
    );
  });
}
