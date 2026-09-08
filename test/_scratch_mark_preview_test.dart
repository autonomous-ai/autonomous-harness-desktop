import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/usage/usage_window.dart';
import 'package:harness/widgets/status_rail/usage_mark.dart';

const _out = '/private/tmp/claude-502/-Users-macbook-WorkPlace-Grid-autonomous-harness-desktop/dab1b6f8-77c6-41e1-9ab5-3daa65be2742/scratchpad/marks.png';

Widget _band(Brightness brightness) {
  final light = brightness == Brightness.light;
  return Container(
    color: light ? const Color(0xFFF7F7F5) : const Color(0xFF1C1C1A),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final provider in UsageProvider.values)
          for (final size in [12.0, 22.0, 46.0])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UsageMark(provider: provider, size: size),
                  const SizedBox(width: 5),
                  Text('2% used',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: light
                              ? const Color(0xFF56564F)
                              : const Color(0xFFB4B4AC))),
                ],
              ),
            ),
      ],
    ),
  );
}

void main() {
  testWidgets('preview', (tester) async {
    tester.view.physicalSize = const Size(2400, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: key,
        child: Align(
          alignment: Alignment.topLeft,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Builder(builder: (c) {
              grid.AppTheme.brightness.value = Brightness.light;
              return _band(Brightness.light);
            }),
            Builder(builder: (c) {
              grid.AppTheme.brightness.value = Brightness.dark;
              return _band(Brightness.dark);
            }),
          ]),
        ),
      ),
    ));
    await tester.pump();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(_out).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
