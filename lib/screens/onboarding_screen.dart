import 'package:flutter/material.dart';
import 'signup_screen.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      body: SafeArea(
        child: Column(
          children: [
            // Back button
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 16, top: 12),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios,
                      size: 20, color: Colors.black87),
                  onPressed: () {
                    if (Navigator.canPop(context)) Navigator.pop(context);
                  },
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Profile bubbles illustration
            Expanded(
              child: _ProfileBubblesWidget(),
            ),

            // Dot indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                _DotIndicator(isActive: false),
                SizedBox(width: 6),
                _DotIndicator(isActive: false),
                SizedBox(width: 6),
                _DotIndicator(isActive: true),
              ],
            ),

            const SizedBox(height: 28),

            // Title & subtitle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: const [
                  Text(
                    'For yourself, family and friends',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      height: 1.3,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Easily manage medication for everyone you care about with seamless profile switching.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black45,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // CLIENT button → navigates to SignUpScreen
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    // TODO: Navigate to Admin Login screen
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A6BFF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'CLIENT',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Admin Login (placeholder)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SignUpScreen()),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    'Admin Login',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.black45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Profile bubbles widget ──────────────────────────────────────────────────

class _ProfileBubblesWidget extends StatelessWidget {
  static const List<String?> _avatarAssets = [
    null, // top-center  → replace with 'assets/images/avatar1.jpg'
    null, // left        → replace with 'assets/images/avatar2.jpg'
    null, // right       → replace with 'assets/images/avatar3.jpg'
    null, // center      → replace with 'assets/images/avatar4.jpg'
  ];

  static const List<IconData> _fallbackIcons = [
    Icons.person,
    Icons.elderly,
    Icons.face,
    Icons.person_2,
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 280,
        height: 260,
        child: Stack(
          alignment: Alignment.center,
          children: [
            _buildRing(220, const Color(0xFFDDE4F0)),
            _buildRing(160, const Color(0xFFCDD7EE)),
            Positioned(
              top: 80,
              left: 90,
              child: _ProfileBubble(
                size: 88,
                assetPath: _avatarAssets[3],
                fallbackIcon: _fallbackIcons[3],
                borderColor: Colors.white,
                borderWidth: 4,
              ),
            ),
            Positioned(
              top: 0,
              left: 110,
              child: _ProfileBubble(
                size: 56,
                assetPath: _avatarAssets[0],
                fallbackIcon: _fallbackIcons[0],
                borderColor: Colors.white,
                borderWidth: 3,
              ),
            ),
            Positioned(
              top: 90,
              left: 10,
              child: _ProfileBubble(
                size: 62,
                assetPath: _avatarAssets[1],
                fallbackIcon: _fallbackIcons[1],
                borderColor: Colors.white,
                borderWidth: 3,
                grayscale: true,
              ),
            ),
            Positioned(
              top: 70,
              right: 8,
              child: _ProfileBubble(
                size: 62,
                assetPath: _avatarAssets[2],
                fallbackIcon: _fallbackIcons[2],
                borderColor: Colors.white,
                borderWidth: 3,
                grayscale: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRing(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.45),
      ),
    );
  }
}

class _ProfileBubble extends StatelessWidget {
  final double size;
  final String? assetPath;
  final IconData fallbackIcon;
  final Color borderColor;
  final double borderWidth;
  final bool grayscale;

  const _ProfileBubble({
    required this.size,
    required this.assetPath,
    required this.fallbackIcon,
    required this.borderColor,
    required this.borderWidth,
    this.grayscale = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget avatar = CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFFCDD7EE),
      backgroundImage: assetPath != null ? AssetImage(assetPath!) : null,
      child: assetPath == null
          ? Icon(fallbackIcon, size: size * 0.45, color: Colors.white70)
          : null,
    );

    if (grayscale) {
      avatar = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0,      0,      0,      1, 0,
        ]),
        child: avatar,
      );
    }

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
          child: SizedBox(width: size, height: size, child: avatar)),
    );
  }
}

// ── Dot indicator ───────────────────────────────────────────────────────────

class _DotIndicator extends StatelessWidget {
  final bool isActive;
  const _DotIndicator({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: isActive ? 22 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF1A6BFF) : Colors.black26,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}