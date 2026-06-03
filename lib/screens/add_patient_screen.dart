// lib/screens/add_patient_screen.dart
//
// Caregiver enters a patient's email address.
// CaregiverService.linkPatientByEmail() looks up the patient in Firestore
// and creates the two-way link.
//
// UPDATED: Wrapped in CaregiverThemeWrapper so dark/HC mode, font scale and
// button scale from CaregiverAccessibilityProvider are applied automatically.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/caregiver_accessibility_provider.dart';
import '../services/caregiver_service.dart';
import 'caregiver_theme_wrapper.dart';

class AddPatientScreen extends StatefulWidget {
  const AddPatientScreen({super.key});

  @override
  State<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends State<AddPatientScreen> {
  final _service = CaregiverService();
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;

  static const _teal = Color(0xFF2BC8A7);

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _linkPatient() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      await _service.linkPatientByEmail(_emailController.text.trim());
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Patient linked successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CaregiverThemeWrapper(
      builder: (ctx, acc) {
        final cs     = Theme.of(ctx).colorScheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bgColor    = isDark ? const Color(0xFF121212) : const Color(0xFFF4F7FF);
        final cardColor  = isDark ? const Color(0xFF1E1E2E) : Colors.white;
        final hintColor  = isDark ? Colors.white38 : Colors.black38;
        final labelColor = isDark ? Colors.white70 : Colors.black45;
        final btnH       = 52.0 * acc.buttonScaleFactor;

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            backgroundColor: bgColor,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios, size: 20, color: cs.onSurface),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Add Patient',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            centerTitle: true,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Icon ──────────────────────────────────────────────
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        Icons.person_add_outlined,
                        color: cs.primary,
                        size: 38,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  Text(
                    'Link a Patient',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the email address of the patient you want to monitor. '
                    'They must have already signed up as a Patient.',
                    style: TextStyle(
                      fontSize: 14,
                      color: labelColor,
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 32),

                  Text(
                    'Patient Email',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _linkPatient(),
                    style: TextStyle(fontSize: 15, color: cs.onSurface),
                    decoration: InputDecoration(
                      hintText: 'patient@example.com',
                      hintStyle: TextStyle(color: hintColor, fontSize: 14),
                      prefixIcon: Icon(Icons.email_outlined,
                          color: hintColor, size: 20),
                      filled: true,
                      fillColor: cardColor,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: isDark
                            ? BorderSide(
                                color: Colors.white.withValues(alpha: 0.08))
                            : BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            BorderSide(color: cs.primary, width: 1.5),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: Colors.redAccent, width: 1.2),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: Colors.redAccent, width: 1.5),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter the patient\'s email';
                      }
                      if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$')
                          .hasMatch(v.trim())) {
                        return 'Please enter a valid email address';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    height: btnH,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _linkPatient,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.primary,
                        disabledBackgroundColor:
                            cs.primary.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Link Patient',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Info note ─────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2C2A1A)
                          : const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF5C5020)
                            : const Color(0xFFFFE082),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: Color(0xFFFFA000), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'The patient must sign up using the Patient role before you can link them.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFFD4B896)
                                  : const Color(0xFF795548),
                              height: 1.4,
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
      },
    );
  }
}