import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/ai_server_models.dart';
import '../providers/ai_server_provider.dart';
import '../services/guided_tour_service.dart';
import '../widgets/guided_tour_overlay.dart';
import 'service_detail_page.dart';

/// Model picker — matches the "select ai model" HTML screen.
class AiModelSelectPage extends ConsumerStatefulWidget {
  const AiModelSelectPage({super.key, this.onContinue});

  /// Called after [AiServerController.selectModel]; defaults to [ServiceDetailPage].
  final void Function(BuildContext context, String modelId)? onContinue;

  @override
  ConsumerState<AiModelSelectPage> createState() => _AiModelSelectPageState();
}

class _AiModelSelectPageState extends ConsumerState<AiModelSelectPage> {
  final _searchController = TextEditingController();
  String? _sizeFilter; // null = all, 'small', 'medium'
  String? _selectedId;

  final _searchFilterKey = GlobalKey();
  final _importCustomKey = GlobalKey();
  final _firstModelCardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = ref.read(aiServerProvider).selectedModelId;
      if (id.isNotEmpty) setState(() => _selectedId = id);

      _startAiModelTour();
    });
  }

  void _startAiModelTour() {
    final steps = [
      GuidedTourStep(
        title: 'Search & Size Filters',
        description:
            'Search GGUF models by architecture or filter by memory footprint (Small / Medium).',
        targetKey: _searchFilterKey,
        tooltipPosition: TooltipPosition.bottom,
      ),
      GuidedTourStep(
        title: 'Import Custom Models',
        description:
            'Clone GGUF models directly from HuggingFace repos or upload local weights.',
        targetKey: _importCustomKey,
        tooltipPosition: TooltipPosition.bottom,
      ),
      GuidedTourStep(
        title: 'Select & Run AI Engine',
        description:
            'Tap any model card (e.g. Llama 3 8B) to download weights and start the llama.cpp server.',
        targetKey: _firstModelCardKey,
        tooltipPosition: TooltipPosition.top,
      ),
    ];
    ref.read(guidedTourNotifierProvider.notifier).startTour(steps);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onSelect(String modelId) async {
    setState(() => _selectedId = modelId);
    ref.read(aiServerProvider.notifier).selectModel(modelId);
  }

  Future<void> _onContinue(String modelId) async {
    await _onSelect(modelId);
    if (!mounted) return;
    if (widget.onContinue != null) {
      widget.onContinue!(context, modelId);
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ServiceDetailPage(modelId: modelId),
      ),
    );
  }

  void _openCloneModal() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (ctx) => const _CloneRepositoryModal(),
    );
  }

  List<ModelProfile> _filteredModels(List<ModelProfile> models) {
    final q = _searchController.text.trim().toLowerCase();
    return models.where((m) {
      final meta = _modelUiMeta[m.id];
      if (_sizeFilter == 'small' && !_isSmallModel(m)) return false;
      if (_sizeFilter == 'medium' && !_isMediumModel(m)) return false;
      if (q.isEmpty) return true;
      final haystack = [
        m.name,
        m.description,
        m.sizeLabel,
        m.speed,
        m.quality,
        meta?.architecture ?? '',
        meta?.quantization ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  bool _isSmallModel(ModelProfile m) =>
      m.id == 'tinyllama-q4' || m.id == 'qwen2-1_5b-q4';

  bool _isMediumModel(ModelProfile m) => m.id == 'phi-3-mini-q4';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiServerProvider);
    final models = _filteredModels(state.models);
    final horizontalPadding = MediaQuery.sizeOf(context).width >= 768 ? 32.0 : 16.0;

    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _SelectPalette.background,
        textTheme: GoogleFonts.spaceMonoTextTheme(ThemeData.dark().textTheme),
      ),
      child: GuidedTourOverlay(
        child: Scaffold(
          backgroundColor: _SelectPalette.background,
          body: ColoredBox(
            color: _SelectPalette.background,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const Positioned.fill(child: _MeshGradientBackground()),
                Positioned(
                  top: MediaQuery.sizeOf(context).height * 0.25,
                  right: -96,
                  child: _DecorOrb(size: 256, pulse: true),
                ),
                Positioned(
                  bottom: MediaQuery.sizeOf(context).height * 0.25,
                  left: -96,
                  child: const _DecorOrb(size: 384, pulse: false),
                ),
                ColoredBox(
                  color: _SelectPalette.background,
                  child: SafeArea(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        16,
                        horizontalPadding,
                        96,
                      ),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(Icons.arrow_back,
                                color: _SelectPalette.primary),
                            tooltip: 'back',
                          ),
                        ),
                        _HeaderSection(),
                        const SizedBox(height: 48),
                        _SearchAndFilters(
                          key: _searchFilterKey,
                          controller: _searchController,
                          sizeFilter: _sizeFilter,
                          onSizeFilter: (f) => setState(() => _sizeFilter = f),
                        ),
                        const SizedBox(height: 48),
                        _ImportSection(
                          key: _importCustomKey,
                          onUpload: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Custom upload coming soon')),
                            );
                          },
                          onClone: _openCloneModal,
                        ),
                        const SizedBox(height: 40),
                        ...models.asMap().entries.map(
                          (entry) {
                            final idx = entry.key;
                            final m = entry.value;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: _ModelCard(
                                key: idx == 0 ? _firstModelCardKey : null,
                                model: m,
                                download: state.downloads[m.id],
                                selected: _selectedId == m.id,
                                onContinue: () => unawaited(_onContinue(m.id)),
                              ),
                            );
                          },
                        ),
                        if (models.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Text(
                              'no models match your filter',
                              style: GoogleFonts.spaceMono(
                                color: _SelectPalette.textDim,
                                fontSize: 14,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectPalette {
  static const background = Color(0xFF131312);
  static const primary = Color(0xFFFFFFFF);
  static const onSurface = Color(0xFFE5E2E0);
  static const onSurfaceVariant = Color(0xFFC4C7C8);
  static const textDim = Color(0xFF8E9192);
  static const surfaceCard = Color(0x6620201F);
  static const statusSuccess = Color(0xFF003924);
  static const statusWarning = Color(0xFF897671);
  static const secondary = Color(0xFFC3C0FF);
  static const onPrimaryFixed = Color(0xFF1A1C1C);
}

class _ModelUiMeta {
  const _ModelUiMeta({
    required this.architecture,
    required this.parameters,
    required this.quantization,
    required this.vramReq,
    required this.badge,
    required this.badgeColor,
    required this.badgeBorderColor,
    required this.icon,
    required this.footerText,
    required this.footerIcon,
  });

  final String architecture;
  final String parameters;
  final String quantization;
  final String vramReq;
  final String badge;
  final Color badgeColor;
  final Color badgeBorderColor;
  final IconData icon;
  final String footerText;
  final IconData footerIcon;
}

final _modelUiMeta = <String, _ModelUiMeta>{
  'tinyllama-q4': _ModelUiMeta(
    architecture: 'llama-2',
    parameters: '1.1B',
    quantization: 'Q4_K_M',
    vramReq: '~0.8GB',
    badge: 'stable',
    badgeColor: _SelectPalette.statusSuccess,
    badgeBorderColor: _SelectPalette.statusSuccess,
    icon: Icons.terminal,
    footerText: 'size: 680mb',
    footerIcon: Icons.storage_outlined,
  ),
  'qwen2-1_5b-q4': _ModelUiMeta(
    architecture: 'qwen-2',
    parameters: '1.5B',
    quantization: 'Q4_0',
    vramReq: '~1.2GB',
    badge: 'optimized',
    badgeColor: _SelectPalette.secondary,
    badgeBorderColor: _SelectPalette.secondary,
    icon: Icons.psychology_outlined,
    footerText: 'size: 940mb',
    footerIcon: Icons.cloud_download_outlined,
  ),
  'phi-3-mini-q4': _ModelUiMeta(
    architecture: 'phi-3',
    parameters: '3.8B',
    quantization: 'Q4_K_S',
    vramReq: '~2.5GB',
    badge: 'popular',
    badgeColor: _SelectPalette.statusWarning,
    badgeBorderColor: _SelectPalette.statusWarning,
    icon: Icons.memory_outlined,
    footerText: 'speed: 124 tok/s',
    footerIcon: Icons.speed_outlined,
  ),
};

_ModelUiMeta _metaFor(ModelProfile model) {
  return _modelUiMeta[model.id] ??
      _ModelUiMeta(
        architecture: model.quality.toLowerCase(),
        parameters: '${model.requiredRamGb}GB ram',
        quantization: 'Q4',
        vramReq: '~${model.requiredRamGb}GB',
        badge: model.speed.toLowerCase(),
        badgeColor: _SelectPalette.textDim,
        badgeBorderColor: _SelectPalette.textDim,
        icon: Icons.smart_toy_outlined,
        footerText: 'size: ${model.sizeLabel}',
        footerIcon: Icons.storage_outlined,
      );
}

class _MeshGradientBackground extends StatelessWidget {
  const _MeshGradientBackground();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: const DecoratedBox(
        decoration: BoxDecoration(color: _SelectPalette.background),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.2,
              colors: [Color(0x262D2D2D), _SelectPalette.background],
            ),
          ),
        ),
      ),
    );
  }
}

