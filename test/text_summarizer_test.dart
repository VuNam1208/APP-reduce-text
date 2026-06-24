import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/services/text_summarizer.dart';

void main() {
  test('summarize returns a shorter text with keywords', () {
    const text = '''
Mục tiêu của ứng dụng là tóm tắt tài liệu dài cho người dùng di động.
Tài liệu đầu vào có thể gồm nhiều đoạn văn bản khác nhau.
Phương pháp của hệ thống là chấm điểm câu theo tần suất từ khóa.
Những câu có nhiều từ khóa quan trọng sẽ được ưu tiên trong bản tóm tắt.
Kết quả giúp người dùng nắm nhanh nội dung chính mà không cần đọc toàn bộ.
Ứng dụng cũng hiển thị số từ của văn bản gốc và bản tóm tắt.
Người dùng có thể thay đổi tỷ lệ rút gọn để phù hợp với từng loại tài liệu.
Kết luận là bản thử nghiệm này tạo được nền tảng cho app tóm tắt trên Android và iOS.
''';

    const summarizer = TextSummarizer();
    final result = summarizer.summarize(text, targetRatio: 0.25);

    expect(result.summary, isNotEmpty);
    expect(result.keywords, isNotEmpty);
    expect(result.summaryWordCount, lessThanOrEqualTo(result.originalWordCount));
  });

  test('summarize supports English and Vietnamese input', () {
    const text = '''
The goal of this app is to summarize long documents for mobile users.
Users can paste English content or upload supported files from their phone.
Mục tiêu của ứng dụng là giúp người dùng tóm tắt văn bản tiếng Việt một cách nhanh chóng.
Phương pháp tóm tắt ưu tiên các câu chứa nhiều từ khóa quan trọng.
The result should keep the main ideas while reducing reading time.
Kết quả cuối cùng là một bản tóm tắt ngắn gọn, dễ đọc và có thể tải về file.
''';

    const summarizer = TextSummarizer();
    final result = summarizer.summarize(text, targetRatio: 0.4);

    expect(result.summary, isNotEmpty);
    expect(result.originalWordCount, greaterThan(20));
    expect(result.keywords, isNotEmpty);
  });
}
