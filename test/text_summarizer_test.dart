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
}
