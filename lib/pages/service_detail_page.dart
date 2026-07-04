import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/ai_server_models.dart';
import '../providers/ai_server_provider.dart';

/// Project service detail — matches the Project---X HTML screen.
class ServiceDetailPage extends ConsumerStatefulWidget {
  const ServiceDetailPage({super.key, this.modelId});

  final String? modelId;

  @override
  ConsumerState<ServiceDetailPage> createState() => _ServiceDetailPageState();
}

class _ServiceDetailPageState extends ConsumerState<ServiceDetailPage> {
  final _logSearchController = TextEditingController();
  final _logScrollController = ScrollController();
  bool _logsFullscreen = false;
  bool _showCustomRange = false;
  String _timeRange = 'last hour';

  static const _serviceId = 'srv-d7udp0po3t8c73fglb40';
  static const _liveUrl = 'project-x-h5d0.onrender.com';
  static const _repo = 'Sujith8257 / Project---X';

  static final _demoLogs = <_LogLine>[
    _LogLine('11:38:46 pm', '[fwp89]', 'initializing container environment...'),
    _LogLine('11:38:46 pm', '[fwp89]', '> paperstudio-backend@1.0.0 start', highlight: true),
    _LogLine('11:38:46 pm', '[fwp89]', '> node dist/server.js', highlight: true),
    _LogLine(
      '11:38:51 pm',
      '[fwp89]',
      'supabase client initialized',
      success: true,
    ),
    _LogLine(
      '11:38:52 pm',
      '[fwp89]',
      'skipping database setup because database_url is not configured.',
      warning: true,
    ),
    _LogLine(
      '11:38:52 pm',
      '[fwp89]',
      '🚀 project-x paper search backend running on port 3000',
    ),
    _LogLine('11:39:10 pm', '[fwp89]', 'get /health 200 - 12ms', dim: true),
    _LogLine('11:40:02 pm', '[fwp89]', 'post /api/v1/search 200 - 145ms', dim: true),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final state = ref.read(aiServerProvider);
      final modelId = widget.modelId ?? state.selectedModelId;
      if (modelId.isEmpty) return;

      ref.read(aiServerProvider.notifier).selectModel(modelId);

      final download = ref.read(aiServerProvider).downloads[modelId];
      final status = download?.status;
      if (status != ModelDownloadStatus.downloaded &&
          status != ModelDownloadStatus.downloading) {
        unawaited(ref.read(aiServerProvider.notifier).downloadModel(modelId));
      }
    });
  }

  @override
  void dispose() {
    _logSearchController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  ModelProfile _model(AiServerState state) {
    final id = widget.modelId ?? state.selectedModelId;
    return state.models.firstWhere(
      (m) => m.id == id,
      orElse: () => state.models.first,
    );
  }

  List<_LogLine> _downloadLogLines(AiServerState state, ModelProfile model) {
    final dl = state.downloads[model.id];
    if (dl == null) return const [];

    final now = DateTime.now();
    final h = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final ts =
        '$h:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'pm' : 'am'}';

    if (dl.status == ModelDownloadStatus.downloading) {
      final pct = (dl.progress * 100).clamp(0, 100).round();
      return [
        _LogLine(ts, '[buildify]', 'downloading ${model.name.toLowerCase()}…', highlight: true),
        _LogLine(ts, '[buildify]', 'progress: $pct%'),
      ];
    }

    if (dl.status == ModelDownloadStatus.downloaded) {
      return [
        _LogLine(ts, '[buildify]', 'model ready on device', success: true),
      ];
    }

    return const [];
  }

  List<_LogLine> _allLogs(AiServerState state) {
    final fromState = state.logs.map((l) {
      final now = DateTime.now();
      final h = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
      final ts =
          '$h:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'pm' : 'am'}';
      return _LogLine(
        ts,
        '[buildify]',
        l.message,
        highlight: l.type == LogType.system,
        warning: l.type == LogType.warning,
        dim: l.type == LogType.request,
      );
    });
    final dlLines = _downloadLogLines(state, _model(state));
    return [..._demoLogs, ...fromState, ...dlLines];
  }

  List<_LogLine> _filteredLogs(List<_LogLine> logs) {
    final q = _logSearchController.text.trim().toLowerCase();
    if (q.isEmpty) return logs;
    return logs
        .where(
          (l) =>
              l.message.toLowerCase().contains(q) ||
              l.instance.toLowerCase().contains(q),
        )
        .toList();
  }

  void _scrollLogsToBottom() {
    if (!_logScrollController.hasClients) return;
    _logScrollController.animateTo(
      _logScrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _copyServiceId() {
    Clipboard.setData(const ClipboardData(text: _serviceId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Service ID copied')),
    );
  }

  void _manualDeploy() {
    if (ref.read(aiServerProvider).status != ServerStatus.running) {
      unawaited(ref.read(aiServerProvider.notifier).startServer());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiServerProvider);
    final model = _model(state);
    final device = state.device;
    final logs = _filteredLogs(_allLogs(state));
    final horizontalPadding = MediaQuery.sizeOf(context).width >= 768 ? 32.0 : 16.0;
    final ramUsed = (device.ramGb - device.availRamGb).clamp(0, device.ramGb.toDouble());
    final ramPct = device.ramGb > 0 ? (ramUsed / device.ramGb * 100).round() : 0;
    const storageTotal = 128.0;
    final storageUsed = (storageTotal - device.freeStorageGb).clamp(0, storageTotal);
    final storagePct = (storageUsed / storageTotal * 100).round();
    final cpuPct = (state.requestsPerSecond * 8 + state.temperature * 2)
        .clamp(0, 100)
        .round();
    final liveUrl = state.tunnel.publicUrl?.replaceFirst(RegExp(r'^https?://'), '') ?? _liveUrl;
    final terminalHeight = _logsFullscreen
        ? MediaQuery.sizeOf(context).height * 0.75
        : 400.0;

    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _DetailPalette.background,
        textTheme: GoogleFonts.spaceMonoTextTheme(ThemeData.dark().textTheme),
      ),
      child: Scaffold(
        backgroundColor: _DetailPalette.background,
        body: DecoratedBox(
          decoration: const BoxDecoration(color: _DetailPalette.background),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Positioned.fill(child: _MeshBackground()),
              SafeArea(
                child: Column(
                  children: [
                    _DetailTopBar(horizontalPadding: horizontalPadding),
                    Expanded(
                    child: ColoredBox(
                      color: _DetailPalette.background,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          8,
                          horizontalPadding,
                          48,
                        ),
                        children: [
                      _DetailIntro(onManualDeploy: _manualDeploy),
                      const SizedBox(height: 32),
                      _MetadataGrid(
                        serviceId: _serviceId,
                        repo: _repo,
                        liveUrl: liveUrl,
                        onCopyId: _copyServiceId,
                        onOpenUrl: () {
                          Clipboard.setData(ClipboardData(text: 'https://$liveUrl'));
                        },
                      ),
                      const SizedBox(height: 48),
                      _SecuritySection(
                        requireApiKey: state.security.requireApiKey,
                        apiKey: state.security.apiKey,
                        onToggleRequire: (val) {
                          ref.read(aiServerProvider.notifier).setRequireApiKey(val);
                        },
                        onRegenerate: () {
                          ref.read(aiServerProvider.notifier).regenerateApiKey();
                        },
                        onCopyKey: () {
                          Clipboard.setData(ClipboardData(text: state.security.apiKey));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('API Key copied to clipboard')),
                          );
                        },
                      ),
                      const SizedBox(height: 48),
                      _SystemStatusSection(
                        deviceLabel: device.cpuLabel.isNotEmpty
                            ? device.cpuLabel
                            : 'IQOO 9se',
                        batteryPercent: device.batteryPercent,
                        charging: device.batteryCharging,
                        cpuPct: cpuPct,
                        ramLabel:
                            '${ramUsed.toStringAsFixed(1)}GB / ${device.ramGb}GB',
                        ramPct: ramPct,
                        storageLabel:
                            '${storageUsed.round()}GB / ${storageTotal.round()}GB',
                        storagePct: storagePct,
                      ),
                      const SizedBox(height: 48),
                      _LatestDeploymentSection(modelName: model.name),
                      const SizedBox(height: 48),
                      _RuntimeLogsSection(
                        logs: logs,
                        logSearchController: _logSearchController,
                        logScrollController: _logScrollController,
                        terminalHeight: terminalHeight,
                        timeRange: _timeRange,
                        showCustomRange: _showCustomRange,
                        logsFullscreen: _logsFullscreen,
                        onSearchChanged: () => setState(() {}),
                        onToggleFullscreen: () =>
                            setState(() => _logsFullscreen = !_logsFullscreen),
                        onScrollToBottom: _scrollLogsToBottom,
                        onTimeRangeTap: () {
                          setState(() {
                            _showCustomRange = !_showCustomRange;
                            if (!_showCustomRange) _timeRange = 'last hour';
                          });
                        },
                        onApplyCustomRange: () =>
                            setState(() => _showCustomRange = false),
                        onCancelCustomRange: () =>
                            setState(() => _showCustomRange = false),
                      ),
                        ],
                      ),
                    ),
                  ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailPalette {
  static const background = Color(0xFF131312);
  static const primary = Color(0xFFFFFFFF);
  static const onSurface = Color(0xFFE5E2E0);
  static const onSurfaceVariant = Color(0xFFC4C7C8);
  static const onPrimary = Color(0xFF2F3131);
  static const outlineVariant = Color(0xFF444748);
  static const surfaceContainer = Color(0xFF20201E);
  static const surfaceContainerLow = Color(0xFF1C1C1A);
  static const surfaceContainerLowest = Color(0xFF0E0E0D);
  static const successGreen = Color(0xFF003924);
  static const statusSuspended = Color(0xFF897671);
  static const terminalBg = Color(0xFF0E0E0D);
}

class _LogLine {
  const _LogLine(
    this.time,
    this.instance,
    this.message, {
    this.highlight = false,
    this.success = false,
    this.warning = false,
    this.dim = false,
  });

  final String time;
  final String instance;
  final String message;
  final bool highlight;
  final bool success;
  final bool warning;
  final bool dim;
}

class _MeshBackground extends StatelessWidget {
  const _MeshBackground();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: const BoxDecoration(color: _DetailPalette.background),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.6, -0.4),
              radius: 1.2,
              colors: [
                Colors.white.withValues(alpha: 0.01),
                Colors.transparent,
              ],
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.8, 0.7),
                radius: 1.0,
                colors: [
                  Colors.white.withValues(alpha: 0.01),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailTopBar extends StatelessWidget {
  const _DetailTopBar({required this.horizontalPadding});

  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        color: _DetailPalette.background.withValues(alpha: 0.8),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: _DetailPalette.onSurface,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              shape: const RoundedRectangleBorder(
                side: BorderSide(color: Color(0x0DFFFFFF)),
              ),
            ),
            onPressed: () => Navigator.maybePop(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back, size: 20, color: _DetailPalette.onSurface),
                Text(
                  'back',
                  style: GoogleFonts.spaceMono(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: _DetailPalette.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Icon(Icons.architecture, color: _DetailPalette.primary, size: 28),
          const SizedBox(width: 8),
          Text(
            'buildify',
            style: GoogleFonts.spaceMono(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: _DetailPalette.primary,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.person_outline, color: _DetailPalette.onSurface),
          ),
        ],
      ),
    );
  }
}

class _DetailIntro extends StatelessWidget {
  const _DetailIntro({required this.onManualDeploy});

  final VoidCallback onManualDeploy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Breadcrumbs(),
        const SizedBox(height: 16),
        _ServiceHeader(modelName: 'Project---X', onManualDeploy: onManualDeploy),
      ],
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.folder_open_outlined, size: 14, color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.6)),
        Icon(Icons.chevron_right, size: 12, color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.6)),
        Text('project---x', style: _crumbStyle()),
        Icon(Icons.chevron_right, size: 12, color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.6)),
        Text('production', style: _crumbStyle(active: true)),
      ],
    );
  }

  TextStyle _crumbStyle({bool active = false}) {
    return GoogleFonts.spaceMono(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
      color: active
          ? _DetailPalette.onSurface
          : _DetailPalette.onSurfaceVariant.withValues(alpha: 0.6),
    );
  }
}

