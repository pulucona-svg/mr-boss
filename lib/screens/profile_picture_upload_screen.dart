import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/user_provider.dart';
import 'reset_password_screen.dart';

class ProfilePictureUploadScreen extends ConsumerStatefulWidget {
  final String email;
  const ProfilePictureUploadScreen({super.key, required this.email});

  @override
  ConsumerState<ProfilePictureUploadScreen> createState() => _ProfilePictureUploadScreenState();
}

class _ProfilePictureUploadScreenState extends ConsumerState<ProfilePictureUploadScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        setState(() => _isUploading = true);
        await ref.read(userProfileProvider.notifier).setProfileImage(pickedFile.path);
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProfile = ref.watch(userProfileProvider);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/login_bg.jpeg',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.5),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Text(
                          'Profile Picture',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _isUploading ? null : () {
                          Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
                        },
                        child: Text(
                          'Skip',
                          style: TextStyle(color: _isUploading ? Colors.grey : Colors.white70, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF14142B).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Add a Profile Picture',
                          style: TextStyle(
                            color: Color(0xFF20C8FF),
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'A profile picture helps your friends recognize you.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 32),
                        Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF20C8FF), width: 3),
                              ),
                              child: CircleAvatar(
                                radius: 70,
                                backgroundColor: Colors.white10,
                                backgroundImage: userProfile.profileImagePath != null
                                    ? FileImage(File(userProfile.profileImagePath!))
                                    : (userProfile.photoURL != null 
                                        ? CachedNetworkImageProvider(userProfile.photoURL!) as ImageProvider
                                        : null),
                                child: (userProfile.profileImagePath == null && userProfile.photoURL == null && !_isUploading)
                                    ? const Icon(Icons.person, size: 80, color: Colors.white54)
                                    : null,
                              ),
                            ),
                            if (_isUploading)
                              Positioned.fill(
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.black45,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(
                                    child: CircularProgressIndicator(color: Color(0xFF20C8FF)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        Row(
                          children: [
                            Expanded(
                              child: _buildUploadOption(
                                icon: Icons.camera_alt_rounded,
                                label: 'Camera',
                                onTap: _isUploading ? () {} : () => _pickImage(ImageSource.camera),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildUploadOption(
                                icon: Icons.image_rounded,
                                label: 'Gallery',
                                onTap: _isUploading ? () {} : () => _pickImage(ImageSource.gallery),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            onPressed: (userProfile.profileImagePath != null || userProfile.photoURL != null) && !_isUploading
                                ? () {
                                    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: (userProfile.profileImagePath != null || userProfile.photoURL != null)
                                  ? const Color(0xFF20C8FF)
                                  : Colors.grey.withOpacity(0.5),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: (userProfile.profileImagePath != null || userProfile.photoURL != null) ? 4 : 0,
                            ),
                            child: _isUploading 
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text(
                                  'CONTINUE',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadOption({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF20C8FF), size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
