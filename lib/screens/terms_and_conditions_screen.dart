import 'package:flutter/material.dart';
import '../constants/legal_constants.dart';
import 'legal_document_screen.dart';

class TermsAndConditionsScreen extends StatelessWidget {
  const TermsAndConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalDocumentScreen(
      title: 'Terms & Conditions',
      version: LegalConstants.termsVersion,
      effectiveDate: LegalConstants.termsEffectiveDate,
      intro: LegalConstants.termsIntro,
      sections: LegalConstants.termsSections,
      acknowledgement: LegalConstants.termsAcknowledgement,
    );
  }
}
