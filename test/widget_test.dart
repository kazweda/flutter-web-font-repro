import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_web_font_repro/main.dart';

void main() {
  testWidgets('shows Before and After comparison cards', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FontReproApp());

    expect(find.textContaining('Before'), findsOneWidget);
    expect(find.textContaining('After'), findsOneWidget);
    expect(find.text('句読点位置バグ再現 (issue #188)'), findsOneWidget);
  });
}
