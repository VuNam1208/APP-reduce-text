import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_first_app/main.dart';

void main() {
  testWidgets('summarizer app accepts pasted text and creates a summary',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Text Summarizer'), findsWidgets);

    const sourceText = '''
Mục tiêu của hệ thống là giúp người dùng đọc nhanh các tài liệu dài.
Ứng dụng nhận nội dung văn bản từ file hoặc từ vùng nhập liệu trên màn hình.
Phương pháp tóm tắt ưu tiên các câu chứa nhiều từ khóa quan trọng và giữ lại trật tự ban đầu.
Kết quả là một bản tóm tắt ngắn hơn, dễ sao chép và đủ để nắm ý chính.
Người dùng có thể điều chỉnh độ dài tóm tắt theo nhu cầu thực tế.
Giải pháp này phù hợp cho bản thử nghiệm trên điện thoại Android và iOS.
''';

    await tester.enterText(find.byKey(const Key('sourceInput')), sourceText);
    await tester.ensureVisible(find.byKey(const Key('summarizeButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('summarizeButton')));
    await tester.pumpAndSettle();

    expect(find.text('Bản tóm tắt'), findsOneWidget);
    expect(find.text('Sao chép'), findsOneWidget);
    expect(find.text('Download .txt'), findsOneWidget);
  });
}