class _DecorOrb extends StatefulWidget {
  const _DecorOrb({required this.size, required this.pulse});

  final double size;
  final bool pulse;

  @override
  State<_DecorOrb> createState() => _DecorOrbState();
}

class _DecorOrbState extends State<_DecorOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    if (widget.pulse) _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final opacity = widget.pulse ? 0.04 + (_controller.value * 0.03) : 0.05;
        return Opacity(opacity: opacity, child: child);
      },
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _HeaderSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'deployment_sequence / engine_select',
          style: GoogleFonts.spaceMono(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: _SelectPalette.textDim,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'select ai model',
          style: GoogleFonts.spaceMono(
            fontSize: 24,
            height: 1.33,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.48,
            color: _SelectPalette.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose a pre-quantized inference engine optimized for your edge '
          'environment. Higher parameter counts require increased memory overhead.',
          style: GoogleFonts.spaceMono(
            fontSize: 14,
            height: 1.43,
            color: _SelectPalette.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SearchAndFilters extends StatelessWidget {
  const _SearchAndFilters({
    super.key,
    required this.controller,
    required this.sizeFilter,
    required this.onSizeFilter,
  });

  final TextEditingController controller;
  final String? sizeFilter;
  final ValueChanged<String?> onSizeFilter;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 600;
        final search = TextField(
          controller: controller,
          style: GoogleFonts.spaceMono(fontSize: 14, color: _SelectPalette.onSurface),
          decoration: InputDecoration(
            hintText: 'filter models by architecture or size...',
            hintStyle: GoogleFonts.spaceMono(
              fontSize: 14,
              color: _SelectPalette.textDim,
            ),
            prefixIcon: const Icon(Icons.search, color: _SelectPalette.textDim),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
        );
        final filters = Row(
          children: [
            _SizeFilterChip(
              label: 'small',
              selected: sizeFilter == 'small',
              onTap: () => onSizeFilter(sizeFilter == 'small' ? null : 'small'),
            ),
            const SizedBox(width: 8),
            _SizeFilterChip(
              label: 'medium',
              selected: sizeFilter == 'medium',
              onTap: () => onSizeFilter(sizeFilter == 'medium' ? null : 'medium'),
            ),
          ],
        );

        if (stacked) {
          return Column(
            children: [search, const SizedBox(height: 16), filters],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: search),
            const SizedBox(width: 16),
            filters,
          ],
        );
      },
    );
  }
}

