import 'package:flutter_test/flutter_test.dart';
import 'package:decard/main.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const DecardApp());
    expect(find.text('데카드'), findsOneWidget);
    expect(find.text('카드 만들기'), findsOneWidget);
  });
}
