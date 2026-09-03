import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/grid/grid_network.dart';
import 'package:harness/settings/sections/grid_network_card.dart';

GridNetwork _network() => GridNetwork.fromJson({
  'network_id': 'grid-3378218621364f16',
  'name': 'autonomous.ai',
  'network_type': 'private-domain',
  'status': 'active',
  'owner_email': 'dev@autonomous.ai',
});

Future<void> _pump(
  WidgetTester tester, {
  required bool selected,
  required VoidCallback onToggle,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 700,
          child: GridNetworkCard(
            network: _network(),
            signedInEmail: 'dev@autonomous.ai',
            selected: selected,
            onToggle: onToggle,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an unchosen grid offers to be used', (tester) async {
    var taps = 0;
    await _pump(tester, selected: false, onToggle: () => taps++);

    expect(find.text('Use for new agents'), findsOneWidget);
    await tester.tap(find.text('Use for new agents'));
    expect(taps, 1);
  });

  testWidgets('the chosen grid is still a control, not just a label', (
    tester,
  ) async {
    var taps = 0;
    await _pump(tester, selected: true, onToggle: () => taps++);

    // It reads as a state at rest…
    expect(find.text('In use'), findsOneWidget);
    // …and pressing it again is the way out, which used to live in a menu in
    // the sidebar and nowhere on this card.
    await tester.tap(find.text('In use'));
    expect(taps, 1);
  });

  testWidgets('under the pointer the chosen grid says what a press does', (
    tester,
  ) async {
    await _pump(tester, selected: true, onToggle: () {});

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(find.text('In use')));
    await tester.pumpAndSettle();

    expect(find.text('Stop using'), findsOneWidget);
    expect(find.text('In use'), findsNothing);
  });

  testWidgets('the target is big enough to hit', (tester) async {
    await _pump(tester, selected: false, onToggle: () {});
    // The text link this replaced was 28px tall — under every target size a
    // desktop guideline asks for.
    expect(
      tester.getSize(find.byType(GridNetworkCard).hitTestable()).height,
      greaterThan(0),
    );
    final button = find.ancestor(
      of: find.text('Use for new agents'),
      matching: find.byType(AnimatedContainer),
    );
    expect(tester.getSize(button.first).height, 32);
  });
}