class _ServiceHeader extends StatelessWidget {
  const _ServiceHeader({
    required this.modelName,
    required this.onManualDeploy,
  });

  final String modelName;
  final VoidCallback onManualDeploy;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 640;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.language, size: 16, color: _DetailPalette.primary),
                const SizedBox(width: 8),
                Text(
                  'web service',
                  style: GoogleFonts.spaceMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: _DetailPalette.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              modelName,
              style: GoogleFonts.spaceMono(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.48,
                color: _DetailPalette.primary,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _TagChip('docker'),
              ],
            ),
          ],
        );
        final actions = _PrimaryButton(
          label: 'manual deploy',
          icon: Icons.bolt,
          onTap: onManualDeploy,
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [title, const SizedBox(height: 24), actions],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [Expanded(child: title), actions],
        );
      },
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: _DetailPalette.surfaceContainerLow,
        border: Border.all(color: _DetailPalette.outlineVariant),
      ),
      child: Text(
        label,
        style: GoogleFonts.spaceMono(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: _DetailPalette.onSurface,
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.label,
    required this.onTap,
    this.trailing,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _DetailPalette.background,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: _DetailPalette.onSurface),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: GoogleFonts.spaceMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: _DetailPalette.onSurface,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Icon(trailing, size: 16, color: _DetailPalette.onSurface),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _DetailPalette.primary,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.spaceMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: _DetailPalette.onPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 16, color: _DetailPalette.onPrimary),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataGrid extends StatelessWidget {
  const _MetadataGrid({
    required this.serviceId,
    required this.repo,
    required this.liveUrl,
    required this.onCopyId,
    required this.onOpenUrl,
  });

  final String serviceId;
  final String repo;
  final String liveUrl;
  final VoidCallback onCopyId;
  final VoidCallback onOpenUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _DetailPalette.outlineVariant),
        color: _DetailPalette.surfaceContainerLowest,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 600;
          final cells = [
            _MetaCell(
              label: 'service id',
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      serviceId,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceMono(fontSize: 14, color: _DetailPalette.onSurface),
                    ),
                  ),
                  IconButton(
                    onPressed: onCopyId,
                    icon: const Icon(Icons.content_copy, size: 16),
                    color: _DetailPalette.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            _MetaCell(
              label: 'repository',
              child: Row(
                children: [
                  const Icon(Icons.code, size: 16, color: _DetailPalette.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      repo,
                      style: GoogleFonts.spaceMono(fontSize: 14, color: _DetailPalette.onSurface),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: _DetailPalette.outlineVariant),
                    ),
                    child: Text(
                      'main',
                      style: GoogleFonts.spaceMono(fontSize: 8, letterSpacing: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            _MetaCell(
              label: 'live url',
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      liveUrl,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceMono(
                        fontSize: 14,
                        color: _DetailPalette.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: _DetailPalette.primary.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onOpenUrl,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    color: _DetailPalette.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ];
          if (stacked) {
            return Column(
              children: [
                for (var i = 0; i < cells.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: _DetailPalette.outlineVariant),
                  cells[i],
                ],
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cells[0]),
                VerticalDivider(width: 1, color: _DetailPalette.outlineVariant),
                Expanded(child: cells[1]),
                VerticalDivider(width: 1, color: _DetailPalette.outlineVariant),
                Expanded(child: cells[2]),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MetaCell extends StatelessWidget {
  const _MetaCell({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.spaceMono(
              fontSize: 8,
              letterSpacing: 0.8,
              color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _SecuritySection extends StatelessWidget {
  const _SecuritySection({
    required this.requireApiKey,
    required this.apiKey,
    required this.onToggleRequire,
    required this.onRegenerate,
    required this.onCopyKey,
  });

  final bool requireApiKey;
  final String apiKey;
  final ValueChanged<bool> onToggleRequire;
  final VoidCallback onRegenerate;
  final VoidCallback onCopyKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('api security & auth'),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: _DetailPalette.background,
            border: Border.all(
              color: _DetailPalette.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _DetailPalette.surfaceContainerLow.withValues(alpha: 0.5),
                  border: const Border(
                    bottom: BorderSide(color: _DetailPalette.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.key_outlined,
                      size: 16,
                      color: _DetailPalette.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'bearer token authentication',
                      style: GoogleFonts.spaceMono(
                        fontSize: 14,
                        color: _DetailPalette.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      requireApiKey ? 'REQUIRED' : 'OFF',
                      style: GoogleFonts.spaceMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: requireApiKey
                            ? _DetailPalette.primary
                            : _DetailPalette.statusSuspended,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: requireApiKey,
                      onChanged: onToggleRequire,
                      activeThumbColor: _DetailPalette.primary,
                      activeTrackColor: _DetailPalette.outlineVariant,
                    ),
                  ],
                ),
              ),
              if (requireApiKey)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Include header: Authorization: Bearer <key>',
                        style: GoogleFonts.spaceMono(
                          fontSize: 10,
                          color: _DetailPalette.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _DetailPalette.surfaceContainerLowest,
                          border: Border.all(color: _DetailPalette.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                apiKey.isEmpty ? 'Generating key...' : apiKey,
                                style: GoogleFonts.spaceMono(
                                  fontSize: 12,
                                  color: _DetailPalette.primary,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: onCopyKey,
                              icon: const Icon(Icons.content_copy, size: 16),
                              color: _DetailPalette.onSurfaceVariant,
                              tooltip: 'Copy API Key',
                            ),
                            IconButton(
                              onPressed: onRegenerate,
                              icon: const Icon(Icons.refresh, size: 16),
                              color: _DetailPalette.onSurfaceVariant,
                              tooltip: 'Regenerate Key',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SystemStatusSection extends StatelessWidget {
  const _SystemStatusSection({
    required this.deviceLabel,
    required this.batteryPercent,
    required this.charging,
    required this.cpuPct,
    required this.ramLabel,
    required this.ramPct,
    required this.storageLabel,
    required this.storagePct,
  });

  final String deviceLabel;
  final int batteryPercent;
  final bool charging;
  final int cpuPct;
  final String ramLabel;
  final int ramPct;
  final String storageLabel;
  final int storagePct;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('system status'),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: _DetailPalette.background,
            border: Border.all(color: _DetailPalette.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _DetailPalette.surfaceContainerLow.withValues(alpha: 0.5),
                  border: const Border(bottom: BorderSide(color: _DetailPalette.outlineVariant)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.dns_outlined, size: 16, color: _DetailPalette.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      deviceLabel.toLowerCase(),
                      style: GoogleFonts.spaceMono(fontSize: 14, color: _DetailPalette.onSurface),
                    ),
                    const Spacer(),
                    Icon(Icons.bolt, size: 14, color: _DetailPalette.successGreen),
                    const SizedBox(width: 8),
                    Text(
                      '$batteryPercent% ${charging ? 'charging' : ''}'.trim(),
                      style: GoogleFonts.spaceMono(
                        fontSize: 8,
                        letterSpacing: 0.8,
                        color: _DetailPalette.successGreen,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 600;
                    final bars = [
                      _ProgressMetric(label: 'cpu usage', value: '$cpuPct%', pct: cpuPct),
                      _ProgressMetric(label: 'ram consumption', value: ramLabel, pct: ramPct),
                      _ProgressMetric(label: 'storage', value: storageLabel, pct: storagePct),
                    ];
                    if (stacked) {
                      return Column(
                        children: [
                          for (var i = 0; i < bars.length; i++) ...[
                            if (i > 0) const SizedBox(height: 32),
                            bars[i],
                          ],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: bars[0]),
                        const SizedBox(width: 32),
                        Expanded(child: bars[1]),
                        const SizedBox(width: 32),
                        Expanded(child: bars[2]),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgressMetric extends StatelessWidget {
  const _ProgressMetric({
    required this.label,
    required this.value,
    required this.pct,
  });

  final String label;
  final String value;
  final int pct;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.spaceMono(
                fontSize: 8,
                color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            Text(
              value,
              style: GoogleFonts.spaceMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _DetailPalette.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          child: LinearProgressIndicator(
            value: pct / 100,
            minHeight: 4,
            backgroundColor: Colors.white.withValues(alpha: 0.05),
            color: _DetailPalette.primary,
          ),
        ),
      ],
    );
  }
}

class _LatestDeploymentSection extends StatelessWidget {
  const _LatestDeploymentSection({required this.modelName});

  final String modelName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('latest deployment'),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: _DetailPalette.background,
            border: Border.all(color: _DetailPalette.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: _DetailPalette.outlineVariant)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      color: _DetailPalette.successGreen,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'may 10, 2026 at 11:55 pm',
                        style: GoogleFonts.spaceMono(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _DetailPalette.onSurface,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      color: _DetailPalette.successGreen,
                      child: Text(
                        'live',
                        style: GoogleFonts.spaceMono(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: _DetailPalette.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(24),
                color: _DetailPalette.surfaceContainerLow,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: _DetailPalette.outlineVariant),
                      ),
                      child: Text(
                        '7335ca6',
                        style: GoogleFonts.spaceMono(
                          fontSize: 8,
                          color: _DetailPalette.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'deploy ${modelName.toLowerCase()} — edge inference',
                        style: GoogleFonts.spaceMono(
                          fontSize: 14,
                          color: _DetailPalette.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RuntimeLogsSection extends StatelessWidget {
  const _RuntimeLogsSection({
    required this.logs,
    required this.logSearchController,
    required this.logScrollController,
    required this.terminalHeight,
    required this.timeRange,
    required this.showCustomRange,
    required this.logsFullscreen,
    required this.onSearchChanged,
    required this.onToggleFullscreen,
    required this.onScrollToBottom,
    required this.onTimeRangeTap,
    required this.onApplyCustomRange,
    required this.onCancelCustomRange,
  });

  final List<_LogLine> logs;
  final TextEditingController logSearchController;
  final ScrollController logScrollController;
  final double terminalHeight;
  final String timeRange;
  final bool showCustomRange;
  final bool logsFullscreen;
  final VoidCallback onSearchChanged;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onScrollToBottom;
  final VoidCallback onTimeRangeTap;
  final VoidCallback onApplyCustomRange;
  final VoidCallback onCancelCustomRange;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionLabel('runtime logs')),
            IconButton(onPressed: () {}, icon: const Icon(Icons.download_outlined, size: 20)),
            IconButton(
              onPressed: onToggleFullscreen,
              icon: Icon(
                logsFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                size: 20,
              ),
              style: logsFullscreen
                  ? IconButton.styleFrom(
                      backgroundColor: _DetailPalette.primary,
                      foregroundColor: _DetailPalette.onPrimary,
                    )
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: _DetailPalette.background,
            border: Border.all(color: _DetailPalette.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: _DetailPalette.surfaceContainerLow,
                  border: Border(bottom: BorderSide(color: _DetailPalette.outlineVariant)),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 600;
                    final filters = Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _OutlineButton(
                          label: timeRange,
                          trailing: Icons.expand_more,
                          onTap: onTimeRangeTap,
                          icon: Icons.schedule,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _DetailPalette.primary.withValues(alpha: 0.1),
                            border: Border.all(color: _DetailPalette.primary),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.bolt, size: 14, color: _DetailPalette.primary),
                              const SizedBox(width: 8),
                              Text(
                                'live tail',
                                style: GoogleFonts.spaceMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _DetailPalette.primary,
                                ),
                              ),
                              const Icon(Icons.expand_more, size: 14, color: _DetailPalette.primary),
                            ],
                          ),
                        ),
                      ],
                    );
                    final search = TextField(
                      controller: logSearchController,
                      onChanged: (_) => onSearchChanged(),
                      style: GoogleFonts.spaceMono(fontSize: 14, color: _DetailPalette.onSurface),
                      decoration: InputDecoration(
                        hintText: 'search logs...',
                        hintStyle: GoogleFonts.spaceMono(
                          fontSize: 14,
                          color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.3),
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          size: 18,
                          color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: _DetailPalette.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: _DetailPalette.primary),
                        ),
                      ),
                    );
                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [filters, const SizedBox(height: 12), search],
                      );
                    }
                    return Row(
                      children: [filters, const SizedBox(width: 16), Expanded(child: search)],
                    );
                  },
                ),
              ),
              if (showCustomRange) _CustomRangePicker(
                onCancel: onCancelCustomRange,
                onApply: onApplyCustomRange,
              ),
              Stack(
                children: [
                  SizedBox(
                    height: terminalHeight,
                    child: ColoredBox(
                      color: _DetailPalette.terminalBg,
                      child: Scrollbar(
                        controller: logScrollController,
                        thumbVisibility: true,
                        child: ListView(
                          controller: logScrollController,
                          padding: const EdgeInsets.all(24),
                        children: [
                          Text(
                            'may 26',
                            style: GoogleFonts.spaceMono(
                              fontSize: 14,
                              color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.4),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ...logs.map((l) => _LogLineWidget(line: l)),
                        ],
                      ),
                    ),
                    ),
                  ),
                  Positioned(
                    right: 24,
                    bottom: 24,
                    child: Material(
                      color: _DetailPalette.primary,
                      child: InkWell(
                        onTap: onScrollToBottom,
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(Icons.arrow_downward, color: _DetailPalette.onPrimary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                height: 48,
                color: _DetailPalette.surfaceContainerLow,
                alignment: Alignment.center,
                child: const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CustomRangePicker extends StatelessWidget {
  const _CustomRangePicker({required this.onCancel, required this.onApply});

  final VoidCallback onCancel;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      color: _DetailPalette.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Custom Range Selection',
                style: GoogleFonts.spaceMono(
                  fontSize: 8,
                  letterSpacing: 1.6,
                  color: _DetailPalette.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              IconButton(onPressed: onCancel, icon: const Icon(Icons.close, size: 20)),
            ],
          ),
          const SizedBox(height: 24),
          _RangeField(label: 'START (GMT+5:30)', date: 'May 26 2026', time: '19:48:02'),
          const SizedBox(height: 16),
          _RangeField(label: 'END (GMT+5:30)', date: 'May 26 2026', time: '23:48:02'),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _OutlineButton(label: 'cancel', onTap: onCancel),
              const SizedBox(width: 12),
              _PrimaryButton(label: 'apply custom range', icon: Icons.check, onTap: onApply),
            ],
          ),
        ],
      ),
    );
  }
}

class _RangeField extends StatelessWidget {
  const _RangeField({
    required this.label,
    required this.date,
    required this.time,
  });

  final String label;
  final String date;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.spaceMono(
            fontSize: 8,
            color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: _DetailPalette.outlineVariant),
                  color: _DetailPalette.surfaceContainerLowest,
                ),
                child: Text(date, style: GoogleFonts.spaceMono(fontSize: 14)),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: _DetailPalette.outlineVariant),
                color: _DetailPalette.surfaceContainerLowest,
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 18, color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.4)),
                  const SizedBox(width: 12),
                  Text(time, style: GoogleFonts.spaceMono(fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LogLineWidget extends StatelessWidget {
  const _LogLineWidget({required this.line});

  final _LogLine line;

  @override
  Widget build(BuildContext context) {
    Color messageColor = _DetailPalette.onSurface;
    if (line.highlight) messageColor = _DetailPalette.primary;
    if (line.success) messageColor = _DetailPalette.successGreen;
    if (line.warning) messageColor = _DetailPalette.statusSuspended;
    if (line.dim) messageColor = _DetailPalette.onSurfaceVariant.withValues(alpha: 0.6);

    Widget messageChild = Text(
      line.message,
      style: GoogleFonts.spaceMono(fontSize: 14, color: messageColor),
    );
    if (line.success) {
      messageChild = Row(
        children: [
          const Icon(Icons.check_circle_outline, size: 14, color: _DetailPalette.successGreen),
          const SizedBox(width: 8),
          Expanded(child: messageChild),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              line.time,
              style: GoogleFonts.spaceMono(
                fontSize: 10,
                color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              line.instance,
              style: GoogleFonts.spaceMono(
                fontSize: 10,
                color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          Expanded(child: messageChild),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.spaceMono(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
        color: _DetailPalette.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}
