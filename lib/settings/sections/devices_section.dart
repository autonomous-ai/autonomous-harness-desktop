import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../autonomous_device/autonomous_device_cli.dart';
import '../../core/test_run.dart';
import '../../shared/widgets/app_icon_button.dart';
import '../../shared/widgets/labeled_field.dart';
import '../../shared/widgets/setting_row.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/widgets/section_scaffold.dart';

class DevicesSection extends StatefulWidget {
  const DevicesSection({super.key, this.cli});
  final AutonomousDeviceCli? cli;
  @override
  State<DevicesSection> createState() => _DevicesSectionState();
}

class _DevicesSectionState extends State<DevicesSection> {
  late final AutonomousDeviceCli _cli = widget.cli ?? AutonomousDeviceCli();
  Timer? _timer;
  final _code = TextEditingController();
  bool _replace = false;
  bool _loading = true;
  bool _busy = false;
  bool _refreshing = false;
  int _generation = 0;
  bool _unsupported = false;
  String? _error;
  Map<String, dynamic> _status = {};
  Map<String, dynamic> _pair = {};
  List<Map<String, dynamic>> _devices = [];

  @override
  void initState() {
    super.initState();
    if (kUnderTest && widget.cli == null) {
      _loading = false;
      return;
    }
    unawaited(_refresh());
  }

