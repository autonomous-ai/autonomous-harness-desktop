import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../lamp/lamp_cli.dart';
import '../../core/test_run.dart';
import '../../shared/widgets/app_icon_button.dart';
import '../../shared/widgets/setting_row.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/widgets/section_scaffold.dart';

class DevicesSection extends StatefulWidget {
  const DevicesSection({super.key, this.cli});
  final LampCli? cli;
  @override
  State<DevicesSection> createState() => _DevicesSectionState();
}

class _DevicesSectionState extends State<DevicesSection> {
  late final LampCli _cli = widget.cli ?? LampCli();
  Timer? _timer;
  bool _loading = true;
  bool _busy = false;
  bool _refreshing = false;
  int _generation = 0;
  bool _unsupported = false;
  String? _error;
  Map<String, dynamic> _status = {};
  Map<String, dynamic> _pair = {};
  List<Map<String, dynamic>> _lamps = [];

  @override
  void initState() {
    super.initState();
    if (kUnderTest && widget.cli == null) {
      _loading = false;
      return;
    }
    unawaited(_refresh());
  }

  bool get _pairing => const {'waiting', 'running'}.contains(_pair['state']);

  void _scheduleRefresh() {
    _timer?.cancel();
    // Tests may inject a fake for the initial fetch and user actions, but must
    // never start a background clock or invoke a real CLI.
    if (!mounted || kUnderTest || _unsupported || _busy) return;
    _timer = Timer(Duration(seconds: _pairing ? 2 : 60), () {
      unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Leaving the screen does not revoke trust or stop the daemon. An open
    // pairing window expires at the CLI's deadline unless explicitly cancelled.
    super.dispose();
  }

  void _failed(Object error) {
    _error = error is LampCliException
        ? error.message
        : 'Could not reach the Harness CLI.';
    if (error is LampCliException && error.unsupported) _unsupported = true;
  }

  Future<void> _refresh() async {
    if (_refreshing || (kUnderTest && widget.cli == null)) return;
    _refreshing = true;
    final generation = _generation;
    try {
      final status = await _cli.status();
      final results = await Future.wait([_cli.list(), _cli.pairStatus()]);
      if (!mounted || generation != _generation) return;
      final lamps = <Map<String, dynamic>>[
        for (final row in results[0]['lamps'] as List? ?? [])
          if (row is Map<String, dynamic>) row,
      ];
      final pair = <String, dynamic>{...results[1]};
      // Only preserve omitted display metadata, never a stale code or state.
      for (final key in ['address', 'machineName']) {
        if (pair[key] == null && _pair[key] != null) pair[key] = _pair[key];
      }
      if (_loading ||
          _unsupported ||
          _error != null ||
          jsonEncode([status, lamps, pair]) !=
              jsonEncode([_status, _lamps, _pair]) ||
          _pairing) {
        setState(() {
          _status = status;
          _lamps = lamps;
          _pair = pair;
          _loading = false;
          _unsupported = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _failed(error);
          _loading = false;
        });
      }
    } finally {
      _refreshing = false;
      _scheduleRefresh();
    }
  }

  Future<bool> _confirm(String title, String detail, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 360,
            child: Text(
              detail,
              style: TextStyle(
                fontFamily: grid.AppFont.sans,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                foregroundColor: grid.AppPalette.textSecondary,
                overlayColor: grid.AppSurface.hoverFill,
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('lamp-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: grid.AppPalette.dangerFill,
                overlayColor: const Color(0x1FFFFFFF),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _act(Future<void> Function() action) async {
    if (_busy || (kUnderTest && widget.cli == null)) return;
    _timer?.cancel();
    // A poll begun before this mutation must not overwrite its newer response.
    _generation++;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _failed(error));
    } finally {
      if (mounted) setState(() => _busy = false);
      _scheduleRefresh();
    }
  }

  Future<void> _start() async {
    // CLI LampTransport.pairStart only stages a candidate; receive confirms it
    // after authenticated lamp_finished, then disconnects the previous lamp.
    final replace = _lamps.isNotEmpty;
    if (replace &&
        !await _confirm(
          'Replace paired lamp?',
          'The current lamp keeps access until the new lamp connects securely. '
              'Cancelling or letting the code expire keeps the current pairing.',
          'Replace lamp',
        )) {
      return;
    }
    if (!mounted) return;
    await _act(() async {
      final result = await _cli.pair(replace: replace);
      if (mounted) {
        setState(() {
          _pair = {...result, 'state': 'waiting'};
        });
      }
    });
  }

  Future<void> _revoke(Map<String, dynamic> lamp) async {
    if (!await _confirm(
      'Revoke lamp?',
      'Disconnect ${lamp['label'] ?? 'this lamp'} and remove its access to this computer. '
          'It will need to pair again.',
      'Revoke',
    )) {
      return;
    }
    if (!mounted) return;
    await _act(() async {
      await _cli.revoke(lamp['id'] as String);
      await _refresh();
    });
  }

  int get _remaining {
    final raw = _pair['expiresAt'];
    final expiry = raw is num
        ? DateTime.fromMillisecondsSinceEpoch(raw.toInt())
        : raw is String
        ? DateTime.tryParse(raw)
        : null;
    if (expiry == null) return 0;
    return math.max(
      0,
      (expiry.difference(DateTime.now()).inMilliseconds + 999) ~/ 1000,
    );
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final disabled = _busy || _loading || (kUnderTest && widget.cli == null);
    final remaining = _remaining;
    Widget action(String label, VoidCallback? onPressed) => SizedBox(
      width: SettingRow.controlWidth,
      child: OutlinedButton(onPressed: onPressed, child: Text(label)),
    );
    Widget fact(String title, String value, {String detail = ''}) => SettingRow(
      title: title,
      detail: detail,
      control: SizedBox(
        width: SettingRow.controlWidth,
        child: SelectableText(
          value,
          style: TextStyle(
            fontFamily: grid.AppFont.sans,
            fontSize: 13,
            color: grid.AppPalette.textPrimary,
          ),
        ),
      ),
    );
    return SectionScaffold(
      title: 'Devices',
      subtitle: 'Pair one Autonomous lamp with this computer.',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading)
              SkeletonBlock(
                child: Container(
                  decoration: BoxDecoration(
                    color: grid.AppGlass.surfaceFill,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: grid.AppGlass.cardShadow,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: const SkeletonListTile(
                    leading: 0,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            if (_unsupported)
              SettingRow(
                title: 'Update Harness CLI to use lamp devices.',
                detail: 'Run this command in Terminal, then refresh this page.',
                control: const SizedBox(
                  width: SettingRow.controlWidth,
                  child: SelectableText('harness update'),
                ),
              ),
            if (_error != null && !_unsupported)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(
                    fontFamily: grid.AppFont.sans,
                    fontSize: 13,
                    color: grid.AppPalette.dangerFill,
                  ),
                ),
              ),
            if (!_unsupported && !_loading) ...[
              for (final lamp in _lamps) ...[
                SettingRow(
                  title: lamp['label']?.toString() ?? 'Lamp',
                  detail: lamp['pendingFirstSession'] == true
                      ? 'Waiting for first connection'
                      : lamp['online'] == true
                      ? 'Connected'
                      : 'Paired · Offline',
                  control: action(
                    'Revoke',
                    disabled || lamp['id'] is! String
                        ? null
                        : () => _revoke(lamp),
                  ),
                ),
                const SizedBox(height: 10),
                fact('Fingerprint', lamp['fingerprint']?.toString() ?? ''),
                const SizedBox(height: 10),
              ],
              if (_pairing) ...[
                fact(
                  'Pairing code',
                  remaining > 0
                      ? _pair['code']?.toString() ?? 'Pairing in progress'
                      : 'Expired',
                  detail: remaining > 0
                      ? 'Expires in $remaining seconds'
                      : 'The code expired. Cancel and start again.',
                ),
                const SizedBox(height: 10),
                fact(
                  'Computer address',
                  (_pair['address'] ?? _status['address'] ?? '').toString(),
                  detail: (_pair['machineName'] ?? '').toString(),
                ),
                const SizedBox(height: 10),
                SettingRow(
                  title: _pair['state'] == 'running'
                      ? 'Pairing…'
                      : 'Enter these on your lamp',
                  detail: 'The lamp and computer must be reachable on your local network.',
                  control: action(
                    'Cancel pairing',
                    disabled
                        ? null
                        : () => _act(() async {
                            await _cli.cancel();
                            if (mounted) {
                              setState(() => _pair = {'state': 'idle'});
                            }
                          }),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (_pair['state'] == 'paired') ...[
                fact(
                  'Lamp paired successfully.',
                  _pair['lampFingerprint']?.toString() ?? '',
                ),
                const SizedBox(height: 10),
              ],
              if (_pair['state'] == 'failed') ...[
                SettingRow(
                  title: 'Pairing failed',
                  detail: (_pair['error'] ?? 'Start again to retry.')
                      .toString(),
                  control: const SizedBox.shrink(),
                ),
                const SizedBox(height: 10),
              ],
              SettingRow(
                title: _lamps.isEmpty ? 'No lamp paired' : 'Pair another lamp',
                detail: _lamps.isEmpty
                    ? 'Connect a lamp to this computer’s agents.'
                    : 'The current lamp keeps access until its replacement connects securely.',
                control: action(
                  _lamps.isEmpty ? 'Pair a lamp' : 'Replace lamp',
                  disabled || _pairing ? null : _start,
                ),
              ),
              const SizedBox(height: 10),
            ],
            SettingRow(
              title: 'Refresh',
              detail: 'Harness CLI keeps the connection running when you close Desktop.',
              control: AppIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh lamp status',
                onPressed: disabled ? null : () => unawaited(_refresh()),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
