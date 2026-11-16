import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 4 trạng thái chuyển động tương tác của Spatial Card Deck
enum SpatialDeckMode {
  cluster,
  expanded,
  diagonalCascade,
  horizontalStrip,
  collapsed,
}

/// Dữ liệu cho mỗi thẻ trong bộ 8 thẻ Editorial Minimalist
class SpatialCardData {
  final String tag;
  final String title;
  final String subtitle;
  final String metaNote;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool useGradient;
  final int patternVariant;

  const SpatialCardData({
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.metaNote,
    required this.backgroundColor,
    required this.foregroundColor,
    this.useGradient = false,
    this.patternVariant = 0,
  });
}

/// Bộ 8 thẻ chuẩn thẩm mỹ Editorial (#565C43, #ECEBE6, #18181A) bản địa hóa cho Blockchain Verifier
const List<SpatialCardData> kDefaultBlockchainDeckCards = [
  SpatialCardData(
    tag: '2026 NOV',
    title: 'BLOCKCHAIN',
    subtitle: 'Sepolia Testnet',
    metaNote: 'Immutable Ledger',
    backgroundColor: Color(0xFFECEBE6),
    foregroundColor: Color(0xFF141416),
    patternVariant: 0,
  ),
  SpatialCardData(
    tag: 'VERIFIED',
    title: 'SHA-256',
    subtitle: 'Zero Tamper',
    metaNote: 'Cryptographic Proof',
    backgroundColor: Color(0xFF565C43),
    foregroundColor: Color(0xFFECEBE6),
    patternVariant: 1,
  ),
  SpatialCardData(
    tag: 'ISSUER',
    title: 'ĐẠI HỌC',
    subtitle: 'Cán bộ đào tạo',
    metaNote: 'Authorized Signer',
    backgroundColor: Color(0xFF18181A),
    foregroundColor: Color(0xFFECEBE6),
    useGradient: true,
    patternVariant: 2,
  ),
  SpatialCardData(
    tag: 'PORTFOLIO',
    title: 'SỔ TAY',
    subtitle: 'Offline SQLite',
    metaNote: 'Instant Access',
    backgroundColor: Color(0xFFECEBE6),
    foregroundColor: Color(0xFF141416),
    patternVariant: 3,
  ),
  SpatialCardData(
    tag: 'EMPLOYER',
    title: 'HR AUDIT',
    subtitle: 'Thẩm định tuyển dụng',
    metaNote: 'Verified Report',
    backgroundColor: Color(0xFF18181A),
    foregroundColor: Color(0xFFECEBE6),
    useGradient: true,
    patternVariant: 0,
  ),
  SpatialCardData(
    tag: 'INSTANT',
    title: 'QR SEAL',
    subtitle: 'Quét 1 chạm',
    metaNote: 'Real-time Check',
    backgroundColor: Color(0xFF565C43),
    foregroundColor: Color(0xFFECEBE6),
    patternVariant: 1,
  ),
  SpatialCardData(
    tag: 'ETH RPC',
    title: 'ON-CHAIN',
    subtitle: 'Smart Contract',
    metaNote: 'Public Registry',
    backgroundColor: Color(0xFFECEBE6),
    foregroundColor: Color(0xFF141416),
    patternVariant: 2,
  ),
  SpatialCardData(
    tag: 'TRUST',
    title: 'CHÍNH CHỦ',
    subtitle: 'Keccak-256',
    metaNote: 'Digital Signature',
    backgroundColor: Color(0xFF18181A),
    foregroundColor: Color(0xFFECEBE6),
    useGradient: true,
    patternVariant: 3,
  ),
];

/// Bộ tích phân vật lý lò xo (mass: 1, stiffness: 240, damping: 26)
class _SpringScalar {
  double value;
  double target;
  double velocity = 0.0;

  static const double stiffness = 240.0;
  static const double damping = 20.0;
  static const double mass = 1.0;

  _SpringScalar(this.value) : target = value;

  bool step(double dt) {
    // Chia nhỏ bước thời gian nếu frame chậm để đảm bảo ổn định tuyệt đối
    final int subSteps = dt > 0.016 ? 2 : 1;
    final double h = dt / subSteps;

    for (int i = 0; i < subSteps; i++) {
      final double displacement = value - target;
      final double springForce = -stiffness * displacement;
      final double dampingForce = -damping * velocity;
      final double acceleration = (springForce + dampingForce) / mass;
      velocity += acceleration * h;
      value += velocity * h;
    }

    if ((value - target).abs() < 0.0005 && velocity.abs() < 0.0005) {
      value = target;
      velocity = 0.0;
      return false;
    }
    return true;
  }
}

