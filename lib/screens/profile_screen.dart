import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../widgets/skeleton.dart';
import '../widgets/glass_card.dart';
import '../widgets/academic_fields.dart';
import '../providers/theme_provider.dart';
import '../providers/upload_provider.dart';
import '../providers/user_provider.dart';
import '../services/course_service.dart';
import 'help_support_screen.dart';
import 'reset_password_screen.dart';
import 'library_screen.dart';
import 'login_screen.dart';
import '../providers/firebase_auth_provider.dart';

import 'subscription_screen.dart';
import '../services/subscription_service.dart';

import 'analytics_screen.dart';
import '../services/usage_service.dart';
import '../services/persistence_service.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  static bool _hasLoadedBefore = false;
  late bool _isLoading;

  @override
  void initState() {
    super.initState();
    _isLoading = !_hasLoadedBefore;
    if (_isLoading) {
      _simulateLoading();
    }
  }

  void _simulateLoading() async {
    await Future.delayed(const Duration(milliseconds: 1500));
    _hasLoadedBefore = true;
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final userProfile = ref.watch(userProfileProvider);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF070716) : Colors.white,
        body: const ProfileSkeleton(),
      );
    }

    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white60 : Colors.black54;

    final resourceService = ref.watch(resourceServiceProvider);
    final approvedContributions = resourceService.userUploads.where((r) => r.status == 'approved').length;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF23144D), Color(0xFF090914)],
                )
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.blue.shade50, Colors.white],
                ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 40),
                    Text(
                      'My Profile',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        shadows: isDark ? [
                          Shadow(
                            color: Colors.pinkAccent.withOpacity(0.5),
                            blurRadius: 10,
                          ),
                          Shadow(
                            color: Colors.blueAccent.withOpacity(0.5),
                            blurRadius: 20,
                          ),
                        ] : [],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.emoji_events_outlined, color: Colors.amber),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // Profile Header
                    Center(
                      child: Stack(
                        children: [
                          GestureDetector(
                            onTap: () => _openFullScreenProfile(context, isDark),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF20C8FF),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF20C8FF).withOpacity(0.3),
                                    blurRadius: 15,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 50,
                                backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                                backgroundImage: userProfile.profileImagePath != null
                                    ? FileImage(File(userProfile.profileImagePath!))
                                    : (userProfile.photoURL != null 
                                        ? NetworkImage(userProfile.photoURL!) 
                                        : null),
                                child: (userProfile.profileImagePath == null && userProfile.photoURL == null)
                                    ? Icon(Icons.person, size: 50, color: isDark ? Colors.white54 : Colors.grey)
                                    : null,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () => _showProfilePhotoMenu(context, isDark),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1A1A3F) : Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 6,
                                      spreadRadius: 1,
                                    )
                                  ],
                                ),
                                child: Icon(
                                  Icons.camera_alt_rounded,
                                  color: isDark ? Colors.white : Colors.blue,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        userProfile.username,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        userProfile.program,
                        style: TextStyle(
                          color: subTextColor,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Stats Row
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatBox(
                            Icons.cloud_queue,
                            approvedContributions.toString(),
                            'Contributions',
                            isDark,
                            iconColor: approvedContributions > 0 ? Colors.greenAccent : Colors.white,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const LibraryScreen(initialShowUploads: true),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: _buildStatBox(Icons.star, '0', 'Stars', isDark, iconColor: Colors.amber)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ListenableBuilder(
                            listenable: UsageService(),
                            builder: (context, child) {
                              final streak = UsageService().streak;
                              return _buildStatBox(
                                Icons.local_fire_department, 
                                streak.toString(), 
                                'Day Streak', 
                                isDark, 
                                iconColor: Colors.orange,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const AnalyticsScreen()),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: _buildStatBox(null, '2450', 'XP Points', isDark, customIcon: 'XP')),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Academic Personalization
                    _buildGlassCard(
                      isDark: isDark,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Academic Personalization',
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Icon(Icons.chevron_right, color: textColor.withOpacity(0.5)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow('Institution', userProfile.institution, textColor, subTextColor),
                          const SizedBox(height: 8),
                          _buildDetailRow('Program', userProfile.program, textColor, subTextColor),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildDetailRow('Year', userProfile.year, textColor, subTextColor),
                                    const SizedBox(height: 8),
                                    _buildDetailRow('Semester', userProfile.semester, textColor, subTextColor),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF20C8FF).withOpacity(0.4),
                                      blurRadius: 10,
                                      spreadRadius: -2,
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: () => _showEditDetailsModal(context, isDark),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF20C8FF),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: const Text('Edit Details', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(color: Colors.white10),
                          const SizedBox(height: 8),
                          _buildDetailRow('Phone', userProfile.phone, textColor, subTextColor),
                          const SizedBox(height: 8),
                          _buildDetailRow('Email', userProfile.email, textColor, subTextColor),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Support Us
                    Text(
                      'Support Us',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildStatusBadge('Donate', 'ACTIVE', Icons.verified, Colors.blue, isDark)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ListenableBuilder(
                            listenable: SubscriptionService(),
                            builder: (context, child) {
                              final isSubscribed = SubscriptionService().isSubscribed;
                              return _buildStatusBadge(
                                'Subscription', 
                                isSubscribed ? 'ACTIVE' : 'INACTIVE', 
                                Icons.workspace_premium, 
                                Colors.orange, 
                                isDark,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const SubscriptionScreen()),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildStatusBadge(
                            'Contribute',
                            'ACTIVE',
                            Icons.auto_awesome,
                            Colors.purple,
                            isDark,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const LibraryScreen(initialShowUploads: true),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Theme Mode
                    Text(
                      'Theme Mode',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            _buildThemeOption('Dark', isDark),
                            const SizedBox(width: 8),
                            _buildThemeOption('Light', isDark),
                          ],
                        ),
                        Switch(
                          value: !isDark,
                          onChanged: (val) {
                            ref.read(themeProvider.notifier).setTheme(val ? ThemeMode.light : ThemeMode.dark);
                          },
                          activeColor: const Color(0xFF20C8FF),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Footer Links
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Flexible(child: _buildFooterLink('Help & Support', textColor)),
                        Flexible(child: _buildFooterLink('Privacy Policy', textColor)),
                        Flexible(child: _buildFooterLink('Change Password', textColor)),
                      ],
                    ),
                    const SizedBox(height: 20),


                    // Log Out Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final authService = ref.read(authServiceProvider);
                          await authService.signOut();
                          await PersistenceService().clearSession();
                          if (context.mounted) {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (context) => const LoginScreen()),
                              (route) => false,
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withOpacity(0.8),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Log Out',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child, required bool isDark, EdgeInsetsGeometry padding = const EdgeInsets.all(14)}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: isDark 
          ? const Color(0xFF181739).withOpacity(0.72)
          : Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? const Color(0xFF302B65) : Colors.blue.shade100),
        boxShadow: isDark ? [] : [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 2,
          )
        ],
      ),
      child: child,
    );
  }

  Widget _buildStatBox(IconData? icon, String value, String label, bool isDark, {Color iconColor = Colors.white, String? customIcon, VoidCallback? onTap}) {
    final textColor = isDark ? Colors.white : Colors.black87;
    return GestureDetector(
      onTap: onTap,
      child: _buildGlassCard(
        isDark: isDark,
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) Icon(icon, color: isDark ? iconColor : (iconColor == Colors.white ? Colors.blue : iconColor), size: 18),
                  if (customIcon != null) Text(customIcon, style: TextStyle(color: isDark ? Colors.white : Colors.blue, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(width: 4),
                  Text(
                    value,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, Color textColor, Color subTextColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 75,
          child: Text(
            label,
            style: TextStyle(color: subTextColor, fontSize: 13),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String title, String status, IconData icon, Color color, bool isDark, {VoidCallback? onTap}) {
    bool isActive = status == 'ACTIVE';
    final textColor = isDark ? Colors.white : Colors.black87;
    return GestureDetector(
      onTap: onTap,
      child: _buildGlassCard(
        isDark: isDark,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: (isActive ? Colors.green : Colors.red).withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: (isActive ? Colors.green : Colors.red).withOpacity(0.5)),
              ),
              child: Text(
                status,
                style: TextStyle(
                  color: isActive ? Colors.greenAccent : (isDark ? Colors.redAccent : Colors.red),
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption(String label, bool isDark) {
    bool isSelected = (label == 'Dark' && isDark) || (label == 'Light' && !isDark);
    final textColor = isDark ? Colors.white : Colors.black87;
    
    return GestureDetector(
      onTap: () {
        ref.read(themeProvider.notifier).setTheme(label == 'Dark' ? ThemeMode.dark : ThemeMode.light);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected 
            ? (isDark ? Colors.white.withOpacity(0.1) : Colors.blue.withOpacity(0.1))
            : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? (isDark ? Colors.white30 : Colors.blue.withOpacity(0.3)) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? textColor : (isDark ? Colors.white38 : Colors.black38),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  void _showEditDetailsModal(BuildContext context, bool isDark) {
    final userProfile = ref.read(userProfileProvider);
    final courseService = ref.read(courseServiceProvider);

    final nameController = TextEditingController(text: userProfile.username);
    final instController = TextEditingController(text: userProfile.institution);
    final progController = TextEditingController(text: userProfile.program);
    final yearController = TextEditingController(text: userProfile.year);
    final semController = TextEditingController(text: userProfile.semester);
    final phoneController = TextEditingController(text: userProfile.phone);
    final emailController = TextEditingController(text: userProfile.email);

    String? instLocation = courseService.getUniversityLocation(userProfile.institution);
    String? progCode = courseService.getProgramCode(userProfile.program);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final cleanPhone = phoneController.text.replaceAll('+254', '0').replaceAll(RegExp(r'\D'), '');
          bool phoneValid = cleanPhone.length == 10 && (cleanPhone.startsWith('07') || cleanPhone.startsWith('01'));

          bool isFormValid = nameController.text.length >= 3 &&
              nameController.text.length <= 20 &&
              instController.text.isNotEmpty &&
              progController.text.isNotEmpty &&
              yearController.text.isNotEmpty &&
              semController.text.isNotEmpty &&
              phoneValid &&
              emailController.text.length >= 13 &&
              emailController.text.length <= 30;

          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF14142B) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Edit Details',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    children: [
                      // Username with live char limit and validation
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 4, bottom: 8),
                                child: Text(
                                  'Username',
                                  style: TextStyle(
                                    color: isDark ? Colors.white70 : Colors.black54,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Text(
                                '${nameController.text.length}/20',
                                style: TextStyle(
                                  color: nameController.text.length < 3 || nameController.text.length > 20
                                      ? Colors.redAccent
                                      : Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                            ),
                            child: TextField(
                              controller: nameController,
                              maxLength: 20,
                              onChanged: (val) => setModalState(() {}),
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                counterText: '',
                                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Institution Autocomplete
                      AcademicAutocompleteField(
                        label: 'Institution',
                        controller: instController,
                        suggestions: courseService.universityNames,
                        isDark: isDark,
                        subText: instLocation,
                        onChanged: (val) => setModalState(() {}),
                        onSelected: (val) {
                          setModalState(() {
                            instLocation = courseService.getUniversityLocation(val);
                          });
                        },
                      ),

                      // Program Autocomplete
                      AcademicAutocompleteField(
                        label: 'Program',
                        controller: progController,
                        suggestions: courseService.programsList,
                        isDark: isDark,
                        subText: progCode,
                        onChanged: (val) => setModalState(() {}),
                        onSelected: (val) {
                          setModalState(() {
                            progCode = courseService.getProgramCode(val);
                          });
                        },
                      ),

                      Row(
                        children: [
                          // Year Dropdown
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                                  child: Text(
                                    'Year',
                                    style: TextStyle(
                                      color: isDark ? Colors.white70 : Colors.black54,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Container(
                                  margin: const EdgeInsets.only(bottom: 20),
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: yearController.text,
                                      isExpanded: true,
                                      dropdownColor: isDark ? const Color(0xFF1F1F3D) : Colors.white,
                                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                                      items: ['Year 1', 'Year 2', 'Year 3', 'Year 4'].map((String value) {
                                        return DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(value),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setModalState(() {
                                            yearController.text = val;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Semester Read-only
                          Expanded(child: _buildEditField('Semester', semController, isDark, enabled: false)),
                        ],
                      ),

                      SmartPhoneField(
                        label: 'Phone Number',
                        controller: phoneController,
                        isDark: isDark,
                        onChanged: (val) => setModalState(() {}),
                      ),

                      _buildEditField(
                        'Email Address',
                        emailController,
                        isDark,
                        keyboardType: TextInputType.emailAddress,
                        maxLength: 30,
                        onChanged: (val) => setModalState(() {}),
                      ),

                      const SizedBox(height: 10),

                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          onPressed: isFormValid
                              ? () {
                                  ref.read(userProfileProvider.notifier).updateProfile(
                                        username: nameController.text,
                                        institution: instController.text,
                                        program: progController.text,
                                        year: yearController.text,
                                        semester: semController.text,
                                        phone: phoneController.text,
                                        email: emailController.text,
                                      );
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Details updated successfully')),
                                  );
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isFormValid ? const Color(0xFF20C8FF) : Colors.grey,
                            disabledBackgroundColor: Colors.grey,
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white60,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('CHANGE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEditField(
    String label,
    TextEditingController controller,
    bool isDark, {
    TextInputType? keyboardType,
    bool enabled = true,
    int? maxLength,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            enabled: enabled,
            maxLength: maxLength,
            onChanged: onChanged,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: const InputDecoration(
              border: InputBorder.none,
              counterText: '',
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  void _showPrivacyPolicyDialog(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A1A3F) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Privacy Policy',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPolicySection(
                  '1. Information We Collect',
                  'To deliver our services effectively, we collect limited information, including:\n\n'
                  'Account Information: Username, email address, and securely encrypted password.\n\n'
                  'Activity Information: Records of uploads, downloads, and viewed documents.\n\n'
                  'Technical Information: IP address, browser type, and related security data.',
                  isDark,
                ),
                const SizedBox(height: 16),
                _buildPolicySection(
                  '2. How We Use Your Information',
                  'Your information is used to:\n\n'
                  '• Enable access to your personal library and activity history.\n'
                  '• Enhance website functionality and improve content suggestions.\n'
                  '• Detect fraudulent activity and maintain platform security.\n\n'
                  'We do not trade, rent, or sell your personal information to third parties.',
                  isDark,
                ),
                const SizedBox(height: 16),
                _buildPolicySection(
                  '3. Cookies',
                  'Cookies are used to keep you signed in and store your preferences for a better browsing experience.',
                  isDark,
                ),
                const SizedBox(height: 16),
                _buildPolicySection(
                  '4. Third-Party Services',
                  'We may rely on trusted third-party providers for services such as:\n\n'
                  '• Website analytics (for example, Google Analytics)',
                  isDark,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Color(0xFF20C8FF), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicySection(String title, String content, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildFooterLink(String text, Color textColor) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;
    return GestureDetector(
      onTap: () {
        if (text == 'Help & Support') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const HelpSupportScreen()),
          );
        } else if (text == 'Privacy Policy') {
          _showPrivacyPolicyDialog(context, isDark);
        } else if (text == 'Change Password') {
          final userEmail = ref.read(userProfileProvider).email;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ResetPasswordScreen(
                showInitialSuccess: true,
                email: userEmail,
              ),
            ),
          );
        }
      },
      child: Text(
        text,
        style: TextStyle(
          color: textColor.withOpacity(0.7),
          fontSize: 12,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }

  void _showProfilePhotoMenu(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF14142B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.only(top: 12, left: 8, right: 8, bottom: 40), // Increased bottom padding
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.close, color: isDark ? Colors.white : Colors.black),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    'Profile picture',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: isDark ? Colors.white : Colors.black),
                  onPressed: () {
                    ref.read(userProfileProvider.notifier).clearProfileImage();
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.image_outlined, color: isDark ? Colors.white70 : Colors.black54),
              title: Text('Gallery', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
              onTap: () => _pickImage(ImageSource.gallery),
            ),
            ListTile(
              leading: Icon(Icons.camera_alt_outlined, color: isDark ? Colors.white70 : Colors.black54),
              title: Text('Camera', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
              onTap: () => _pickImage(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(source: source);
      if (pickedFile != null) {
        ref.read(userProfileProvider.notifier).setProfileImage(pickedFile.path);
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  void _openFullScreenProfile(BuildContext context, bool isDark) {
    final userProfile = ref.read(userProfileProvider);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xFF070716),
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: MediaQuery.of(context).size.height * 0.45,
                pinned: true,
                stretch: true,
                backgroundColor: const Color(0xFF070716),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(icon: const Icon(Icons.grid_view_rounded, color: Colors.white), onPressed: () {}),
                  IconButton(icon: const Icon(Icons.more_vert, color: Colors.white), onPressed: () {}),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [
                    StretchMode.zoomBackground,
                    StretchMode.blurBackground,
                  ],
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      userProfile.profileImagePath != null
                          ? Image.file(File(userProfile.profileImagePath!), fit: BoxFit.cover)
                          : Container(
                              color: isDark ? const Color(0xFF1A1A3F) : Colors.grey.shade200,
                              child: Center(
                                child: Icon(
                                  Icons.person,
                                  size: 150,
                                  color: isDark ? Colors.white10 : Colors.white70,
                                ),
                              ),
                            ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.3),
                              Colors.transparent,
                              Colors.black.withOpacity(0.8),
                            ],
                            stops: const [0.0, 0.5, 1.0],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 20,
                        left: 20,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userProfile.username,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text(
                              'online',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Academic Personalization',
                        style: TextStyle(
                          color: Color(0xFF20C8FF),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 25),
                      _buildFullScreenDetailRow(Icons.school_outlined, 'Institution', userProfile.institution),
                      _buildFullScreenDetailRow(Icons.book_outlined, 'Program', userProfile.program),
                      _buildFullScreenDetailRow(Icons.calendar_today_outlined, 'Year', userProfile.year),
                      _buildFullScreenDetailRow(Icons.history_edu_outlined, 'Semester', userProfile.semester),
                      
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Divider(color: Colors.white12, thickness: 1),
                      ),
                      
                      const Text(
                        'Contact Details',
                        style: TextStyle(
                          color: Color(0xFF20C8FF),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 25),
                      _buildFullScreenDetailRow(Icons.phone_outlined, 'Phone', userProfile.phone),
                      _buildFullScreenDetailRow(Icons.chat_outlined, 'WhatsApp', userProfile.phone),
                      _buildFullScreenDetailRow(Icons.email_outlined, 'Email', userProfile.email),
                      
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Divider(color: Colors.white12, thickness: 1),
                      ),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Media, links, and docs',
                            style: TextStyle(color: Colors.white70, fontSize: 16),
                          ),
                          Row(
                            children: [
                              const Text('14', style: TextStyle(color: Colors.white38)),
                              const SizedBox(width: 4),
                              Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3), size: 20),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullScreenDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF20C8FF).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF20C8FF), size: 22),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
