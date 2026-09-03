import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/share_page_theme.dart';
import '../engine_run.dart';
import '../grid_cli.dart';
import '../model_pull.dart';
import '../share_controller.dart';
import '../share_route.dart';
import 'serve_key_form.dart';
import 'serve_local_form.dart';
import 'serve_server_form.dart';
import 'share_form_parts.dart';

/// The right half: the route picked on the left, said once at the top and then
/// set up underneath.
///
/// One route at a time, which is the whole reason the page is split in two.
class ShareDetail extends StatelessWidget {
  const ShareDetail({
    super.key,
    required this.controller,
    required this.pull,
    required this.cli,
    required this.gridName,
  });

  final ShareController controller;
  final ModelPullController pull;
  final GridCli cli;
  final String gridName;

  /// Which of the offered routes this is, one-based. Read off the rail's own
  /// list rather than written into the copy: a machine that cannot run a local
  /// engine has no route 01, and an eyebrow saying otherwise would number a row
  /// that is not on the page.
  int get _position {
    final offers = controller.capabilities.offers;
    return offers.indexWhere((offer) => offer.route == controller.route) + 1;
  }

  int get _serversFound {
    for (final offer in controller.capabilities.offers) {
      if (offer.route == ShareRoute.server) return offer.detected;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    if (controller.status == ShareStatus.live) {
      return _Pane(
        header: PanelHeader(
          eyebrow: 'LIVE ON THE GRID',
          eyebrowColour: SharePalette.liveInk,
          title: 'This computer is answering questions.',
          blurb: _liveBlurb,
        ),
        body: LiveSharePanel(controller: controller),
      );
    }
    final (eyebrow, title, blurb) = _copy;
    return _Pane(
      header: PanelHeader(
        eyebrow: 'ROUTE 0$_position · $eyebrow',
        title: title,
        blurb: blurb,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.error != null) ...[
            ShareErrorNote(
              message: controller.error!,
              onDismiss: controller.clearError,
            ),
            const SizedBox(height: 16),
          ],
          _form,
        ],
      ),
    );
  }

  String get _liveBlurb {
    final models = {
      for (final spec in controller.liveRun?.engines ?? const <EngineSpec>[])
        ...spec.models,
    };
    final what = switch (models.length) {
      0 => 'Serving on $gridName',
      1 => 'Serving ${models.first} on $gridName',
      final n => 'Serving $n models on $gridName',
    };
    return '$what. It keeps working whether or not this window is open.';
  }

  (String, String, String) get _copy => switch (controller.route) {
    ShareRoute.local => (
      'LOCAL MODEL',
      'Run a model on this computer.',
      'Questions arrive over the grid, get answered on your hardware, and the '
          'answer goes back. The weights never leave this disk.',
    ),
    ShareRoute.key => (
      'YOUR OWN KEY',
      'Lend a key, not a machine.',
      'The grid forwards questions to the provider you pick, using your key. '
          'The key stays on this computer, and what it spends is billed to '
          'your account.',
    ),
    ShareRoute.server => (
      'EXISTING SERVER',
      "Share what's already running.",
      // Names the count when there is one to name, and falls back to the
      // general sentence when nothing was detected — where "Harness found one
      // engine" would be a plain untruth.
      _serversFound == 0
          ? 'Point the grid at an engine on this computer and your existing '
                'setup is shared exactly as configured: models, quantization, '
                'flags.'
          : 'Found ${_serversFound == 1 ? 'one engine' : '$_serversFound engines'} '
                'on this computer. Point at one and your existing setup is '
                'shared exactly as configured: models, quantization, flags.',
    ),
  };

  /// The route's three steps. Keyed by route so switching one out replaces its
  /// state rather than handing the next route the last one's controllers — the
  /// endpoint typed on route 03 has no business surviving into route 01.
  Widget get _form => switch (controller.route) {
    ShareRoute.local => ServeLocalForm(
      key: const ValueKey('local'),
      controller: controller,
      pull: pull,
      cli: cli,
      gridName: gridName,
    ),
    ShareRoute.server => ServeServerForm(
      key: const ValueKey('server'),
      controller: controller,
      gridName: gridName,
    ),
    ShareRoute.key => ServeKeyForm(
      key: const ValueKey('key'),
      controller: controller,
      offers: controller.capabilities.keyProviders,
    ),
  };
}

/// A pane: its heading, then its scrolling body.
class _Pane extends StatelessWidget {
  const _Pane({required this.header, required this.body});

  final Widget header;
  final Widget body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: ShareMetrics.panePadding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: ShareMetrics.paneGap),
        Expanded(child: SingleChildScrollView(child: body)),
      ],
    ),
  );
}

/// What the pane is about, before anything it asks for.
class PanelHeader extends StatelessWidget {
  const PanelHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.blurb,
    this.eyebrowColour,
  });

  final String eyebrow;
  final String title;
  final String blurb;
  final Color? eyebrowColour;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: eyebrowColour == null
              ? ShareType.eyebrow
              : ShareType.eyebrow.copyWith(color: eyebrowColour),
        ),
        const SizedBox(height: 7),
        Text(title, style: ShareType.paneTitle),
        const SizedBox(height: 7),
        Text(blurb, style: ShareType.paneBody),
      ],
    );
  }
}

/// What is serving, and the one way out of it.
///
/// The design drew a stat panel here — requests, tokens out, uptime, median
/// latency. None of the four is measured for THIS computer by anything in this
/// app, and four invented figures is the one thing a dashboard must never do.
/// What is real is listed instead: the engines, and Stop.
class LiveSharePanel extends StatelessWidget {
  const LiveSharePanel({super.key, required this.controller});

  final ShareController controller;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final run = controller.liveRun;
    final stopping = controller.status == ShareStatus.stopping;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SharePlate(
          children: [
            for (final (index, spec)
                in (run?.engines ?? const <EngineSpec>[]).indexed) ...[
              if (index > 0) Divider(height: 25, color: SharePalette.innerRule),
              _EngineRow(spec: spec, port: run?.endpointPort),
            ],
            if (run == null || run.engines.isEmpty)
              Text(
                'An engine is serving this grid. Its details have not been '
                'read back yet.',
                style: ShareType.note,
              ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            ShareButton(
              label: stopping ? 'Stopping…' : 'Stop sharing',
              icon: LucideIcons.square300,
              kind: ShareButtonKind.secondary,
              busy: stopping,
              onPressed: controller.stop,
            ),
            const SizedBox(width: ShareMetrics.buttonGap),
            Flexible(
              child: Text(
                'Stops the engine and takes this computer off the grid.',
                style: ShareType.buttonHelper,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EngineRow extends StatelessWidget {
  const _EngineRow({required this.spec, required this.port});

  final EngineSpec spec;
  final int? port;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final (label, where) = switch (spec.kind) {
      EngineKind.local => (
        spec.models.join(', '),
        port == null ? 'On this hardware' : 'On this hardware · port $port',
      ),
      EngineKind.external => (
        spec.models.join(', '),
        spec.endpointUrl ?? 'A server on this computer',
      ),
      EngineKind.api => (
        spec.models.isEmpty ? spec.apiKind! : spec.models.join(', '),
        'Through your ${spec.apiKind} key',
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(top: 5, right: 10),
          decoration: BoxDecoration(
            color: SharePalette.liveDot,
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.isEmpty ? 'Serving' : label,
                style: ShareType.cardTitle,
              ),
              const SizedBox(height: 2),
              Text(where, style: ShareType.note),
            ],
          ),
        ),
      ],
    );
  }
}
