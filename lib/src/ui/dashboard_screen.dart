import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../ml/platform_classifier.dart';
import '../state/sibi_state.dart';
import 'camera_view.dart';
import 'theme.dart';
import 'animated_tutorial_card.dart';
import 'spotlight_overlay.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

class DashboardScreen extends StatefulWidget {
  final PlatformClassifier classifier;

  const DashboardScreen({super.key, required this.classifier});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

enum TutorialStep { none, pressStart, performGesture, pressCopy, pressDelete, finished }

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0; 
  bool _isExpanded = false; 
  final GlobalKey<CameraViewState> _cameraKey = GlobalKey<CameraViewState>();

  // Tutorial State
  TutorialStep _tutorialStep = TutorialStep.none;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isTutorialListening = false;
  String _previousText = '';
  
  // Spotlight keys
  final GlobalKey _startKey = GlobalKey();
  final GlobalKey _copyKey = GlobalKey();
  final GlobalKey _deleteKey = GlobalKey();
  Rect? _currentTargetRect;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    
    _pulseAnimation = TweenSequence([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.15).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 20),
      TweenSequenceItem(tween: Tween<double>(begin: 1.15, end: 1.0).chain(CurveTween(curve: Curves.bounceOut)), weight: 40),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 40),
    ]).animate(_pulseController);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _startTutorial() {
    setState(() {
      _tutorialStep = TutorialStep.pressStart;
      _isTutorialListening = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkTutorialProgress(Provider.of<SibiState>(context, listen: false));
    });
  }

  void _exitTutorial() {
    setState(() {
      _tutorialStep = TutorialStep.none;
      _isTutorialListening = false;
      _currentTargetRect = null;
    });
  }

  void _checkTutorialProgress(SibiState state) {
    if (!_isTutorialListening) return;

    if (_tutorialStep == TutorialStep.pressStart) {
      if (state.isCameraActive && !state.isPaused) {
        setState(() => _tutorialStep = TutorialStep.performGesture);
        _previousText = state.translatedText;
      }
    } else if (_tutorialStep == TutorialStep.performGesture) {
      if (state.translatedText != _previousText && state.translatedText.isNotEmpty) {
        setState(() => _tutorialStep = TutorialStep.pressCopy);
      }
    } else if (_tutorialStep == TutorialStep.pressDelete) {
      if (state.translatedText.isEmpty) {
        setState(() => _tutorialStep = TutorialStep.finished);
      }
    }
    
    // Always update spotlight rect to follow the current active key
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateSpotlightRect();
    });
  }

  void _updateSpotlightRect() {
    GlobalKey? activeKey;
    if (_tutorialStep == TutorialStep.pressStart) activeKey = _startKey;
    if (_tutorialStep == TutorialStep.pressCopy) activeKey = _copyKey;
    if (_tutorialStep == TutorialStep.pressDelete) activeKey = _deleteKey;

    if (activeKey != null && activeKey.currentContext != null) {
      final RenderBox box = activeKey.currentContext!.findRenderObject() as RenderBox;
      final Offset position = box.localToGlobal(Offset.zero);
      final newRect = Rect.fromLTWH(position.dx, position.dy, box.size.width, box.size.height);
      if (_currentTargetRect != newRect) {
        setState(() {
          _currentTargetRect = newRect;
        });
      }
    } else {
      if (_currentTargetRect != null) {
        setState(() {
          _currentTargetRect = null;
        });
      }
    }
  }

  void _showTutorialDialog() {
    // Digantikan oleh tutorial interaktif
    _startTutorial();
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<SibiState>(context);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final contentBgColor = isDark ? AppTheme.spaceDark : AppTheme.bgLightContent;

    if (_isTutorialListening) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkTutorialProgress(state));
    }

    return Scaffold(
      backgroundColor: contentBgColor,
      appBar: !isDesktop && !_isExpanded 
          ? AppBar(
              title: Text(
                'SIBI Real-time', 
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.primaryGreen,
                )
              ),
              backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
              elevation: 0,
              iconTheme: IconThemeData(color: isDark ? Colors.white : AppTheme.primaryGreen),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1.0),
                child: Container(
                  color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0),
                  height: 1.0,
                ),
              ),
              actions: [
                _buildModelStatusBadge(state, isDark),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    state.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    color: isDark ? Colors.white70 : AppTheme.primaryGreen,
                  ),
                  onPressed: () => state.toggleTheme(),
                ),
                const SizedBox(width: 8),
              ],
            )
          : null,
      drawer: !isDesktop ? Drawer(
        child: SafeArea(child: _buildSidebar(isDark)),
      ) : null,
      body: Stack(
        children: [
          SafeArea(
            child: Row(
          children: [
            if (isDesktop && !_isExpanded) _buildSidebar(isDark),
            
            Expanded(
              child: Column(
                children: [
                  // Desktop Header
                  if (isDesktop && !_isExpanded)
                    Container(
                      height: 60,
                      color: isDark ? AppTheme.spaceDark : const Color(0xFFE2E8F0),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Dashboard Penerjemah SIBI',
                              style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          _buildModelStatusBadge(state, isDark),
                          const SizedBox(width: 16),
                          IconButton(
                            icon: Icon(state.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
                            color: isDark ? Colors.white70 : Colors.black54,
                            onPressed: () => state.toggleTheme(),
                          ),
                        ],
                      ),
                    ),
                  
                  // Main Content Layout based on Screen Aspect Ratio
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final bool isLandscape = constraints.maxWidth > constraints.maxHeight * 1.2;
                        final bool isSuperSmall = constraints.maxWidth < 400;

                        final Widget cameraSection = Padding(
                          padding: EdgeInsets.all(_isExpanded ? 0 : (isLandscape ? 16.0 : 8.0)),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(_isExpanded ? 0 : 20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                )
                              ],
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(_isExpanded ? 0 : 20),
                                  child: CameraView(key: _cameraKey, classifier: widget.classifier, isExpanded: _isExpanded),
                                ),
                                if (_isExpanded)
                                  Positioned(
                                    bottom: isSuperSmall ? 85 : 100,
                                    left: 20,
                                    right: 20,
                                    child: Text(
                                      state.translatedText.isEmpty ? 'Arahkan tangan ke kamera' : state.translatedText,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.outfit(
                                        fontSize: state.translatedText.isEmpty ? (isSuperSmall ? 20 : 32) : (isSuperSmall ? 32 : 56),
                                        fontWeight: FontWeight.w900,
                                        color: state.translatedText.isEmpty ? Colors.white54 : Colors.white,
                                        shadows: [
                                          Shadow(color: Colors.black.withOpacity(0.8), offset: const Offset(0, 4), blurRadius: 10),
                                          Shadow(color: Colors.black.withOpacity(0.5), offset: const Offset(0, 8), blurRadius: 20),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (_isExpanded)
                                  Positioned(
                                    bottom: 20,
                                    left: 12,
                                    right: 12,
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.7),
                                          borderRadius: BorderRadius.circular(30),
                                          border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
                                        ),
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _buildActionButton(
                                                key: _deleteKey,
                                                icon: Icons.backspace_rounded,
                                                label: 'HAPUS',
                                                color: Colors.white70,
                                                isOutlined: true,
                                                onPressed: () => state.backspace(),
                                                isTutorialTarget: _tutorialStep == TutorialStep.pressDelete,
                                                isCompact: true,
                                              ),
                                              const SizedBox(width: 8),
                                              _buildActionButton(
                                                icon: Icons.refresh_rounded,
                                                label: 'RESET',
                                                color: Colors.white70,
                                                isOutlined: true,
                                                onPressed: () => state.clearText(),
                                                isCompact: true,
                                              ),
                                              const SizedBox(width: 8),
                                              _buildActionButton(
                                                key: _startKey,
                                                icon: Icons.play_arrow_rounded,
                                                label: 'START',
                                                color: AppTheme.successEmerald,
                                                isOutlined: false,
                                                onPressed: (state.isPaused || !state.isCameraActive) 
                                                    ? () { 
                                                        if (state.isPaused) state.togglePause(); 
                                                        if (!state.isCameraActive) { 
                                                          _cameraKey.currentState?.startCamera(); 
                                                        } 
                                                      } 
                                                    : null,
                                                isTutorialTarget: _tutorialStep == TutorialStep.pressStart,
                                                isCompact: true,
                                              ),
                                              const SizedBox(width: 8),
                                              _buildActionButton(
                                                icon: Icons.stop_rounded,
                                                label: 'STOP',
                                                color: AppTheme.dangerRose,
                                                isOutlined: true,
                                                onPressed: state.isCameraActive ? () {
                                                  _cameraKey.currentState?.stopCamera();
                                                  state.setCameraActive(false, message: 'Kamera dinonaktifkan.');
                                                } : null,
                                                isCompact: true,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                // Top-Right Camera Controls Bar (Flip Camera + Perbesar/Kecilkan)
                                Positioned(
                                  top: 12,
                                  right: 12,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // 1. Tombol Balik Kamera (Khusus Mobile Android/iOS)
                                      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) ...[
                                        Material(
                                          color: Colors.black.withOpacity(0.55),
                                          shape: const CircleBorder(),
                                          child: InkWell(
                                            customBorder: const CircleBorder(),
                                            onTap: () => _cameraKey.currentState?.toggleCamera(),
                                            child: const Tooltip(
                                              message: 'Balik Kamera',
                                              child: Padding(
                                                padding: EdgeInsets.all(8.0),
                                                child: Icon(Icons.flip_camera_android_rounded, color: Colors.white, size: 20),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      // 2. Tombol Perbesar / Kecilkan Layar
                                      Material(
                                        color: Colors.black.withOpacity(0.55),
                                        borderRadius: BorderRadius.circular(20),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(20),
                                          onTap: () async {
                                            setState(() => _isExpanded = !_isExpanded);
                                            if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
                                              await windowManager.setFullScreen(_isExpanded);
                                            } else if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
                                              if (_isExpanded) {
                                                SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
                                              } else {
                                                SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                                              }
                                            }
                                          },
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: (constraints.maxWidth < 600) ? 10 : 14, 
                                              vertical: 8
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  _isExpanded ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, 
                                                  color: Colors.white, 
                                                  size: 20
                                                ),
                                                if (constraints.maxWidth >= 600) ...[
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    _isExpanded ? 'KECILKAN' : 'PERBESAR', 
                                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Top-Left HUD (FPS & Latency)
                                Positioned(
                                  top: 46,
                                  left: 12,
                                  child: _buildPerformanceHUD(state, isDark),
                                ),
                              ],
                            ),
                          ),
                        );

                        final bool isCompactScreen = constraints.maxWidth < 460;
                        final double buttonGap = isSuperSmall ? 8.0 : (isCompactScreen ? 12.0 : 20.0);

                        // Segmented Mode Selector Cadangan (Otomatis / Huruf / Kata)
                        final Widget modeSelectorSection = Padding(
                          padding: const EdgeInsets.only(bottom: 6.0),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildModeSegment(
                                    label: 'Otomatis',
                                    modeKey: 'auto',
                                    icon: Icons.auto_awesome_rounded,
                                    currentMode: state.translationMode,
                                    isDark: isDark,
                                    onTap: () => state.setTranslationMode('auto'),
                                    isCompact: isCompactScreen,
                                  ),
                                  _buildModeSegment(
                                    label: 'Huruf',
                                    modeKey: 'alphabet',
                                    icon: Icons.text_fields_rounded,
                                    currentMode: state.translationMode,
                                    isDark: isDark,
                                    onTap: () => state.setTranslationMode('alphabet'),
                                    isCompact: isCompactScreen,
                                  ),
                                  _buildModeSegment(
                                    label: 'Kata',
                                    modeKey: 'word',
                                    icon: Icons.waves_rounded,
                                    currentMode: state.translationMode,
                                    isDark: isDark,
                                    onTap: () => state.setTranslationMode('word'),
                                    isCompact: isCompactScreen,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );

                        final Widget actionButtonsSection = Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: isLandscape ? 0 : 8.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              modeSelectorSection,
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _buildActionButton(
                                      icon: Icons.refresh_rounded,
                                      label: 'RESET',
                                      color: isDark ? Colors.white70 : AppTheme.textLightSecondary,
                                      isOutlined: true,
                                      onPressed: () => state.clearText(),
                                      isCompact: isCompactScreen,
                                    ),
                                    SizedBox(width: buttonGap),
                                    _buildActionButton(
                                      key: _startKey,
                                      icon: Icons.play_arrow_rounded,
                                      label: 'START',
                                      color: isDark ? AppTheme.successEmerald : AppTheme.primaryGreen,
                                      isOutlined: false,
                                      onPressed: (state.isPaused || !state.isCameraActive) 
                                          ? () { 
                                              if (state.isPaused) state.togglePause(); 
                                              if (!state.isCameraActive) { 
                                                _cameraKey.currentState?.startCamera(); 
                                              } 
                                            } 
                                          : null,
                                      isTutorialTarget: _tutorialStep == TutorialStep.pressStart,
                                      isCompact: isCompactScreen,
                                    ),
                                    SizedBox(width: buttonGap),
                                    _buildActionButton(
                                      icon: Icons.stop_rounded,
                                      label: 'STOP',
                                      color: AppTheme.dangerRose,
                                      isOutlined: true,
                                      onPressed: state.isCameraActive ? () {
                                        _cameraKey.currentState?.stopCamera();
                                        state.setCameraActive(false, message: 'Kamera dinonaktifkan.');
                                      } : null,
                                      isCompact: isCompactScreen,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );


                        final Widget textResultSection = Padding(
                          padding: EdgeInsets.all(isLandscape ? 16.0 : (isSuperSmall ? 8.0 : 16.0)),
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: !isDark 
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      )
                                    ]
                                  : [],
                              border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.black12 : const Color(0xFFF8FAFC),
                                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'HASIL TERJEMAHAN',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.outfit(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white70 : AppTheme.textLightSecondary,
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                      ),
                                      if (state.translatedText.isNotEmpty)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _buildTextButtonIcon(
                                              key: _deleteKey,
                                              icon: Icons.backspace_rounded,
                                              label: 'HAPUS',
                                              isDark: isDark,
                                              onPressed: () {
                                                state.backspace();
                                              },
                                              isTutorialTarget: _tutorialStep == TutorialStep.pressDelete,
                                            ),
                                            const SizedBox(width: 8),
                                            _buildTextButtonIcon(
                                              key: _copyKey,
                                              icon: Icons.copy_rounded,
                                              label: 'SALIN',
                                              isDark: isDark,
                                              onPressed: () {
                                                Clipboard.setData(ClipboardData(text: state.translatedText));
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Teks berhasil disalin ke clipboard!',
                                                      style: GoogleFonts.outfit(),
                                                    ),
                                                    backgroundColor: AppTheme.successEmerald,
                                                    behavior: SnackBarBehavior.floating,
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                  ),
                                                );
                                                if (_tutorialStep == TutorialStep.pressCopy) {
                                                  setState(() => _tutorialStep = TutorialStep.pressDelete);
                                                }
                                              },
                                              isTutorialTarget: _tutorialStep == TutorialStep.pressCopy,
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1, thickness: 1),
                                Expanded(
                                  child: Center(
                                    child: SingleChildScrollView(
                                      padding: EdgeInsets.all(isSuperSmall ? 12.0 : 20.0),
                                      child: Text(
                                        state.translatedText.isEmpty 
                                            ? 'Mulai peragakan isyarat tangan Anda di depan kamera...' 
                                            : state.translatedText,
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.outfit(
                                          fontSize: state.translatedText.isEmpty
                                              ? 14
                                              : (isSuperSmall ? 28 : (isLandscape ? 36 : 40)),
                                          fontStyle: state.translatedText.isEmpty ? FontStyle.italic : FontStyle.normal,
                                          fontWeight: state.translatedText.isEmpty ? FontWeight.normal : FontWeight.w800,
                                          color: state.translatedText.isEmpty 
                                              ? (isDark ? Colors.white30 : Colors.black38) 
                                              : (isDark ? Colors.white : AppTheme.textLightPrimary),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );

                        if (_isExpanded) {
                          return cameraSection;
                        }

                        // Selalu gunakan layout atas-bawah (kamera di atas, teks di bawah)
                        // seperti yang direkomendasikan pengguna.
                        return Column(
                          children: [
                            Expanded(flex: 6, child: cameraSection),
                            actionButtonsSection,
                            Expanded(flex: 4, child: textResultSection),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (_tutorialStep != TutorialStep.none) 
        SpotlightOverlay(
          targetRect: _currentTargetRect, 
          isDark: isDark,
        ),
      if (_tutorialStep != TutorialStep.none) _buildTutorialOverlay(isDark),
    ],
  ),
);
  }

  Widget _buildModeSegment({
    required String label,
    required String modeKey,
    required IconData icon,
    required String currentMode,
    required bool isDark,
    required VoidCallback onTap,
    bool isCompact = false,
  }) {
    final bool isSelected = currentMode == modeKey;
    final Color selectedBg = isDark ? const Color(0xFF334155) : Colors.white;
    final Color selectedFg = isDark ? Colors.white : AppTheme.textLightPrimary;
    final Color unselectedFg = isDark ? Colors.white54 : AppTheme.textLightSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 9 : 12, 
          vertical: isCompact ? 5 : 6
        ),
        decoration: BoxDecoration(
          color: isSelected ? selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: isCompact ? 12 : 13,
              color: isSelected ? (isDark ? AppTheme.electricCyan : AppTheme.primaryGreen) : unselectedFg,
            ),
            SizedBox(width: isCompact ? 3 : 5),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: isCompact ? 10 : 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? selectedFg : unselectedFg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    Key? key,
    required IconData icon,
    required String label,
    required Color color,
    required bool isOutlined,
    required VoidCallback? onPressed,
    bool isTutorialTarget = false,
    bool isCompact = false,
  }) {
    final bool isDisabled = onPressed == null;
    final borderRadius = BorderRadius.circular(20.0); // Rounded card style
    
    Widget button = Container(
      key: key,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: !isOutlined && !isDisabled
            ? [
                BoxShadow(
                  color: color.withOpacity(0.25),
                  blurRadius: isCompact ? 6 : 10,
                  offset: const Offset(0, 3),
                )
              ]
            : [],
      ),
      child: Material(
        color: isOutlined ? Colors.transparent : (isDisabled ? color.withOpacity(0.4) : color),
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: isOutlined 
              ? BorderSide(color: isDisabled ? color.withOpacity(0.2) : color, width: 1.5) 
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: borderRadius,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 12 : 20, 
              vertical: isCompact ? 9 : 12
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon, 
                  size: isCompact ? 18 : 20, 
                  color: isOutlined 
                      ? (isDisabled ? color.withOpacity(0.5) : color) 
                      : (isDisabled ? Colors.white54 : Colors.white),
                ),
                SizedBox(width: isCompact ? 5 : 8),
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: isCompact ? 12 : 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: isOutlined 
                        ? (isDisabled ? color.withOpacity(0.5) : color) 
                        : (isDisabled ? Colors.white54 : Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (isTutorialTarget) {
      return AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _pulseAnimation.value,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.6 * _pulseAnimation.value),
                    blurRadius: 15 * _pulseAnimation.value,
                    spreadRadius: 2 * _pulseAnimation.value,
                  )
                ],
              ),
              child: child,
            ),
          );
        },
        child: button,
      );
    }
    return button;
  }

  Widget _buildCircleActionButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required bool isOutlined,
    required VoidCallback? onPressed,
  }) {
    final bool isDisabled = onPressed == null;
    const double size = 48.0;
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: !isOutlined && !isDisabled
            ? [
                BoxShadow(
                  color: color.withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            : [],
      ),
      child: Material(
        color: isOutlined ? Colors.transparent : (isDisabled ? color.withOpacity(0.4) : color),
        shape: CircleBorder(
          side: isOutlined 
              ? BorderSide(color: isDisabled ? color.withOpacity(0.2) : color, width: 1.5) 
              : BorderSide.none,
        ),
        child: IconButton(
          icon: Icon(icon, size: 22),
          color: isOutlined 
              ? (isDisabled ? color.withOpacity(0.5) : color) 
              : (isDisabled ? Colors.white54 : Colors.white),
          tooltip: tooltip,
          onPressed: onPressed,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildSidebar(bool isDark) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;
    
    Widget content = Column(
      children: [
        const SizedBox(height: 40),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: isDark ? Colors.black : AppTheme.primaryGreen,
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Text(
              'SIBI',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'SIBI Real-time',
          style: GoogleFonts.outfit(
            color: isDark ? AppTheme.successEmerald : AppTheme.primaryGreen,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 40),
        
        _buildSidebarItem(
          icon: Icons.home_rounded,
          title: 'Beranda',
          isActive: _selectedIndex == 0,
          isDark: isDark,
          onTap: () {
            setState(() => _selectedIndex = 0);
            if (!isDesktop) Navigator.pop(context);
          },
        ),
        _buildSidebarItem(
          icon: Icons.help_outline_rounded,
          title: 'Petunjuk',
          isActive: false,
          isDark: isDark,
          onTap: () {
            if (!isDesktop) Navigator.pop(context);
            _showTutorialDialog();
          },
        ),
        
        if (isDesktop) const Spacer() else const SizedBox(height: 36),
        
        Column(
          children: [
            Image.asset(
              'assets/images/logo_polbeng.png',
              height: 50,
            ),
            const SizedBox(height: 8),
            Text(
              'Politeknik Negeri Bengkalis',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: isDark ? Colors.white70 : AppTheme.textLightSecondary,
                fontWeight: FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );

    return Container(
      width: isDesktop ? 260 : double.infinity,
      color: isDark ? AppTheme.surfaceDark : Colors.white,
      child: isDesktop ? content : SingleChildScrollView(child: content),
    );
  }

  Widget _buildSidebarItem({
    required IconData icon,
    required String title,
    required bool isActive,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final activeBg = isDark ? AppTheme.primaryGreen.withOpacity(0.2) : AppTheme.primaryGreen.withOpacity(0.1);
    final activeColor = isDark ? AppTheme.successEmerald : AppTheme.primaryGreen;
    final inactiveColor = isDark ? Colors.white70 : Colors.black87;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
        decoration: BoxDecoration(
          color: isActive ? activeBg : Colors.transparent,
          border: isActive
              ? Border(right: BorderSide(color: activeColor, width: 4))
              : const Border(right: BorderSide(color: Colors.transparent, width: 4)),
        ),
        child: Row(
          children: [
            Icon(icon, color: isActive ? activeColor : inactiveColor),
            const SizedBox(width: 16),
            Text(
              title,
              style: GoogleFonts.outfit(
                color: isActive ? activeColor : inactiveColor,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelStatusBadge(SibiState state, bool isDark) {
    final isWindowsPlatform = defaultTargetPlatform == TargetPlatform.windows;
    final bool isPythonTFLite = isWindowsPlatform && state.isBridgeConnected;

    final Color modelBadgeColor = widget.classifier.isTfliteLoaded || isPythonTFLite
        ? AppTheme.successEmerald
        : AppTheme.dangerRose;

    final String modelBadgeText = isPythonTFLite 
        ? 'Aktif'
        : (widget.classifier.isTfliteLoaded ? 'Aktif' : 'Tidak Aktif');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: modelBadgeColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            modelBadgeText == 'Aktif' ? Icons.check_circle_rounded : Icons.cancel_rounded, 
            color: Colors.white, 
            size: 14
          ),
          const SizedBox(width: 6),
          Text(
            modelBadgeText,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceHUD(SibiState state, bool isDark) {
    if (!state.isCameraActive) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.speed_rounded, color: AppTheme.electricCyan, size: 12),
          const SizedBox(width: 4),
          Text(
            'FPS: ${state.fps.toInt()}',
            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Icon(Icons.timer_rounded, color: AppTheme.warningAmber, size: 12),
          const SizedBox(width: 4),
          Text(
            '${state.inferenceTimeMs.toInt()}ms',
            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Icon(Icons.verified_user_rounded, color: AppTheme.successEmerald, size: 12),
          const SizedBox(width: 4),
          Text(
            '${(state.confidence * 100).toInt()}%',
            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildTextButtonIcon({
    Key? key,
    required IconData icon,
    required String label,
    required bool isDark,
    required VoidCallback onPressed,
    bool isTutorialTarget = false,
  }) {
    Widget button = TextButton.icon(
      key: key,
      icon: Icon(icon, size: 16),
      label: Text(label, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
      style: TextButton.styleFrom(
        foregroundColor: isDark ? AppTheme.electricCyan : AppTheme.primaryGreen,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
    );

    if (isTutorialTarget) {
      return AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _pulseAnimation.value,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.electricCyan.withOpacity(0.4 * _pulseAnimation.value),
                    blurRadius: 8 * _pulseAnimation.value,
                    spreadRadius: 1 * _pulseAnimation.value,
                  )
                ],
              ),
              child: child,
            ),
          );
        },
        child: button,
      );
    }
    return button;
  }

  Widget _buildTutorialOverlay(bool isDark) {
    if (_tutorialStep == TutorialStep.none) return const SizedBox.shrink();

    String instruction = '';
    int stepNum = 1;
    bool isFinished = false;

    switch (_tutorialStep) {
      case TutorialStep.pressStart:
        instruction = 'Arahkan perhatian Anda ke tombol START di bawah kamera. Silakan tekan tombol tersebut untuk menghidupkan deteksi AI.';
        stepNum = 1;
        break;
      case TutorialStep.performGesture:
        instruction = 'Kamera telah aktif! Sekarang arahkan tangan Anda ke kamera dan cobalah mempraktikkan abjad isyarat apa saja hingga AI mendeteksinya.';
        stepNum = 2;
        break;
      case TutorialStep.pressCopy:
        instruction = 'Luar Biasa! Teks berhasil ditebak oleh AI. Sekarang, tekan tombol SALIN untuk menyalin teks tersebut ke clipboard Anda.';
        stepNum = 3;
        break;
      case TutorialStep.pressDelete:
        instruction = 'Teks telah disalin. Langkah terakhir, tekan tombol HAPUS untuk mengosongkan layar dan bersiap untuk gestur berikutnya.';
        stepNum = 4;
        break;
      case TutorialStep.finished:
        instruction = 'Sempurna! Anda sudah berhasil menguasai cara menggunakan SIBI Real-time. Anda siap untuk menerjemahkan lebih banyak isyarat tangan.';
        stepNum = 4;
        isFinished = true;
        break;
      default:
        break;
    }

    return Positioned(
      top: 20,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedTutorialCard(
          instruction: instruction,
          currentStep: stepNum,
          totalSteps: 4,
          isDark: isDark,
          onClose: _exitTutorial,
          isFinished: isFinished,
        ),
      ),
    );
  }
}
