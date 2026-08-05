import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../ml/sibi_classifier.dart';
import '../state/sibi_state.dart';
import 'camera_view.dart';
import 'theme.dart';
import 'tutorial_dialog.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

class DashboardScreen extends StatefulWidget {
  final SibiClassifier classifier;

  const DashboardScreen({super.key, required this.classifier});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0; 
  bool _isExpanded = false; 
  final GlobalKey<CameraViewState> _cameraKey = GlobalKey<CameraViewState>();

  void _showTutorialDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (context) => const TutorialDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<SibiState>(context);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final contentBgColor = isDark ? AppTheme.spaceDark : AppTheme.bgLightContent;

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
      body: SafeArea(
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
                              'Dashboard Deteksi SIBI',
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
                                  child: CameraView(key: _cameraKey, classifier: widget.classifier),
                                ),
                                if (_isExpanded)
                                  Positioned(
                                    bottom: 120,
                                    left: 24,
                                    right: 24,
                                    child: Text(
                                      state.translatedText.isEmpty ? 'Arahkan tangan ke kamera' : state.translatedText,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.outfit(
                                        fontSize: state.translatedText.isEmpty ? (isSuperSmall ? 24 : 36) : (isSuperSmall ? 36 : 64),
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
                                    bottom: 40,
                                    left: 0,
                                    right: 0,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        _buildCircleActionButton(
                                          icon: Icons.refresh_rounded,
                                          tooltip: 'RESET',
                                          color: Colors.white70,
                                          isOutlined: true,
                                          onPressed: () => state.clearText(),
                                        ),
                                        const SizedBox(width: 24),
                                        _buildActionButton(
                                          icon: Icons.play_arrow_rounded,
                                          label: 'START',
                                          color: AppTheme.successEmerald,
                                          isOutlined: false,
                                          onPressed: (state.isPaused || (!state.isBridgeConnected && defaultTargetPlatform == TargetPlatform.windows)) 
                                              ? () { 
                                                  if (state.isPaused) state.togglePause(); 
                                                  if (defaultTargetPlatform == TargetPlatform.windows && !state.isBridgeConnected) { 
                                                    _cameraKey.currentState?.initWindowsFFI(); 
                                                  } 
                                                } 
                                              : null,
                                        ),
                                        const SizedBox(width: 24),
                                        _buildCircleActionButton(
                                          icon: Icons.stop_rounded,
                                          tooltip: 'STOP',
                                          color: AppTheme.dangerRose,
                                          isOutlined: true,
                                          onPressed: !state.isPaused ? () => state.togglePause() : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Positioned(
                                    top: 16,
                                    right: 16,
                                    child: Material(
                                      color: Colors.black.withOpacity(0.5),
                                      shape: const CircleBorder(),
                                      child: IconButton(
                                        icon: Icon(_isExpanded ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, color: Colors.white,),
                                        onPressed: () async {
                                          setState(() => _isExpanded = !_isExpanded);
                                          if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
                                            await windowManager.setFullScreen(_isExpanded);
                                          } else if (Platform.isAndroid || Platform.isIOS) {
                                            if (_isExpanded) {
                                              SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
                                            } else {
                                              SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  top: 56,
                                  left: 16,
                                  child: _buildPerformanceHUD(state, isDark),
                                ),
                              ],
                            ),
                          ),
                        );

                        final Widget actionButtonsSection = Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: isLandscape ? 0 : 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildCircleActionButton(
                                icon: Icons.refresh_rounded,
                                tooltip: 'RESET',
                                color: isDark ? Colors.white70 : AppTheme.textLightSecondary,
                                isOutlined: true,
                                onPressed: () => state.clearText(),
                              ),
                              const SizedBox(width: 24),
                              _buildActionButton(
                                icon: Icons.play_arrow_rounded,
                                label: 'START',
                                color: isDark ? AppTheme.successEmerald : AppTheme.primaryGreen,
                                isOutlined: false,
                                onPressed: (state.isPaused || (!state.isBridgeConnected && defaultTargetPlatform == TargetPlatform.windows)) ? () { if (state.isPaused) state.togglePause(); if (defaultTargetPlatform == TargetPlatform.windows && !state.isBridgeConnected) { _cameraKey.currentState?.initWindowsFFI(); } } : null,
                              ),
                              const SizedBox(width: 24),
                              _buildCircleActionButton(
                                icon: Icons.stop_rounded,
                                tooltip: 'STOP',
                                color: AppTheme.dangerRose,
                                isOutlined: true,
                                onPressed: !state.isPaused ? () => state.togglePause() : null,
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
                                      Text(
                                        'HASIL TERJEMAHAN',
                                        style: GoogleFonts.outfit(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white70 : AppTheme.textLightSecondary,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                      if (state.translatedText.isNotEmpty)
                                        IconButton(
                                          icon: const Icon(Icons.copy_rounded, size: 18),
                                          color: isDark ? AppTheme.electricCyan : AppTheme.primaryGreen,
                                          tooltip: 'Salin Teks',
                                          constraints: const BoxConstraints(),
                                          padding: EdgeInsets.zero,
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
                                          },
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
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool isOutlined,
    required VoidCallback? onPressed,
  }) {
    final bool isDisabled = onPressed == null;
    final borderRadius = BorderRadius.circular(20.0); // Rounded card style
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon, 
                  size: 20, 
                  color: isOutlined 
                      ? (isDisabled ? color.withOpacity(0.5) : color) 
                      : (isDisabled ? Colors.white54 : Colors.white),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
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
    
    return Container(
      width: isDesktop ? 260 : double.infinity,
      color: isDark ? AppTheme.surfaceDark : Colors.white,
      child: Column(
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
        ],
      ),
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

  // Not used anymore but kept to avoid errors if called elsewhere
  Widget _buildPerfRow(IconData icon, String label, String value) {
    return const SizedBox.shrink();
  }
}