class _SizeFilterChip extends StatelessWidget {
  const _SizeFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? Colors.white.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.1),
            ),
            color: selected ? Colors.white.withValues(alpha: 0.08) : null,
          ),
          child: Text(
            label,
            style: GoogleFonts.spaceMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: _SelectPalette.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ImportSection extends StatelessWidget {
  const _ImportSection({
    super.key,
    required this.onUpload,
    required this.onClone,
  });

  final VoidCallback onUpload;
  final VoidCallback onClone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'import source model',
            style: GoogleFonts.spaceMono(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.36,
              color: _SelectPalette.primary.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 520;
              final upload = _ImportButton(
                icon: Icons.upload_file_outlined,
                title: 'upload custom model',
                subtitle: 'GGUF / SAFE-TENSORS',
                onTap: onUpload,
              );
              final clone = _ImportButton(
                icon: Icons.account_tree_outlined,
                title: 'clone from repository',
                subtitle: 'GIT / HUGGINGFACE',
                onTap: onClone,
              );
              if (stacked) {
                return Column(children: [upload, const SizedBox(height: 16), clone]);
              }
              return Row(
                children: [
                  Expanded(child: upload),
                  const SizedBox(width: 16),
                  Expanded(child: clone),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ImportButton extends StatelessWidget {
  const _ImportButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _SelectPalette.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: _SelectPalette.primary, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.spaceMono(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _SelectPalette.primary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.spaceMono(
                        fontSize: 10,
                        letterSpacing: -0.5,
                        color: _SelectPalette.textDim,
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

class _ModelCard extends StatefulWidget {
  const _ModelCard({
    super.key,
    required this.model,
    required this.download,
    required this.selected,
    required this.onContinue,
  });

  final ModelProfile model;
  final ModelDownload? download;
  final bool selected;
  final VoidCallback onContinue;

  @override
  State<_ModelCard> createState() => _ModelCardState();
}

class _ModelCardState extends State<_ModelCard> {
  Offset? _pointer;

  @override
  Widget build(BuildContext context) {
    final meta = _metaFor(widget.model);
    final displayName = widget.model.name.toLowerCase();
    final download = widget.download;
    final downloaded = download?.status == ModelDownloadStatus.downloaded;
    final downloading = download?.status == ModelDownloadStatus.downloading;
    final bg = _pointer != null
        ? BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(
                (_pointer!.dx / 300).clamp(-1.0, 1.0),
                (_pointer!.dy / 200).clamp(-1.0, 1.0),
              ),
              radius: 0.9,
              colors: [
                Colors.white.withValues(alpha: 0.06),
                _SelectPalette.surfaceCard,
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.selected
                  ? Colors.white.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.05),
            ),
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.05),
                      blurRadius: 20,
                    ),
                  ]
                : null,
          )
        : BoxDecoration(
            color: _SelectPalette.surfaceCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.selected
                  ? Colors.white.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.05),
            ),
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.05),
                      blurRadius: 20,
                    ),
                  ]
                : null,
          );

    return MouseRegion(
      onEnter: (_) {},
      onExit: (_) => setState(() => _pointer = null),
      child: Listener(
        onPointerHover: (e) => setState(() => _pointer = e.localPosition),
        onPointerMove: (e) => setState(() => _pointer = e.localPosition),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: bg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withValues(alpha: 0.05),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.1),
                                      ),
                                    ),
                                    child: Icon(meta.icon, color: _SelectPalette.primary),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          displayName,
                                          style: GoogleFonts.spaceMono(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.36,
                                            color: _SelectPalette.primary,
                                          ),
                                        ),
                                        Text(
                                          'architecture: ${meta.architecture}',
                                          style: GoogleFonts.spaceMono(
                                            fontSize: 8,
                                            letterSpacing: 0.8,
                                            color: _SelectPalette.textDim,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _Badge(
                              label: meta.badge,
                              color: meta.badgeColor,
                              borderColor: meta.badgeBorderColor,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _MetadataRow(meta: meta),
                        if (downloading) ...[
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: download!.progress,
                              minHeight: 8,
                              backgroundColor: Colors.white.withValues(alpha: 0.08),
                              color: _SelectPalette.primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'downloading ${(download.progress * 100).round()}%',
                            style: GoogleFonts.spaceMono(
                              fontSize: 10,
                              color: _SelectPalette.textDim,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      border: Border(
                        top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(meta.footerIcon, size: 18, color: _SelectPalette.textDim),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                downloaded
                                    ? 'model ready on device'
                                    : downloading
                                        ? 'fetching weights…'
                                        : meta.footerText,
                                style: GoogleFonts.spaceMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                  color: _SelectPalette.textDim,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          children: [
                            _ShinyContinueButton(
                              enabled: !downloading,
                              onPressed: widget.onContinue,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.color,
    required this.borderColor,
  });

  final String label;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: GoogleFonts.spaceMono(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
          color: _SelectPalette.primary,
        ),
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.meta});

  final _ModelUiMeta meta;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        color: Colors.white.withValues(alpha: 0.02),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(child: _MetaCell(label: 'parameters', value: meta.parameters)),
            Container(width: 1, color: Colors.white.withValues(alpha: 0.05)),
            Expanded(child: _MetaCell(label: 'quantization', value: meta.quantization)),
            Container(width: 1, color: Colors.white.withValues(alpha: 0.05)),
            Expanded(child: _MetaCell(label: 'vram req', value: meta.vramReq)),
          ],
        ),
      ),
    );
  }
}