  bool get _pairing =>
      const {'listening', 'waiting', 'running'}.contains(_pair['state']);

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
    _code.dispose();
    // Leaving the screen does not revoke trust or stop the daemon. An open
    // pairing window expires at the CLI's deadline unless explicitly cancelled.
    super.dispose();
  }

  void _failed(Object error) {
    _error = error is AutonomousDeviceCliException
        ? error.message
        : 'Could not reach the Harness CLI.';
    if (error is AutonomousDeviceCliException && error.unsupported) {
      _unsupported = true;
    }
  }

  Future<void> _refresh() async {
    if (_refreshing || (kUnderTest && widget.cli == null)) return;
    _refreshing = true;
    final generation = _generation;
    try {
      final status = await _cli.status();
      final results = await Future.wait([_cli.list(), _cli.pairStatus()]);
      if (!mounted || generation != _generation) return;
      final devices = <Map<String, dynamic>>[
        for (final row in results[0]['devices'] as List? ?? [])
          if (row is Map<String, dynamic>) row,
      ];
      final pair = <String, dynamic>{...results[1]}..remove('code');
      for (final key in ['address', 'machineName']) {
        if (pair[key] == null && _pair[key] != null) pair[key] = _pair[key];
      }
      if (pair['state'] != 'waiting' ||
          pair['pairId'] != _pair['pairId'] ||
          pair['expiresAt'] != _pair['expiresAt'] ||
          _secondsRemaining(pair) <= 0) {
        _code.clear();
      }
      if (_loading ||
          _unsupported ||
          _error != null ||
          jsonEncode([status, devices, pair]) !=
              jsonEncode([_status, _devices, _pair]) ||
          _pairing) {
        setState(() {
          _status = status;
          _devices = devices;
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
              key: const Key('device-confirm'),
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
    // CLI AutonomousDeviceTransport.pairStart only stages a candidate; receive confirms it
    // after authenticated autonomous_device_finished, then disconnects the previous Autonomous device.
    final replace = _devices.isNotEmpty;
    if (replace &&
        !await _confirm(
          'Replace paired Autonomous device?',
          'The current Autonomous device keeps access until the new Autonomous device connects securely. '
              'Cancelling or letting the code expire keeps the current pairing.',
          'Replace Autonomous device',
        )) {
      return;
    }
    if (!mounted) return;
    await _act(() async {
      final result = await _cli.listen(replace: replace);
      if (mounted) {
        setState(() {
          _replace = replace;
          _code.clear();
          _pair = {...result, 'state': 'listening'}..remove('code');
        });
      }
    });
  }

  Future<void> _submitCode() async {
    final pairId = _pair['pairId'];
    final code = _code.text.trim().toUpperCase();
    if (_busy ||
        _pair['state'] != 'waiting' ||
        pairId is! String ||
        _remaining <= 0) {
      return;
    }
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
      setState(
        () => _error =
            'Enter the six-character code shown on your Autonomous device.',
      );
      return;
    }
    if (_devices.isNotEmpty && !_replace) {
      if (!await _confirm(
        'Replace paired Autonomous device?',
        'The current Autonomous device keeps access until its replacement connects securely.',
        'Replace Autonomous device',
      )) {
        return;
      }
      if (!mounted) return;
      _replace = true;
    }
    await _act(() async {
      _code.clear();
      // Verify the pending intent before submitting; the CLI also checks pair-id.
      final fresh = await _cli.pairStatus();
      if (fresh['state'] != 'waiting' ||
          fresh['pairId'] != pairId ||
          fresh['expiresAt'] != _pair['expiresAt'] ||
          _remaining <= 0) {
        throw const AutonomousDeviceCliException(
          'STALE_PAIR',
          'The pairing request changed. Refresh and enter the code from the current Autonomous device.',
        );
      }
      final result = await _cli.pair(
        code: code,
        pairId: pairId,
        replace: _replace,
      );
      if (mounted) {
        setState(
          () =>
              _pair = {..._pair, ...result, 'state': 'running'}..remove('code'),
        );
      }
    });
  }

  Future<void> _revoke(Map<String, dynamic> device) async {
    if (!await _confirm(
      'Revoke Autonomous device?',
      'Disconnect ${device['label'] ?? 'this Autonomous device'} and remove its access to this computer. '
          'It will need to pair again.',
      'Revoke Autonomous device',
    )) {
      return;
    }
    if (!mounted) return;
    await _act(() async {
      await _cli.revoke(device['id'] as String);
      await _refresh();
    });
  }

  int get _remaining => _secondsRemaining(_pair);

  int _secondsRemaining(Map<String, dynamic> pair) {
    final raw = pair['expiresAt'];
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
      subtitle: 'Pair one Autonomous device with this computer.',
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
                title: 'Update Harness CLI to use Autonomous devices.',
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
              for (final device in _devices) ...[
                SettingRow(
                  title: device['label']?.toString() ?? 'Autonomous device',
                  detail: device['pendingFirstSession'] == true
                      ? 'Waiting for first connection'
                      : device['online'] == true
                      ? 'Connected'
                      : 'Paired · Offline',
                  control: action(
                    'Revoke Autonomous device',
                    disabled || device['id'] is! String
                        ? null
                        : () => _revoke(device),
                  ),
                ),
                const SizedBox(height: 10),
                fact('Fingerprint', device['fingerprint']?.toString() ?? ''),
                const SizedBox(height: 10),
              ],
              if (_pairing) ...[
                fact(
                  'Computer address',
                  (_pair['address'] ?? _status['address'] ?? '').toString(),
                  detail: (_pair['machineName'] ?? '').toString(),
                ),
                const SizedBox(height: 10),
                SettingRow(
                  title: _pair['state'] == 'running'
                      ? 'Pairing…'
                      : _pair['state'] == 'listening'
                      ? 'Waiting for your Autonomous device'
                      : 'Enter the code from your Autonomous device',
                  detail: remaining > 0
                      ? 'Open Harness pairing on your Autonomous device and enter this computer address. Expires in $remaining seconds.'
                      : 'The pairing window expired. Cancel and start again.',
                  control: action(
                    'Cancel pairing',
                    disabled
                        ? null
                        : () => _act(() async {
                            await _cli.cancel();
                            if (mounted) {
                              setState(() {
                                _pair = {'state': 'idle'};
                                _code.clear();
                                _replace = false;
                              });
                            }
                          }),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (_pair['state'] == 'waiting' &&
                  _pair['pairId'] is String &&
                  remaining > 0) ...[
                SettingRow(
                  title: 'Code from Autonomous device',
                  detail:
                      _pair['deviceLabel']?.toString() ??
                      'The code appears on your Autonomous device.',
                  control: SizedBox(
                    width: SettingRow.controlWidth,
                    child: TextField(
                      key: const Key('autonomous-device-code'),
                      controller: _code,
                      enabled: !disabled,
                      maxLength: 6,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: TextStyle(
                        fontFamily: grid.AppFont.sans,
                        fontSize: 13,
                        color: grid.AppPalette.textPrimary,
                      ),
                      decoration: labeledFieldDecoration(
                        'Six-character code',
                        fill: grid.AppCard.inset,
                      ).copyWith(counterText: ''),
                      onSubmitted: (_) => unawaited(_submitCode()),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SettingRow(
                  title: 'Confirm pairing',
                  detail: 'The code is sent privately to Harness CLI.',
                  control: action(
                    'Connect Autonomous device',
                    disabled ? null : () => unawaited(_submitCode()),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (_pair['state'] == 'paired') ...[
                fact(
                  'Autonomous device paired successfully.',
                  _pair['deviceFingerprint']?.toString() ?? '',
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
                title: _devices.isEmpty
                    ? 'No Autonomous device paired'
                    : 'Pair another Autonomous device',
                detail: _devices.isEmpty
                    ? 'Connect an Autonomous device to this computer’s agents.'
                    : 'The current Autonomous device keeps access until its replacement connects securely.',
                control: action(
                  _devices.isEmpty
                      ? 'Pair an Autonomous device'
                      : 'Replace Autonomous device',
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
                tooltip: 'Refresh Autonomous device status',
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
