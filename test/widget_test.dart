import 'package:flutter_test/flutter_test.dart';

import 'package:bandcut/main.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const BandCutApp());
    expect(find.text('BandCut'), findsNWidgets(2));
    expect(find.text('Pick a WAV file to start a session'), findsOneWidget);
  });
}
