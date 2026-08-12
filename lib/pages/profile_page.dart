import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Profile & Settings Page - Tharuka Karunarathne
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/student_learning_models.dart';
import '../theme/app_theme.dart';
import '../widgets/student_app_shell.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return StudentAppShell(
      activeSection: StudentNavSection.settings,
      userName: currentAuthUserName(),
      notificationCount: 0,
      onSectionSelected: (section) => _openSection(context, section),
      child: const _SettingsContent(),
    );
  }

  static void _openSection(BuildContext context, StudentNavSection section) {
    if (section == StudentNavSection.settings) return;
    Navigator.pushNamed(context, _routeForSection(section));
  }

  static String _routeForSection(StudentNavSection section) {
    switch (section) {
      case StudentNavSection.dashboard:
        return '/student-dashboard';
      case StudentNavSection.teacherMessages:
        return '/teacher-messages';
      case StudentNavSection.uploadMaterial:
        return '/upload';
      case StudentNavSection.aiFeedback:
        return '/ai-feedback';
      case StudentNavSection.reviewSchedule:
        return '/review';
      case StudentNavSection.analytics:
        return '/analytics';
      case StudentNavSection.settings:
        return '/profile';
    }
  }
}

class _SettingsContent extends StatefulWidget {
  const _SettingsContent();

  @override
  State<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<_SettingsContent> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _currentPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController(text: '');
  final _confirmPassCtrl = TextEditingController(text: '');

  String _difficulty = 'Adaptive (AI-controlled)';
  bool _focusMode = true;
  bool _reviewReminders = true;
  bool _weeklyReport = true;
  bool _newFeatures = false;
  bool _emailDigest = true;

  bool _showCurrentPass = false;
  bool _showNewPass = false;
  bool _showConfirmPass = false;
  bool _isLoading = true;
  bool _isSavingProfile = false;
  bool _isSavingPassword = false;
  String _role = 'student';

  static const _difficultyOptions = [
    'Adaptive (AI-controlled)',
    'Easy',
    'Medium',
    'Hard',
  ];

