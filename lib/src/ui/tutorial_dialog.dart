import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme.dart';

class TutorialDialog extends StatefulWidget {
  const TutorialDialog({super.key});

  @override
  State<TutorialDialog> createState() => _TutorialDialogState();
}

class _TutorialDialogState extends State<TutorialDialog> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _tutorialSteps = [
    {
      'icon': Icons.lightbulb_rounded,
      'title': 'Pencahayaan Terang',
      'desc': 'Pastikan Anda berada di ruangan dengan cahaya yang cukup terang agar kecerdasan buatan (AI) bisa membaca lekuk jari Anda dengan akurat.',
      'color': AppTheme.warningAmber,
    },
    {
      'icon': Icons.front_hand_rounded,
      'title': 'Posisi Tangan',
      'desc': 'Angkat tangan Anda tepat di depan kamera. Jangan terlalu dekat hingga terpotong, dan jangan terlalu jauh hingga tak terlihat.',
      'color': Colors.blueAccent,
    },
    {
      'icon': Icons.sign_language_rounded,
      'title': 'Lakukan Isyarat',
      'desc': 'Mulai peragakan SIBI secara perlahan. Teks terjemahan akan otomatis muncul dan terangkai di layar secara real-time.',
      'color': AppTheme.successEmerald,
    },
    {
      'icon': Icons.refresh_rounded,
      'title': 'Bersihkan Layar',
      'desc': 'Jika ada kesalahan atau Anda ingin memulai kalimat baru, cukup tekan tombol RESET untuk mengosongkan seluruh papan teks.',
      'color': AppTheme.dangerRose,
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: double.infinity,
        height: 500,
        constraints: const BoxConstraints(maxWidth: 450),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 30,
              offset: const Offset(0, 10),
            )
          ],
        ),
        child: Column(
          children: [
            // Top action bar
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Petunjuk Cepat',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppTheme.textPrimary : Colors.black87,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: isDark ? AppTheme.textSecondary : Colors.black54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            
            // Carousel Content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemCount: _tutorialSteps.length,
                itemBuilder: (context, index) {
                  final step = _tutorialSteps[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: (step['color'] as Color).withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            step['icon'] as IconData,
                            size: 80,
                            color: step['color'] as Color,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          step['title'] as String,
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppTheme.textPrimary : Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          step['desc'] as String,
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark ? AppTheme.textSecondary : Colors.black54,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Bottom Navigation
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Page Indicators
                  Row(
                    children: List.generate(
                      _tutorialSteps.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.only(right: 8),
                        height: 8,
                        width: _currentPage == index ? 24 : 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index 
                              ? AppTheme.electricIndigo 
                              : (isDark ? Colors.white24 : Colors.black12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  
                  // Next/Done Button
                  ElevatedButton(
                    onPressed: () {
                      if (_currentPage < _tutorialSteps.length - 1) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.electricIndigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      _currentPage == _tutorialSteps.length - 1 ? 'MULAI SEKARANG' : 'SELANJUTNYA',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
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
