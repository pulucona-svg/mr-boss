import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/user_provider.dart';
import '../services/course_service.dart';
import 'profile_screen.dart'; // To reuse widgets if needed, but they are private there.
import 'profile_picture_upload_screen.dart';

class AcademicPersonalizationScreen extends ConsumerStatefulWidget {
  final String email;
  const AcademicPersonalizationScreen({super.key, required this.email});

  @override
  ConsumerState<AcademicPersonalizationScreen> createState() => _AcademicPersonalizationScreenState();
}

class _AcademicPersonalizationScreenState extends ConsumerState<AcademicPersonalizationScreen> {
  late TextEditingController _instController;
  late TextEditingController _progController;
  late TextEditingController _yearController;
  late TextEditingController _semController;

  String? _instLocation;
  String? _progCode;

  @override
  void initState() {
    super.initState();
    final userProfile = ref.read(userProfileProvider);
    _instController = TextEditingController(text: userProfile.institution);
    _progController = TextEditingController(text: userProfile.program);
    _yearController = TextEditingController(text: userProfile.year);
    _semController = TextEditingController(text: userProfile.semester);
    
    final courseService = ref.read(courseServiceProvider);
    _instLocation = courseService.getUniversityLocation(userProfile.institution);
    _progCode = courseService.getProgramCode(userProfile.program);
  }

  @override
  void dispose() {
    _instController.dispose();
    _progController.dispose();
    _yearController.dispose();
    _semController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final courseService = ref.watch(courseServiceProvider);
    const isDark = true; // Signup flow uses dark themed cards over the image

    bool isFormValid = _instController.text.isNotEmpty &&
        _progController.text.isNotEmpty &&
        _yearController.text.isNotEmpty &&
        _semController.text.isNotEmpty;

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
              color: Colors.black.withOpacity(0.4),
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
                          'Academic Personalization',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48), // Spacer
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF14142B).withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tell us about your studies',
                            style: TextStyle(
                              color: Color(0xFF20C8FF),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          AcademicAutocompleteField(
                            label: 'Institution',
                            controller: _instController,
                            suggestions: courseService.universityNames,
                            isDark: isDark,
                            subText: _instLocation,
                            onChanged: (val) => setState(() {}),
                            onSelected: (val) {
                              setState(() {
                                _instLocation = courseService.getUniversityLocation(val);
                              });
                            },
                          ),

                          AcademicAutocompleteField(
                            label: 'Program',
                            controller: _progController,
                            suggestions: courseService.programsList,
                            isDark: isDark,
                            subText: _progCode,
                            onChanged: (val) => setState(() {}),
                            onSelected: (val) {
                              setState(() {
                                _progCode = courseService.getProgramCode(val);
                              });
                            },
                          ),

                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(left: 4, bottom: 8),
                                      child: Text(
                                        'Year',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 20),
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.white12),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _yearController.text,
                                          isExpanded: true,
                                          dropdownColor: const Color(0xFF1F1F3D),
                                          style: const TextStyle(color: Colors.white),
                                          items: ['Year 1', 'Year 2', 'Year 3', 'Year 4'].map((String value) {
                                            return DropdownMenuItem<String>(
                                              value: value,
                                              child: Text(value),
                                            );
                                          }).toList(),
                                          onChanged: (val) {
                                            if (val != null) {
                                              setState(() {
                                                _yearController.text = val;
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
                              Expanded(
                                child: _buildStaticField('Semester', _semController),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: ElevatedButton(
                              onPressed: isFormValid
                                  ? () {
                                      ref.read(userProfileProvider.notifier).updateProfile(
                                            institution: _instController.text,
                                            program: _progController.text,
                                            year: _yearController.text,
                                            semester: _semController.text,
                                            email: widget.email,
                                          );
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ProfilePictureUploadScreen(email: widget.email),
                                        ),
                                      );
                                    }
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isFormValid ? const Color(0xFF20C8FF) : Colors.grey,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'SAVE',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaticField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: TextField(
            controller: controller,
            enabled: false,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}