class _MetaCell extends StatelessWidget {
  const _MetaCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.spaceMono(
              fontSize: 8,
              letterSpacing: 0.8,
              color: _SelectPalette.textDim,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.spaceMono(
              fontSize: 14,
              color: _SelectPalette.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShinyContinueButton extends StatefulWidget {
  const _ShinyContinueButton({
    required this.onPressed,
    this.label = 'CONTINUE',
    this.enabled = true,
  });

  final VoidCallback onPressed;
  final String label;
  final bool enabled;

  @override
  State<_ShinyContinueButton> createState() => _ShinyContinueButtonState();
}

class _ShinyContinueButtonState extends State<_ShinyContinueButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.enabled ? widget.onPressed : null,
      child: AnimatedScale(
        scale: _pressed && widget.enabled ? 0.95 : 1,
        duration: const Duration(milliseconds: 100),
        child: Opacity(
          opacity: widget.enabled ? 1 : 0.4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
            decoration: BoxDecoration(
              color: _SelectPalette.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.label,
              style: GoogleFonts.spaceMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
                color: _SelectPalette.onPrimaryFixed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CloneRepositoryModal extends StatefulWidget {
  const _CloneRepositoryModal();

  @override
  State<_CloneRepositoryModal> createState() => _CloneRepositoryModalState();
}

class _CloneRepositoryModalState extends State<_CloneRepositoryModal> {
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 512),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: _SelectPalette.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _SelectPalette.primary),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'clone from repository',
              style: GoogleFonts.spaceMono(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _SelectPalette.primary,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _urlController,
              style: GoogleFonts.spaceMono(fontSize: 14, color: _SelectPalette.onSurface),
              decoration: InputDecoration(
                hintText: 'paste repository link (git/huggingface)...',
                hintStyle: GoogleFonts.spaceMono(
                  fontSize: 14,
                  color: _SelectPalette.textDim,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.2),
                    style: BorderStyle.solid,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _SelectPalette.primary, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'cancel',
                    style: GoogleFonts.spaceMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                      color: _SelectPalette.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                _ShinyContinueButton(
                  label: 'CLONE',
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Clone started (demo)')),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
