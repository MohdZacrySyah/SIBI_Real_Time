import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme.dart';

class AnimatedTutorialCard extends StatefulWidget {
  final String instruction;
  final int currentStep; // 1 to 4 (or 5 for finished)
  final int totalSteps;
  final bool isDark;
  final VoidCallback onClose;
  final bool isFinished;

  const AnimatedTutorialCard({
    super.key,
    required this.instruction,
    required this.currentStep,
    this.totalSteps = 4,
    required this.isDark,
    required this.onClose,
    this.isFinished = false,
  });

  @override
  State<AnimatedTutorialCard> createState() => _AnimatedTutorialCardState();
}

class _AnimatedTutorialCardState extends State<AnimatedTutorialCard> with TickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  String _displayedText = '';
  int _charIndex = 0;
  String _targetText = '';

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _slideAnimation = Tween<Offset>(begin: const Offset(0, -0.5), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeIn),
    );

    _slideController.forward();
    _targetText = widget.instruction;
    _startTypewriter();
  }

  @override
  void didUpdateWidget(AnimatedTutorialCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.instruction != widget.instruction) {
      _slideController.reset();
      _slideController.forward();
      
      setState(() {
        _targetText = widget.instruction;
        _displayedText = '';
        _charIndex = 0;
      });
      _startTypewriter();
    }
  }

  void _startTypewriter() {
    Future.delayed(const Duration(milliseconds: 400), _typeNextChar);
  }

  void _typeNextChar() {
    if (!mounted) return;
    if (_charIndex < _targetText.length) {
      setState(() {
        _displayedText += _targetText[_charIndex];
        _charIndex++;
      });
      Future.delayed(const Duration(milliseconds: 30), _typeNextChar);
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  IconData _getStepIcon() {
    if (widget.isFinished) return Icons.celebration_rounded;
    switch (widget.currentStep) {
      case 1: return Icons.power_settings_new_rounded;
      case 2: return Icons.waving_hand_rounded;
      case 3: return Icons.content_copy_rounded;
      case 4: return Icons.backspace_rounded;
      default: return Icons.school_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          constraints: const BoxConstraints(maxWidth: 500),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: (widget.isDark ? AppTheme.electricCyan : AppTheme.primaryGreen).withOpacity(0.3),
                blurRadius: 30,
                spreadRadius: 2,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: widget.isDark ? AppTheme.spaceDark.withOpacity(0.85) : Colors.white.withOpacity(0.9),
                  border: Border.all(
                    color: (widget.isDark ? AppTheme.electricCyan : AppTheme.primaryGreen).withOpacity(0.5),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header & Progress
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (widget.isDark ? AppTheme.electricCyan : AppTheme.primaryGreen).withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _getStepIcon(), 
                            color: widget.isDark ? AppTheme.electricCyan : AppTheme.primaryGreen,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.isFinished ? 'Tutorial Selesai!' : 'Langkah ${widget.currentStep} dari ${widget.totalSteps}',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: widget.isDark ? Colors.white70 : AppTheme.textLightSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (!widget.isFinished)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: widget.currentStep / widget.totalSteps,
                                    backgroundColor: widget.isDark ? Colors.white12 : Colors.black12,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      widget.isDark ? AppTheme.electricCyan : AppTheme.primaryGreen,
                                    ),
                                    minHeight: 4,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 24),
                          color: widget.isDark ? Colors.white54 : Colors.black54,
                          padding: const EdgeInsets.only(left: 8),
                          constraints: const BoxConstraints(),
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Typewriter Text
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: widget.isDark ? Colors.black26 : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: widget.isDark ? Colors.white12 : Colors.black12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              _displayedText + (_charIndex < _targetText.length ? '|' : ''),
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: widget.isDark ? Colors.white : Colors.black87,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.isFinished) ...[
                      const SizedBox(height: 20),
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.rocket_launch_rounded),
                          label: const Text('Mulai Menggunakan Aplikasi'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.isDark ? AppTheme.electricCyan : AppTheme.primaryGreen,
                            foregroundColor: widget.isDark ? AppTheme.spaceDark : Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            textStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                      )
                    ]
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
