// lib/screens/profile_settings_screen.dart
//
// Changes from previous version:
//   - Loads the current profile from Firestore via ProfileService.getProfile()
//     when the screen opens (initState).
//   - Save button calls ProfileService.saveProfile() to persist changes,
//     then pops with ProfileData for the home header to update immediately.

import 'package:flutter/material.dart';
import '../services/profile_service.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

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
  bool _isLoading = true; // true while fetching from Firestore
  bool _isSaving = false;

  static const List<String> _genderOptions = ['Male', 'Female', 'Non-binary'];

  static const List<Color> _avatarColors = [
    Color(0xFF3B71FE),
    Color(0xFF6B5BFF),
    Color(0xFF2BC8A7),
    Color(0xFFFFA726),
    Color(0xFFEF5350),
    Color(0xFF8E24AA),
    Color(0xFF42A5F5),
    Color(0xFF26A69A),
    Color(0xFFFFCA28),
  ];

  static const List<String> _avatarInitials = [
    'H', 'M', 'A', 'S', 'L', 'T', 'P', 'J', 'C',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // ── Load from Firestore ────────────────────────────────────────────────────

  Future<void> _loadProfile() async {
    try {
      final data = await _profileService.getProfile();
      if (data != null && mounted) {
        setState(() {
          _nameController.text = (data['name'] as String?) ?? '';
          _gender = (data['gender'] as String?) ?? 'Female';
          _selectedAvatarIndex = (data['avatarIndex'] as int?) ?? 0;
          final dob = data['dateOfBirth'];
          if (dob != null) {
            // Firestore Timestamp → DateTime
            _dateOfBirth = (dob as dynamic).toDate() as DateTime;
          }
        });
      }
    } catch (_) {
      // If fetch fails just show empty form — user can still fill in details
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Save to Firestore ──────────────────────────────────────────────────────

  Future<void> _saveProfile() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final name = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : 'User';

      await _profileService.saveProfile(
        name: name,
        dateOfBirth: _dateOfBirth,
        gender: _gender,
        avatarIndex: _selectedAvatarIndex,
      );

      if (!mounted) return;

      // Pop and return ProfileData so home_screen can update immediately
      // (before the stream fires)
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
          content: Text('Profile saved!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save profile: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Date picker ────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${date.day.toString().padLeft(2, '0')} - '
        '${months[date.month - 1]} - ${date.year}';
  }

  Future<void> _pickDateOfBirth() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(1998, 10, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF3B71FE),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF3B71FE),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (selected != null) setState(() => _dateOfBirth = selected);
  }

  void _showGenderPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose Gender',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 18),
              ..._genderOptions.map((option) {
                final selected = option == _gender;
                return ListTile(
                  title: Text(
                    option,
                    style: TextStyle(
                      fontSize: 16,
                      color: selected
                          ? const Color(0xFF3B71FE)
                          : Colors.black87,
                    ),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check, color: Color(0xFF3B71FE))
                      : null,
                  onTap: () {
                    setState(() => _gender = option);
                    Navigator.pop(context);
                  },
                );
              }),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B71FE),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAvatarPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Choose Avatar',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 5,
                    shrinkWrap: true,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    children: List.generate(_avatarColors.length, (i) {
                      final isSelected = i == _selectedAvatarIndex;
                      return GestureDetector(
                        onTap: () {
                          setModalState(() {});
                          setState(() => _selectedAvatarIndex = i);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(
                                    color: const Color(0xFF3B71FE),
                                    width: 3,
                                  )
                                : null,
                          ),
                          child: CircleAvatar(
                            backgroundColor: _avatarColors[i],
                            child: Text(
                              _avatarInitials[i],
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B71FE),
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInfoField({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[700],
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      color: value.contains('Enter')
                          ? Colors.grey
                          : Colors.black87,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
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
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4F7FF),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FF),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.black87,
                      size: 20,
                    ),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Edit Profile',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                ],
              ),
            ),

            // Form
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),

                      // Avatar
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: _avatarColors[
                                _selectedAvatarIndex % _avatarColors.length],
                            child: Text(
                              _avatarInitials[_selectedAvatarIndex],
                              style: const TextStyle(
                                fontSize: 32,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _showAvatarPicker,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 18,
                                color: Color(0xFF3B71FE),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      // Name
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Name',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.grey.withOpacity(0.2),
                          ),
                        ),
                        child: TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            hintText: 'Enter your name',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 18,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      _buildInfoField(
                        label: 'Date of Birth',
                        value: _dateOfBirth != null
                            ? _formatDate(_dateOfBirth!)
                            : 'Enter your date of birth',
                        onTap: _pickDateOfBirth,
                      ),

                      const SizedBox(height: 16),

                      _buildInfoField(
                        label: 'Gender',
                        value: _gender,
                        onTap: _showGenderPicker,
                      ),

                      const SizedBox(height: 30),

                      // Save button
                      ElevatedButton(
                        onPressed: _isSaving ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B71FE),
                          disabledBackgroundColor:
                              const Color(0xFF3B71FE).withOpacity(0.6),
                          minimumSize: const Size.fromHeight(60),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
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