  User? get _user => FirebaseAuth.instance.currentUser;
  DocumentReference<Map<String, dynamic>>? get _userDoc {
    final user = _user;
    if (user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  String get _displayName {
    final fullName = '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'.trim();
    final authName = _user?.displayName?.trim();
    return fullName.isNotEmpty
        ? fullName
        : authName?.isNotEmpty == true
            ? authName!
            : _user?.email?.split('@').first ?? 'Student';
  }

  String get _initial {
    final name = _displayName.trim();
    return name.isEmpty ? 'S' : name[0].toUpperCase();
  }

  String get _roleLabel {
    if (_role.isEmpty) return 'Student';
    return '${_role[0].toUpperCase()}${_role.substring(1)}';
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final user = _user;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    _emailCtrl.text = user.email ?? '';

    Map<String, dynamic> data = {};
    try {
      final snapshot = await _userDoc?.get();
      data = snapshot?.data() ?? {};
    } catch (_) {
      data = {};
    }

    if (!mounted) return;

    final displayName = (data['displayName'] as String?)?.trim().isNotEmpty == true
        ? (data['displayName'] as String).trim()
        : user.displayName?.trim() ?? '';
    final fallbackName = displayName.isNotEmpty
        ? displayName
        : user.email?.split('@').first ?? '';

    _firstNameCtrl.text =
        (data['firstName'] as String?)?.trim().isNotEmpty == true
            ? (data['firstName'] as String).trim()
            : _firstNameFrom(fallbackName);
    _lastNameCtrl.text =
        (data['lastName'] as String?)?.trim().isNotEmpty == true
            ? (data['lastName'] as String).trim()
            : _lastNameFrom(fallbackName);

    final rawSettings = data['settings'];
    final settings = rawSettings is Map
        ? Map<String, dynamic>.from(rawSettings)
        : const <String, dynamic>{};

    final savedDifficulty = settings['difficulty'] as String?;
    _difficulty = _difficultyOptions.contains(savedDifficulty)
        ? savedDifficulty!
        : 'Adaptive (AI-controlled)';
    _focusMode = settings['focusMode'] as bool? ?? true;
    _reviewReminders = settings['reviewReminders'] as bool? ?? true;
    _weeklyReport = settings['weeklyReport'] as bool? ?? true;
    _newFeatures = settings['newFeatures'] as bool? ?? false;
    _emailDigest = settings['emailDigest'] as bool? ?? true;
    _role = (data['role'] as String?)?.trim().isNotEmpty == true
        ? (data['role'] as String).trim().toLowerCase()
        : 'student';

    if (mounted) setState(() => _isLoading = false);
  }

  String _firstNameFrom(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? '' : parts.first;
  }

  String _lastNameFrom(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length <= 1) return '';
    return parts.skip(1).join(' ');
  }

  void _showSavedSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(message),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _saveProfile() async {
    final user = _user;
    final doc = _userDoc;
    if (user == null || doc == null) return;

    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final displayName = '$firstName $lastName'.trim();

    if (displayName.isEmpty) {
      _showErrorSnackbar('Enter your name before saving.');
      return;
    }

    setState(() => _isSavingProfile = true);
    try {
      await user.updateDisplayName(displayName);
      await doc.set({
        'uid': user.uid,
        'email': user.email,
        'displayName': displayName,
        'firstName': firstName,
        'lastName': lastName,
        'role': _role,
        'settings': _settingsPayload(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {});
      _showSavedSnackbar('Profile saved');
    } catch (_) {
      if (mounted) _showErrorSnackbar('Could not save profile. Try again.');
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  Future<void> _saveSettings({String? successMessage}) async {
    final user = _user;
    final doc = _userDoc;
    if (user == null || doc == null) return;

    try {
      await doc.set({
        'uid': user.uid,
        'email': user.email,
        'displayName': _displayName,
        'role': _role,
        'settings': _settingsPayload(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted && successMessage != null) _showSavedSnackbar(successMessage);
    } catch (_) {
      if (mounted) _showErrorSnackbar('Could not save settings. Try again.');
    }
  }

  Map<String, dynamic> _settingsPayload() {
    return {
      'difficulty': _difficulty,
      'focusMode': _focusMode,
      'reviewReminders': _reviewReminders,
      'weeklyReport': _weeklyReport,
      'newFeatures': _newFeatures,
      'emailDigest': _emailDigest,
    };
  }

  Future<void> _updatePassword() async {
    final user = _user;
    if (user == null) return;

    if (_newPassCtrl.text.isEmpty) {
      _showErrorSnackbar('Please enter a new password');
      return;
    }
    if (_currentPassCtrl.text.isEmpty) {
      _showErrorSnackbar('Please enter your current password');
      return;
    }
    if (_newPassCtrl.text.length < 6) {
      _showErrorSnackbar('Password must be at least 6 characters');
      return;
    }
    if (_newPassCtrl.text != _confirmPassCtrl.text) {
      _showErrorSnackbar('Passwords do not match');
      return;
    }

    setState(() => _isSavingPassword = true);
    try {
      final email = user.email;
      if (email != null && email.isNotEmpty) {
        final credential = EmailAuthProvider.credential(
          email: email,
          password: _currentPassCtrl.text,
        );
        await user.reauthenticateWithCredential(credential);
      }
      await user.updatePassword(_newPassCtrl.text.trim());
      _currentPassCtrl.clear();
      _newPassCtrl.clear();
      _confirmPassCtrl.clear();
      if (mounted) _showSavedSnackbar('Password updated successfully');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'requires-recent-login') {
        _showErrorSnackbar('Please sign in again before changing password.');
      } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        _showErrorSnackbar('Current password is incorrect.');
      } else {
        _showErrorSnackbar('Could not update password. Try again.');
      }
    } catch (_) {
      if (mounted) _showErrorSnackbar('Could not update password. Try again.');
    } finally {
      if (mounted) setState(() => _isSavingPassword = false);
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings & Account',
            style: GoogleFonts.openSans(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Manage your profile, account security, and learning preferences',
            style: GoogleFonts.openSans(color: AppColors.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 28),

          // ── Profile Information ──
          _sectionCard(
            title: 'Profile Information',
            icon: null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _initial,
                        style: GoogleFonts.openSans(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayName,
                            style: GoogleFonts.openSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _emailCtrl.text,
                            style: GoogleFonts.openSans(
                              color: AppColors.textMuted,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0E7EF),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _roleLabel,
                              style: GoogleFonts.openSans(
                                color: AppColors.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('First Name'),
                          const SizedBox(height: 6),
                          _field(controller: _firstNameCtrl),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Last Name'),
                          const SizedBox(height: 6),
                          _field(controller: _lastNameCtrl),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _label('Email Address'),
                const SizedBox(height: 6),
                SizedBox(
                  width: 400,
                  child: _field(controller: _emailCtrl, readOnly: true),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isSavingProfile ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                  child: Text(
                    _isSavingProfile ? 'Saving...' : 'Save',
                    style: GoogleFonts.openSans(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Learning Preferences ──
          _sectionCard(
            title: 'Learning Preferences',
            icon: Icons.menu_book_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Default Difficulty'),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: _difficulty,
                            items:
                                _difficultyOptions
                                    .map(
                                      (d) => DropdownMenuItem(
                                        value: d,
                                        child: Text(d),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (v) {
                              setState(() => _difficulty = v!);
                              _saveSettings(
                                successMessage: 'Difficulty updated to $v',
                              );
                            },
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD1D5DB),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD1D5DB),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(child: SizedBox()),
                  ],
                ),
                const SizedBox(height: 16),
                _toggleRow(
                  'Focus Mode',
                  'Hide distractions during learning sessions',
                  _focusMode,
                  (v) {
                    setState(() => _focusMode = v);
                    _saveSettings(
                      successMessage:
                      'Focus Mode ${v ? 'enabled' : 'disabled'}',
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Notification Settings ──
          _sectionCard(
            title: 'Notification Settings',
            icon: Icons.notifications_none_rounded,
            child: Column(
              children: [
                _toggleRow(
                  'Review Reminders',
                  "Get notified when it's time to review topics",
                  _reviewReminders,
                  (v) {
                    setState(() => _reviewReminders = v);
                    _saveSettings(
                      successMessage: 'Review Reminders ${v ? 'on' : 'off'}',
                    );
                  },
                ),
                const SizedBox(height: 10),
                _toggleRow(
                  'Weekly Progress Report',
                  'Receive weekly summaries of your learning progress',
                  _weeklyReport,
                  (v) {
                    setState(() => _weeklyReport = v);
                    _saveSettings(
                      successMessage: 'Weekly Report ${v ? 'on' : 'off'}',
                    );
                  },
                ),
                const SizedBox(height: 10),
                _toggleRow(
                  'New Features',
                  'Be the first to know about new platform features',
                  _newFeatures,
                  (v) {
                    setState(() => _newFeatures = v);
                    _saveSettings(
                      successMessage: 'New Features ${v ? 'on' : 'off'}',
                    );
                  },
                ),
                const SizedBox(height: 10),
                _toggleRow(
                  'Email Digest',
                  'Daily email with your learning stats and recommendations',
                  _emailDigest,
                  (v) {
                    setState(() => _emailDigest = v);
                    _saveSettings(
                      successMessage: 'Email Digest ${v ? 'on' : 'off'}',
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Security ──
          _sectionCard(
            title: 'Security',
            icon: Icons.lock_outline_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Current Password'),
                const SizedBox(height: 6),
                SizedBox(
                  width: 400,
                  child: _field(
                    controller: _currentPassCtrl,
                    obscure: !_showCurrentPass,
                    onToggle: () =>
                        setState(() => _showCurrentPass = !_showCurrentPass),
                    isVisible: _showCurrentPass,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('New Password'),
                          const SizedBox(height: 6),
                          _field(
                            controller: _newPassCtrl,
                            obscure: !_showNewPass,
                            onToggle: () =>
                                setState(() => _showNewPass = !_showNewPass),
                            isVisible: _showNewPass,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Confirm Password'),
                          const SizedBox(height: 6),
                          _field(
                            controller: _confirmPassCtrl,
                            obscure: !_showConfirmPass,
                            onToggle: () => setState(
                              () => _showConfirmPass = !_showConfirmPass,
                            ),
                            isVisible: _showConfirmPass,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isSavingPassword ? null : _updatePassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                  child: Text(
                    _isSavingPassword ? 'Updating...' : 'Update Password',
                    style: GoogleFonts.openSans(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData? icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: AppColors.textMuted),
                const SizedBox(width: 8),
              ],
              Text(
                title,
                style: GoogleFonts.openSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _toggleRow(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.openSans(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.openSans(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.accent,
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: GoogleFonts.openSans(
        color: Color(0xFF374151),
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    bool obscure = false,
    VoidCallback? onToggle,
    bool? isVisible,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      readOnly: readOnly,
      style: GoogleFonts.openSans(color: AppColors.textDark, fontSize: 14),
      decoration: InputDecoration(
        suffixIcon: onToggle != null
            ? IconButton(
                onPressed: onToggle,
                icon: Icon(
                  // eye closed = password hidden, eye open = password shown
                  isVisible == true
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.textFaint,
                  size: 18,
                ),
              )
            : null,
        filled: true,
        fillColor: readOnly ? AppColors.bgPage : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
    );
  }
}
