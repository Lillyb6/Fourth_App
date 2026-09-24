import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourthapp/main.dart';

void main() {
  testWidgets('Create a habit, check in, undo and open accountability', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.text('New habit'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Create habit'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create habit'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a habit name.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Read a book');
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Create habit'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create habit'));
    await tester.pumpAndSettle();
    expect(find.text('Read a book'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Check in'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1 scheduled habits complete'), findsOneWidget);
    await tester.tap(find.text('Read a book'));
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsOneWidget);
    await tester.tap(find.text('Undo today’s check-in'));
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('0 of 1 scheduled habits complete'), findsOneWidget);
    await tester.tap(find.text('Accountability'));
    await tester.pumpAndSettle();
    expect(find.text('Your accountability circle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
