// lib/screens/profile_settings_screen.dart
//
// Editable profile screen for both patient and caregiver.
// Supports: name, date of birth, gender, age display, and profile picture.
//
// UPDATED: Respects AccessibilityProvider (patient) or
// CaregiverAccessibilityProvider (caregiver) — dark/HC colours, font scale,
// and button scale are all applied automatically.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/accessibility_provider.dart';
import '../providers/caregiver_accessibility_provider.dart';
import '../services/profile_service.dart';

class ProfileSettingsScreen extends StatefulWidget {
  final bool isCaregiverMode;
  const ProfileSettingsScreen({super.key, this.isCaregiverMode = false});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class ProfileData {
  final String name;
  final DateTime? dateOfBirth;
  final String gender;
  final int avatarIndex;

  const ProfileData({
    required this.name,
    this.dateOfBirth,
    required this.gender,
    required this.avatarIndex,
  });
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _profileService = ProfileService();
  final _nameController = TextEditingController();

  DateTime? _dateOfBirth;
  String _gender = 'Female';
  int _selectedAvatarIndex = 0;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _profileImageBase64;
  String? _existingProfileImageUrl;

  static const List<String> _genderOptions = [
    'Male', 'Female', 'Non-binary', 'Prefer not to say'
  ];

  static const List<Color> _avatarColors = [
    Color(0xFF3B71FE), Color(0xFF6B5BFF), Color(0xFF2BC8A7),
    Color(0xFFFFA726), Color(0xFFEF5350), Color(0xFF8E24AA),
    Color(0xFF42A5F5), Color(0xFF26A69A), Color(0xFFFFCA28),
  ];

  static const List<String> _avatarInitials = [
    'H', 'M', 'A', 'S', 'L', 'T', 'P', 'J', 'C',
  ];

  Color get _themeColor =>
      widget.isCaregiverMode ? const Color(0xFF2BC8A7) : const Color(0xFF3B71FE);

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await _profileService.getProfile();
      if (data != null && mounted) {
        setState(() {
          _nameController.text = (data['name'] as String?) ?? '';
          _gender = (data['gender'] as String?) ?? 'Female';
          _selectedAvatarIndex = (data['avatarIndex'] as int?) ?? 0;
          _existingProfileImageUrl = data['profileImageUrl'] as String?;
          final dob = data['dateOfBirth'];
          if (dob != null) {
            _dateOfBirth = (dob as dynamic).toDate() as DateTime;
          }
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final name = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : 'User';

      final imageUrl = _profileImageBase64 ?? _existingProfileImageUrl;

      await _profileService.saveProfile(
        name: name,
        dateOfBirth: _dateOfBirth,
        gender: _gender,
        avatarIndex: _selectedAvatarIndex,
        profileImageUrl: imageUrl,
      );

      if (!mounted) return;

      Navigator.pop(
        context,
        ProfileData(
          name: name,
          dateOfBirth: _dateOfBirth,
          gender: _gender,
          avatarIndex: _selectedAvatarIndex,
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Profile saved!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not save profile: $e'),
            backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickProfilePicture(
      {required Color accent, required bool isDark}) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text('Profile Picture',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.camera_alt, color: accent),
              title: Text('Take a Photo',
                  style:
                      TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                Navigator.pop(ctx);
                _capturePhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library, color: accent),
              title: Text('Choose from Gallery',
                  style:
                      TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                Navigator.pop(ctx);
                _capturePhoto(ImageSource.gallery);
              },
            ),
            if (_profileImageBase64 != null ||
                _existingProfileImageUrl != null)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Remove Photo',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _profileImageBase64 = null;
                    _existingProfileImageUrl = null;
                  });
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _capturePhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
          source: source,
          maxWidth: 400,
          maxHeight: 400,
          imageQuality: 75);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _profileImageBase64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        _existingProfileImageUrl = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load image: $e')),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }

  int? _computeAge() {
    if (_dateOfBirth == null) return null;
    final now = DateTime.now();
    int age = now.year - _dateOfBirth!.year;
    if (now.month < _dateOfBirth!.month ||
        (now.month == _dateOfBirth!.month && now.day < _dateOfBirth!.day)) {
      age--;
    }
    return age;
  }

  Future<void> _pickDateOfBirth(Color accent) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(1995, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(primary: accent),
        ),
        child: child!,
      ),
    );
    if (selected != null) setState(() => _dateOfBirth = selected);
  }

  void _showGenderPicker(
      {required Color accent, required bool isDark, required Color onSurface}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose Gender',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: onSurface)),
              const SizedBox(height: 18),
              ..._genderOptions.map((option) {
                final selected = option == _gender;
                return ListTile(
                  title: Text(option,
                      style: TextStyle(
                          fontSize: 16,
                          color: selected ? accent : onSurface)),
                  trailing: selected
                      ? Icon(Icons.check, color: accent)
                      : null,
                  onTap: () {
                    setState(() => _gender = option);
                    Navigator.pop(context);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAvatar(Color accent) {
    final imageUrl = _profileImageBase64 ?? _existingProfileImageUrl;
    if (imageUrl != null &&
        imageUrl.isNotEmpty &&
        imageUrl.startsWith('data:')) {
      try {
        final b64 =
            imageUrl.contains(',') ? imageUrl.split(',').last : imageUrl;
        return CircleAvatar(
          radius: 50,
          backgroundImage: MemoryImage(base64Decode(b64)),
        );
      } catch (_) {}
    }
    return CircleAvatar(
      radius: 50,
      backgroundColor:
          _avatarColors[_selectedAvatarIndex % _avatarColors.length],
      child: Text(
        _nameController.text.isNotEmpty
            ? _nameController.text[0].toUpperCase()
            : _avatarInitials[_selectedAvatarIndex],
        style: const TextStyle(
            fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildInfoField({
    required String label,
    required String value,
    required VoidCallback onTap,
    required Color labelColor,
    required Color fieldBg,
    required Color onSurface,
    String? subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 14,
                color: labelColor,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: fieldBg,
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: onSurface.withValues(alpha: 0.12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        style: TextStyle(
                            fontSize: 15,
                            color: value.startsWith('Enter') ||
                                    value == 'Not set'
                                ? onSurface.withValues(alpha: 0.4)
                                : onSurface),
                      ),
                      if (subtitle != null)
                        Text(subtitle,
                            style: TextStyle(
                                fontSize: 12,
                                color:
                                    onSurface.withValues(alpha: 0.45))),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios,
                    size: 16,
                    color: onSurface.withValues(alpha: 0.4)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.isCaregiverMode) {
      return _buildWithCaregiverTheme();
    } else {
      return _buildWithPatientTheme();
    }
  }

  Widget _buildWithPatientTheme() {
    final acc = context.watch<AccessibilityProvider>();
    final isDark = acc.themeMode == AppThemeMode.dark;
    final theme = isDark ? acc.buildDarkTheme() : acc.buildLightTheme();
    final mq = MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(acc.fontScaleFactor));

    return Theme(
      data: theme,
      child: MediaQuery(
        data: mq,
        child: Builder(builder: (ctx) => _buildScaffold(ctx, acc.buttonScaleFactor)),
      ),
    );
  }

  Widget _buildWithCaregiverTheme() {
    final acc = context.watch<CaregiverAccessibilityProvider>();
    final theme = acc.theme;
    final mq = MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(acc.fontScaleFactor));

    return Theme(
      data: theme,
      child: MediaQuery(
        data: mq,
        child: Builder(builder: (ctx) => _buildScaffold(ctx, acc.buttonScaleFactor)),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context, double buttonScaleFactor) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? const Color(0xFF121212) : const Color(0xFFF4F7FF);
    final cardColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final onSurface = cs.onSurface;
    final accent = widget.isCaregiverMode ? const Color(0xFF2BC8A7) : cs.primary;
    final labelColor = onSurface.withValues(alpha: 0.6);
    final btnH = 56.0 * buttonScaleFactor;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(child: CircularProgressIndicator(color: accent)),
      );
    }

    final age = _computeAge();

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.arrow_back_ios_new,
                        color: onSurface, size: 20),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Edit Profile',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: onSurface),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                ],
              ),
            ),

            // ── Form ───────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),

                      // Profile picture
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          _buildAvatar(accent),
                          GestureDetector(
                            onTap: () => _pickProfilePicture(
                                accent: accent, isDark: isDark),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 6,
                                      offset: Offset(0, 2))
                                ],
                              ),
                              child: Icon(Icons.camera_alt,
                                  size: 18, color: accent),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),
                      Text('Tap to change photo',
                          style: TextStyle(
                              fontSize: 12,
                              color: onSurface.withValues(alpha: 0.4))),

                      const SizedBox(height: 24),

                      // Name
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Name',
                            style: TextStyle(
                                fontSize: 14,
                                color: labelColor,
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: onSurface.withValues(alpha: 0.12)),
                        ),
                        child: TextField(
                          controller: _nameController,
                          onChanged: (_) => setState(() {}),
                          style: TextStyle(color: onSurface),
                          decoration: InputDecoration(
                            hintText: 'Enter your name',
                            hintStyle: TextStyle(
                                color: onSurface.withValues(alpha: 0.35)),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 16),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      _buildInfoField(
                        label: 'Date of Birth',
                        value: _dateOfBirth != null
                            ? _formatDate(_dateOfBirth!)
                            : 'Enter your date of birth',
                        subtitle:
                            age != null ? 'Age: $age years old' : null,
                        onTap: () => _pickDateOfBirth(accent),
                        labelColor: labelColor,
                        fieldBg: cardColor,
                        onSurface: onSurface,
                      ),

                      const SizedBox(height: 16),

                      _buildInfoField(
                        label: 'Gender',
                        value: _gender,
                        onTap: () => _showGenderPicker(
                            accent: accent,
                            isDark: isDark,
                            onSurface: onSurface),
                        labelColor: labelColor,
                        fieldBg: cardColor,
                        onSurface: onSurface,
                      ),

                      const SizedBox(height: 30),

                      // Save button
                      SizedBox(
                        width: double.infinity,
                        height: btnH,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _saveProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            disabledBackgroundColor:
                                accent.withValues(alpha: 0.6),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white))
                              : const Text(
                                  'Save Changes',
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                        ),
                      ),

                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}