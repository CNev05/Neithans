import 'package:flutter_test/flutter_test.dart';

import 'package:neithans/main.dart';

void main() {
  testWidgets('Neithans app builds successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const NeithansApp(firebaseInitialized: true));

    expect(find.byType(NeithansApp), findsOneWidget);
  });
}
