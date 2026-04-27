import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitclient/app/git_client_app.dart';

void main() {
  testWidgets('renders the disconnected workbench shell', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const GitClientApp());
    await tester.pumpAndSettle();

    expect(find.text('Choose repository'), findsOneWidget);
    expect(find.text('Console'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
  });
}