class _CardSpringState {
  final _SpringScalar x = _SpringScalar(0);
  final _SpringScalar y = _SpringScalar(0);
  final _SpringScalar scale = _SpringScalar(1);
  final _SpringScalar rotation = _SpringScalar(0);
  final _SpringScalar opacity = _SpringScalar(1);
  double zPriority = 0;

  bool step(double dt) {
    bool active = false;
    if (x.step(dt)) active = true;
    if (y.step(dt)) active = true;
    if (scale.step(dt)) active = true;
    if (rotation.step(dt)) active = true;
    if (opacity.step(dt)) active = true;
    return active;
  }
}

/// Interactive Spatial Card Deck 8 thẻ với 4 trạng thái chuyển động mượt 60fps
class SpatialCardDeck extends StatefulWidget {
  final List<SpatialCardData> cards;
  final SpatialDeckMode mode;
  final ValueChanged<SpatialDeckMode>? onModeChanged;
  final double baseCardSize;
  final bool autoPlay;

  const SpatialCardDeck({
    super.key,
    this.cards = kDefaultBlockchainDeckCards,
    this.mode = SpatialDeckMode.cluster,
    this.onModeChanged,
    this.baseCardSize = 132,
    this.autoPlay = false,
  });

  @override
  State<SpatialCardDeck> createState() => SpatialCardDeckState();
}

