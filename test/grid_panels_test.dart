import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/grid/grid_api_client.dart';
import 'package:harness/grid/grid_credentials.dart';
import 'package:harness/grid/grid_overview.dart';
import 'package:harness/grid/grid_overview_controller.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/grid/managed_network_member.dart';
import 'package:harness/grid/member_usage.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/widgets/status_rail/grid_status_rail.dart';
import 'package:harness/widgets/status_rail/pill_panel_shell.dart';

class _Store implements LocalKeyValueStore {
  final Map<String, String> v = {};
  @override
  Future<String?> read(String k) async => v[k];
  @override
  Future<void> write(String k, String value) async => v[k] = value;
  @override
  Future<void> delete(String k) async => v.remove(k);
}

Map<String, dynamic> _json(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;

class _Api extends GridApiClient {
  @override
  Future<GridCredentials> credentials(String networkId) async =>
      GridCredentials(networkId: networkId, baseUrl: 'x', apiKey: 'y');

  @override
  Future<GridOverview> overview({
    required String baseUrl,
    required String apiKey,
  }) async => GridOverview.fromJson(_json('grid_overview'));

  @override
  Future<List<ManagedNetworkMember>?> members(String networkId) async => [
    for (final row in jsonDecode(
      File('test/fixtures/members.json').readAsStringSync(),
    ) as List)
      ManagedNetworkMember.fromJson(Map<String, dynamic>.from(row as Map)),
  ];

  @override
  Future<({int windowSeconds, Map<String, MemberUsage> byEmail})?> memberUsage({
    required String baseUrl,
    required String apiKey,
  }) async {
    final body = _json('member_usage');
    final rows = body['members'];
    if (rows is! List) return null;
    return (
      windowSeconds: (body['window_seconds'] as num?)?.toInt() ?? 0,
      byEmail: {
        for (final row in rows)
          if (MemberUsage.fromJson(row) case final u?)
            if (u.email case final e? when e.isNotEmpty) e.toLowerCase(): u,
      },
    );
  }
}

/// Load a real font.
///
/// Widget tests draw with Ahem, whose every glyph is a fixed square — a 24
/// character label measures 276px where Arial measures ~140. That is not a
/// small distortion for a panel whose whole job is fitting figures beside
/// names: with Ahem the node panel overflows by 19px, and without a real font
/// a golden of it is a picture of a bug that does not exist.
Future<void> _loadFont() async {
  Future<ByteData> bytes() async => ByteData.view(
    Uint8List.fromList(
      await File('/System/Library/Fonts/Supplemental/Arial.ttf').readAsBytes(),
    ).buffer,
  );
  // Under every family the panels can resolve to: the app's own
  // `.AppleSystemUIFont`, and Roboto, which is what an unthemed widget falls
  // back to in a test.
  for (final family in ['.AppleSystemUIFont', 'Roboto', 'SF Pro Text']) {
    await (FontLoader(family)..addFont(bytes())).load();
  }
  // A model id is set in mono, and an unregistered mono family falls back to
  // Ahem just as loudly.
  Future<ByteData> mono() async => ByteData.view(
    Uint8List.fromList(
      await File(
        '/System/Library/Fonts/Supplemental/Courier New.ttf',
      ).readAsBytes(),
    ).buffer,
  );
  for (final family in ['.AppleSystemUIFontMonospaced', 'SF Mono', 'Menlo']) {
    await (FontLoader(family)..addFont(mono())).load();
  }
}

/// What each panel has to be showing. One line per panel that could only come
/// from that panel having actually parsed the captured relay answer — a heading
/// alone would pass on an empty list.
const _expects = {
  'autonomous.ai': ['IN USE', 'SELF-HOST', '1.0 / 1.7 TB · 59%', '99.9% uptime'],
  '33': ['33 MEMBERS', 'owner', '106M input · 24h'],
  '8': ['NODES', '@team2', '828.3 GB VRAM', '4 × Apple M2 Ultra · macOS'],
  '10': ['MODELS', 'CARRYING THIS GRID · LAST 24H', 'FRESH IN', 'OTHERS · 9'],
  '106M': ['TOKENS', 'last 24h', 'Input', 'Cached', 'Output', 'Answered'],
};

void main() {
  setUpAll(_loadFont);

  for (final target in ['autonomous.ai', '33', '8', '10', '106M']) {
    testWidgets('panel over $target', (tester) async {
      grid.AppTheme.brightness.value = Brightness.light;
      tester.view.physicalSize = const Size(1000, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final selection = GridSelectionStore(storage: _Store());
      await selection.selectNetwork(
        networkId: 'grid-3378218621364f16',
        networkName: 'autonomous.ai',
      );
      final controller = GridOverviewController(
        api: _Api(),
        selection: selection,
        interval: const Duration(hours: 1),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: grid.buildAppTheme(brightness: Brightness.light),
          home: Scaffold(
            backgroundColor: grid.AppPalette.windowBg,
            body: Column(
              children: [
                const Spacer(),
                GridStatusRail(controller: controller),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      await pointer.moveTo(tester.getCenter(find.text(target).first));
      // The panel opens on a beat, so a pointer crossing the rail on its way
      // elsewhere does not flash one open behind it.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.byType(PillPanelSurface), findsOneWidget);
      for (final line in _expects[target]!) {
        expect(find.text(line), findsWidgets, reason: '$target · $line');
      }
      controller.dispose();
    });
  }
}
