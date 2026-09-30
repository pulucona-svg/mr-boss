import 'package:flutter/material.dart';
import '../constants/legal_constants.dart';
import 'legal_document_screen.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalDocumentScreen(
      title: 'Privacy Policy',
      version: LegalConstants.privacyPolicyVersion,
      effectiveDate: LegalConstants.privacyPolicyEffectiveDate,
      intro: LegalConstants.privacyPolicyIntro,
      sections: LegalConstants.privacyPolicySections,
      acknowledgement: LegalConstants.privacyPolicyAcknowledgement,
    );
  }
}