class SpatialCardDeckState extends State<SpatialCardDeck>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  Timer? _autoTimer;
  int _autoStep = 0;
  int _autoCardCursor = 0;
  bool _isPausedByUser = false;

  late List<_CardSpringState> _cardStates;
  late SpatialDeckMode _mode;
  SpatialDeckMode _modeBeforeExpand = SpatialDeckMode.cluster;
  int? _expandedIndex;
  double _scrollIndex = 3.5;

  // Cấu hình cụm Organic Cluster cố định cho 8 thẻ
  static const List<Offset> _clusterOffsets = [
    Offset(-42, -34),
    Offset(38, -28),
    Offset(-54, 18),
    Offset(48, 24),
    Offset(-16, -48),
    Offset(18, 46),
    Offset(-24, 6),
    Offset(14, -4),
  ];

  static const List<double> _clusterRotations = [
    -0.14,
    0.12,
    -0.09,
    0.15,
    0.06,
    -0.11,
    0.04,
    -0.05,
  ];

  @override
  void initState() {
    super.initState();
    _mode = widget.mode;
    _cardStates = List.generate(widget.cards.length, (_) => _CardSpringState());
    _applyTargets(immediate: true);
    _ticker = createTicker(_onTick);
    if (widget.autoPlay) {
      _scheduleNextAutoStep(const Duration(milliseconds: 2200));
    }
  }

  @override
  void didUpdateWidget(covariant SpatialCardDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode && widget.mode != _mode) {
      setMode(widget.mode);
    }
    if (oldWidget.autoPlay != widget.autoPlay) {
      if (widget.autoPlay) {
        _isPausedByUser = false;
        _autoStep = 0;
        _scheduleNextAutoStep(const Duration(milliseconds: 1800));
      } else {
        _autoTimer?.cancel();
        _autoTimer = null;
      }
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _scheduleNextAutoStep(Duration delay) {
    _autoTimer?.cancel();
    if (!widget.autoPlay || _isPausedByUser || !mounted) return;
    _autoTimer = Timer(delay, _runAutoChoreographyStep);
  }

  void _runAutoChoreographyStep() {
    if (!mounted || !widget.autoPlay || _isPausedByUser) return;

    final int count = widget.cards.length;
    switch (_autoStep) {
      case 0:
        // Nhịp 1 -> Phóng to 1 thẻ tiêu điểm (Tap-to-Expand)
        final int cardIdx = _autoCardCursor % count;
        _autoCardCursor++;
        setState(() {
          _modeBeforeExpand = SpatialDeckMode.cluster;
          _mode = SpatialDeckMode.expanded;
          _expandedIndex = cardIdx;
          _applyTargets();
        });
        _ensureTicking();
        _autoStep = 1;
        _scheduleNextAutoStep(const Duration(milliseconds: 3600));
        break;
      case 1:
        // Nhịp 2 -> Chuyển Thác chéo (Diagonal Cascade) từ trên-trái xuống
        setState(() {
          _mode = SpatialDeckMode.diagonalCascade;
          _expandedIndex = null;
          _scrollIndex = 2.0;
          _applyTargets();
        });
        _ensureTicking();
        _autoStep = 2;
        _scheduleNextAutoStep(const Duration(milliseconds: 2600));
        break;
      case 2:
        // Nhịp 3 -> Tự động lướt dọc theo Thác chéo
        setState(() {
          _mode = SpatialDeckMode.diagonalCascade;
          _scrollIndex = (count - 2.5).clamp(0.0, count - 1.0);
          _applyTargets();
        });
        _ensureTicking();
        _autoStep = 3;
        _scheduleNextAutoStep(const Duration(milliseconds: 2800));
        break;
      case 3:
        // Nhịp 4 -> Chuyển sang Dải ngang (Horizontal Strip)
        setState(() {
          _mode = SpatialDeckMode.horizontalStrip;
          _scrollIndex = (count / 2).floorToDouble();
          _applyTargets();
        });
        _ensureTicking();
        _autoStep = 4;
        _scheduleNextAutoStep(const Duration(milliseconds: 3000));
        break;
      case 4:
        // Nhịp 5 -> Thu gọn về sau thẻ trung tâm (Center Collapse)
        setState(() {
          _mode = SpatialDeckMode.collapsed;
          _applyTargets();
        });
        _ensureTicking();
        _autoStep = 5;
        _scheduleNextAutoStep(const Duration(milliseconds: 1400));
        break;
      default:
        // Nhịp 6 -> Bung lò xo trở lại Cụm Organic Cluster ban đầu
        setState(() {
          _mode = SpatialDeckMode.cluster;
          _applyTargets();
        });
        _ensureTicking();
        _autoStep = 0;
        _scheduleNextAutoStep(const Duration(milliseconds: 3200));
        break;
    }
  }

  void setMode(SpatialDeckMode newMode) {
    if (_mode == newMode && newMode != SpatialDeckMode.expanded) return;
    setState(() {
      _mode = newMode;
      if (newMode != SpatialDeckMode.expanded) {
        _expandedIndex = null;
      }
      _applyTargets();
    });
    _ensureTicking();
  }

  /// Chuyển từ Horizontal Strip -> Center Collapse -> Spring về Cluster
  Future<void> playCollapseToClusterSequence() async {
    setMode(SpatialDeckMode.horizontalStrip);
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (!mounted) return;
    setMode(SpatialDeckMode.collapsed);
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    setMode(SpatialDeckMode.cluster);
    widget.onModeChanged?.call(SpatialDeckMode.cluster);
  }

  void _ensureTicking() {
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final double dt = _lastTick == Duration.zero
        ? (1.0 / 60.0)
        : ((elapsed - _lastTick).inMicroseconds / 1000000.0).clamp(0.001, 0.033);
    _lastTick = elapsed;

    bool anyActive = false;
    for (final state in _cardStates) {
      if (state.step(dt)) {
        anyActive = true;
      }
    }

    if (mounted) {
      setState(() {});
    }

    if (!anyActive && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _applyTargets({bool immediate = false}) {
    final int count = widget.cards.length;
    final int activeCenter = _scrollIndex.round().clamp(0, count - 1);

    for (int i = 0; i < count; i++) {
      final state = _cardStates[i];
      double tx = 0;
      double ty = 0;
      double tScale = 1.0;
      double tRot = 0.0;
      double tOpacity = 1.0;
      double tz = i.toDouble();

      switch (_mode) {
        case SpatialDeckMode.cluster:
          final offset = _clusterOffsets[i % _clusterOffsets.length];
          tx = offset.dx;
          ty = offset.dy;
          tRot = _clusterRotations[i % _clusterRotations.length];
          tScale = 0.94 + (i * 0.012);
          tOpacity = 1.0;
          tz = i.toDouble();
          break;

        case SpatialDeckMode.expanded:
          if (i == _expandedIndex) {
            tx = 0;
            ty = 0;
            tScale = 2.05;
            tRot = 0;
            tOpacity = 1.0;
            tz = 100.0;
          } else {
            final offset = _clusterOffsets[i % _clusterOffsets.length];
            tx = offset.dx * 1.45;
            ty = offset.dy * 1.45;
            tRot = _clusterRotations[i % _clusterRotations.length] * 1.3;
            tScale = 0.82;
            tOpacity = 0.24;
            tz = i.toDouble();
          }
          break;

        case SpatialDeckMode.diagonalCascade:
          final double diff = i - _scrollIndex;
          final double absDiff = diff.abs();
          tx = diff * 54.0;
          ty = diff * 42.0;
          // Parallax & scale 1.05x cho thẻ trung tâm
          tScale = (1.05 - absDiff * 0.09).clamp(0.74, 1.05);
          tRot = diff * 0.045;
          tOpacity = (1.0 - absDiff * 0.16).clamp(0.32, 1.0);
          tz = 50.0 - absDiff * 5.0;
          break;

        case SpatialDeckMode.horizontalStrip:
          final double diff = i - _scrollIndex;
          final double absDiff = diff.abs();
          tx = diff * (widget.baseCardSize * 0.96);
          ty = absDiff * 4.0;
          tScale = (1.06 - absDiff * 0.11).clamp(0.76, 1.06);
          tRot = diff * 0.02;
          tOpacity = (1.0 - absDiff * 0.2).clamp(0.28, 1.0);
          tz = 50.0 - absDiff * 5.0;
          break;

        case SpatialDeckMode.collapsed:
          if (i == activeCenter) {
            tx = 0;
            ty = 0;
            tScale = 1.12;
            tRot = 0;
            tOpacity = 1.0;
            tz = 100.0;
          } else {
            tx = 0;
            ty = 0;
            tScale = 0.86;
            tRot = 0;
            tOpacity = 0.0;
            tz = i.toDouble();
          }
          break;
      }

      state.x.target = tx;
      state.y.target = ty;
      state.scale.target = tScale;
      state.rotation.target = tRot;
      state.opacity.target = tOpacity;
      state.zPriority = tz;

      if (immediate) {
        state.x.value = tx;
        state.y.value = ty;
        state.scale.value = tScale;
        state.rotation.value = tRot;
        state.opacity.value = tOpacity;
      }
    }
  }

  void _handleCardTap(int index) {
    if (_mode == SpatialDeckMode.expanded) {
      if (_expandedIndex == index) {
        setState(() {
          _mode = _modeBeforeExpand;
          _expandedIndex = null;
          _isPausedByUser = false;
          _applyTargets();
        });
        widget.onModeChanged?.call(_mode);
        if (widget.autoPlay) {
          _scheduleNextAutoStep(const Duration(milliseconds: 3600));
        }
      } else {
        setState(() {
          _expandedIndex = index;
          _isPausedByUser = true;
          _applyTargets();
        });
        _autoTimer?.cancel();
      }
    } else {
      _modeBeforeExpand = _mode == SpatialDeckMode.collapsed
          ? SpatialDeckMode.cluster
          : _mode;
      _autoTimer?.cancel();
      setState(() {
        _mode = SpatialDeckMode.expanded;
        _expandedIndex = index;
        _isPausedByUser = true;
        _applyTargets();
      });
      widget.onModeChanged?.call(SpatialDeckMode.expanded);
    }
    _ensureTicking();
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_mode == SpatialDeckMode.expanded) return;

    if (_mode == SpatialDeckMode.cluster || _mode == SpatialDeckMode.collapsed) {
      _mode = SpatialDeckMode.diagonalCascade;
      widget.onModeChanged?.call(SpatialDeckMode.diagonalCascade);
    }

    final double delta = _mode == SpatialDeckMode.diagonalCascade
        ? (details.delta.dx + details.delta.dy) * 0.0085
        : details.delta.dx * 0.011;

    setState(() {
      _scrollIndex =
          (_scrollIndex - delta).clamp(0.0, widget.cards.length - 1.0);
      _applyTargets();
    });
    _ensureTicking();
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_mode == SpatialDeckMode.diagonalCascade ||
        _mode == SpatialDeckMode.horizontalStrip) {
      setState(() {
        _scrollIndex = _scrollIndex.roundToDouble();
        _applyTargets();
      });
      _ensureTicking();
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<int> drawOrder = List.generate(widget.cards.length, (i) => i)
      ..sort(
        (a, b) => _cardStates[a].zPriority.compareTo(_cardStates[b].zPriority),
      );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanUpdate: _handlePanUpdate,
      onPanEnd: _handlePanEnd,
      onTap: () {
        if (_mode == SpatialDeckMode.expanded) {
          setState(() {
            _mode = _modeBeforeExpand;
            _expandedIndex = null;
            _applyTargets();
          });
          widget.onModeChanged?.call(_mode);
          _ensureTicking();
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double maxSide = math.min(
            constraints.maxWidth * 0.42,
            constraints.maxHeight * 0.44,
          );
          final double cardSize =
              math.min(widget.baseCardSize, maxSide).clamp(88.0, 142.0);

          return SizedBox.expand(
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: drawOrder.map((index) {
                final card = widget.cards[index];
                final state = _cardStates[index];

                return Transform.translate(
                  offset: Offset(state.x.value, state.y.value),
                  child: Transform.rotate(
                    angle: state.rotation.value,
                    child: Transform.scale(
                      scale: state.scale.value,
                      child: Opacity(
                        opacity: state.opacity.value.clamp(0.0, 1.0),
                        child: GestureDetector(
                          onTap: () => _handleCardTap(index),
                          child: _EditorialCard(
                            data: card,
                            size: cardSize,
                            isFocused: _mode == SpatialDeckMode.expanded &&
                                _expandedIndex == index,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}

class _EditorialCard extends StatelessWidget {
  final SpatialCardData data;
  final double size;
  final bool isFocused;

  const _EditorialCard({
    required this.data,
    required this.size,
    this.isFocused = false,
  });

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: data.useGradient ? null : data.backgroundColor,
        gradient: data.useGradient
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF232327), Color(0xFF141416)],
              )
            : null,
        border: Border.all(
          color: isFocused
              ? const Color(0xFFECEBE6).withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.1),
          width: isFocused ? 1.4 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isFocused ? 0.65 : 0.42),
            blurRadius: isFocused ? 28 : 16,
            offset: Offset(0, isFocused ? 14 : 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Họa tiết chấm bi hình học nền
          Positioned.fill(
            child: CustomPaint(
              painter: _GeometricDotPatternPainter(
                color: data.foregroundColor.withValues(alpha: 0.14),
                variant: data.patternVariant,
              ),
            ),
          ),
          // Nội dung Typography tối giản
          Padding(
            padding: EdgeInsets.all(size * 0.12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        data.tag,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: size * 0.085,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: data.foregroundColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    Container(
                      width: size * 0.055,
                      height: size * 0.055,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: data.foregroundColor.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    data.title,
                    style: TextStyle(
                      fontSize: size * 0.145,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: data.foregroundColor,
                    ),
                  ),
                ),
                SizedBox(height: size * 0.02),
                Text(
                  data.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: size * 0.085,
                    fontWeight: FontWeight.w500,
                    color: data.foregroundColor.withValues(alpha: 0.8),
                  ),
                ),
                Text(
                  data.metaNote,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: size * 0.072,
                    color: data.foregroundColor.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _GeometricDotPatternPainter extends CustomPainter {
  final Color color;
  final int variant;

  const _GeometricDotPatternPainter({
    required this.color,
    required this.variant,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;

    if (variant == 0 || variant == 2) {
      // Lưới chấm bi góc phải trên
      const int cols = 5;
      const int rows = 4;
      final double spacing = size.width * 0.095;
      final double startX = size.width * 0.48;
      final double startY = size.height * 0.18;

      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          if (variant == 2 && (r + c).isOdd) continue;
          canvas.drawCircle(
            Offset(startX + c * spacing, startY + r * spacing),
            size.width * 0.014,
            paint,
          );
        }
      }
    } else if (variant == 1) {
      // Vòng tròn chấm bi đồng tâm tối giản
      final center = Offset(size.width * 0.74, size.height * 0.34);
      final double radius = size.width * 0.17;
      for (int i = 0; i < 10; i++) {
        final angle = (i / 10.0) * math.pi * 2;
        canvas.drawCircle(
          Offset(
            center.dx + math.cos(angle) * radius,
            center.dy + math.sin(angle) * radius,
          ),
          size.width * 0.016,
          paint,
        );
      }
    } else {
      // Đường chéo chấm bi tinh tế
      for (int i = 0; i < 6; i++) {
        final t = i / 5.0;
        canvas.drawCircle(
          Offset(
            size.width * (0.42 + t * 0.42),
            size.height * (0.48 - t * 0.28),
          ),
          size.width * 0.016,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GeometricDotPatternPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.variant != variant;
  }
}
