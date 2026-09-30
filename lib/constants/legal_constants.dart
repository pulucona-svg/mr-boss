class LegalSection {
  final String title;
  final String content;

  const LegalSection({
    required this.title,
    required this.content,
  });
}

class LegalConstants {
  LegalConstants._();

  static const String platformName = 'Mirror Digital';
  static const String contactEmail = 'mirrorlaikipia@gmail.com';

  // Terms & Conditions metadata
  static const String termsVersion = '1.0';
  static const String termsEffectiveDate = 'October 1, 2026';

  // Privacy Policy metadata
  static const String privacyPolicyVersion = '1.0';
  static const String privacyPolicyEffectiveDate = 'October 1, 2026';

  // Terms & Conditions content
  static const String termsIntro =
      'These Terms & Conditions ("Terms", "Terms and Conditions" or "Agreement") govern your access to and use of the Mirror Digital mobile application, website, services, features and related platform infrastructure (collectively, the "Platform").\n\n'
      'By creating an account, accessing, browsing or using Mirror Digital, uploading content, downloading or accessing materials, participating in comments or reports, purchasing a package or subscription, or otherwise using the Platform, you acknowledge that you have read, understood and agreed to these Terms and our Privacy Policy.\n\n'
      'If you do not agree with these Terms, you should not create an account or use the Platform.';

  static const List<LegalSection> termsSections = [
    LegalSection(
      title: '1. ABOUT MIRROR DIGITAL',
      content:
          'Mirror Digital is a user- and volunteer-driven educational technology platform designed to facilitate the organization, hosting, discovery, access and sharing of educational materials and related educational information.\n\n'
          'Mirror Digital provides the technological infrastructure through which users and contributors may upload, organize, access and share educational materials with other users.\n\n'
          'Mirror Digital may provide additional services including educational discovery, news and information features, advertising, notifications, moderation, account services, subscriptions, platform support and other digital services.\n\n'
          'Mirror Digital is not a university, examination body, government agency or educational regulator.\n\n'
          'Unless expressly stated otherwise in writing, Mirror Digital is independent and is not owned, operated, sponsored, endorsed or officially affiliated with Laikipia University or any other university, college, school, institution or educational authority.\n\n'
          'References to institutions, courses, programmes, departments, examinations or educational bodies on the Platform do not by themselves establish an official relationship with those institutions.',
    ),
    LegalSection(
      title: '2. ACCEPTANCE OF THESE TERMS',
      content:
          'You agree to comply with:\n'
          '1. these Terms;\n'
          '2. the Mirror Digital Privacy Policy;\n'
          '3. applicable laws and regulations;\n'
          '4. reasonable instructions and policies displayed within the Platform; and\n'
          '5. any additional terms applicable to specific paid features, services or promotions.\n\n'
          'If you use the Platform on behalf of another person or organization, you confirm that you have authority to do so and that both you and the relevant person or organization will comply with these Terms.',
    ),
    LegalSection(
      title: '3. ELIGIBILITY AND USER ACCOUNTS',
      content:
          'You are responsible for providing information that is reasonably accurate, current and not misleading when creating or maintaining your account.\n\n'
          'You must not:\n'
          '• create an account using another person\'s identity;\n'
          '• impersonate another person or institution;\n'
          '• create fraudulent accounts;\n'
          '• provide deliberately false information;\n'
          '• share your account credentials in a manner that compromises account security;\n'
          '• use another person\'s account without authorization;\n'
          '• attempt to circumvent account restrictions or suspensions.\n\n'
          'You are responsible for maintaining the confidentiality of credentials and for activity conducted through your account, except to the extent that applicable law provides otherwise.\n\n'
          'You should notify Mirror Digital promptly if you reasonably believe your account has been compromised.\n\n'
          'Mirror Digital may require additional verification where reasonably necessary to protect users, the Platform or payment systems.',
    ),
    LegalSection(
      title: '4. USER- AND VOLUNTEER-DRIVEN PLATFORM',
      content:
          'Mirror Digital is designed as a user- and volunteer-driven platform.\n\n'
          'A substantial portion of educational materials, comments, contributions, reports and other information may originate from users, contributors or third parties rather than from Mirror Digital itself.\n\n'
          'Accordingly, the existence of material on Mirror Digital does not mean that Mirror Digital:\n'
          '• created the material;\n'
          '• owns the material;\n'
          '• guarantees the material;\n'
          '• independently verified the material;\n'
          '• endorses the material;\n'
          '• guarantees that the material is officially issued by an institution; or\n'
          '• guarantees that the material is suitable for your academic purpose.',
    ),
    LegalSection(
      title: '5. EDUCATIONAL INFORMATION DISCLAIMER',
      content:
          'Mirror Digital provides educational materials and information for general educational and informational purposes.\n\n'
          'Materials may contain:\n'
          '• errors;\n'
          '• omissions;\n'
          '• outdated information;\n'
          '• incorrect answers;\n'
          '• incomplete notes;\n'
          '• unofficial interpretations;\n'
          '• user opinions;\n'
          '• duplicated content;\n'
          '• formatting errors; or\n'
          '• information that has subsequently changed.\n\n'
          'Mirror Digital does not warrant or guarantee that educational content is accurate, complete, current, reliable, suitable for a particular course, or officially approved by an educational institution.\n\n'
          'Users should independently verify important academic information, examination requirements, academic policies, dates, course requirements and other consequential information with the relevant official institution or qualified source.\n\n'
          'Nothing on Mirror Digital constitutes professional, legal, medical, financial or other regulated professional advice.',
    ),
    LegalSection(
      title: '6. USER-UPLOADED MATERIALS',
      content:
          'Mirror Digital allows users and contributors to upload educational materials.\n\n'
          '"User Content" includes, without limitation:\n'
          '• lecture notes;\n'
          '• revision materials;\n'
          '• past papers;\n'
          '• assignments;\n'
          '• summaries;\n'
          '• diagrams;\n'
          '• photographs;\n'
          '• documents;\n'
          '• study guides;\n'
          '• comments;\n'
          '• descriptions;\n'
          '• metadata;\n'
          '• other educational materials; and\n'
          '• other content submitted through the Platform.\n\n'
          'You remain responsible for User Content that you upload.\n\n'
          'By uploading User Content, you represent and warrant that:\n'
          '1. you own the content or have sufficient legal rights, permissions or authorization to upload and share it;\n'
          '2. your upload does not knowingly infringe another person\'s copyright, trademark, privacy, confidentiality or other legal rights;\n'
          '3. you have the authority to grant the licence described below;\n'
          '4. the content does not knowingly contain unlawful material;\n'
          '5. the content does not contain malicious software intended to compromise the Platform or another person; and\n'
          '6. your upload complies with these Terms and applicable law.\n\n'
          'You must not upload material merely because you were able to obtain or download it from another source.\n\n'
          'Public availability of a document, image, article, file or other material does not automatically give you permission to reproduce, upload, distribute or commercially exploit it.',
    ),
    LegalSection(
      title: '7. OWNERSHIP OF USER CONTENT',
      content:
          'Except for the rights granted to Mirror Digital under these Terms, you retain ownership of User Content to the extent that you legally own that content.\n\n'
          'Uploading material to Mirror Digital does not automatically transfer ownership of the material to Mirror Digital.\n\n'
          'However, by uploading User Content, you grant Mirror Digital a non-exclusive, worldwide, royalty-free licence, for the duration reasonably necessary to operate the service and as otherwise permitted by law, to:\n'
          '• receive;\n'
          '• store;\n'
          '• host;\n'
          '• reproduce;\n'
          '• process;\n'
          '• format;\n'
          '• convert;\n'
          '• display;\n'
          '• index;\n'
          '• organize;\n'
          '• distribute;\n'
          '• transmit; and\n'
          '• make the User Content available\n'
          'through Mirror Digital and its technical service providers as reasonably necessary to provide, maintain, secure, improve and administer the Platform.\n\n'
          'This licence does not transfer ownership of your User Content to Mirror Digital.\n\n'
          'Mirror Digital may make technical copies, backups, thumbnails, indexes, previews and other transformations necessary for operating the Platform.',
    ),
    LegalSection(
      title: '8. ACCESS TO MATERIALS UPLOADED BY YOU',
      content:
          'Where the Platform provides users with access to materials they personally uploaded, the uploader may access those materials through their account, subject to:\n'
          '• these Terms;\n'
          '• applicable law;\n'
          '• copyright requirements;\n'
          '• moderation decisions;\n'
          '• security requirements;\n'
          '• account status;\n'
          '• technical availability; and\n'
          '• legitimate removal, restriction or administrative actions.\n\n'
          'Access to your own uploaded material does not create an unconditional guarantee that the material will remain permanently available in every circumstance.\n\n'
          'Mirror Digital may restrict or remove access where reasonably necessary for legal compliance, copyright enforcement, security, fraud prevention, moderation, technical reasons, account termination or protection of the Platform and its users.',
    ),
    LegalSection(
      title: '9. ACCESS TO OTHER USERS\' MATERIALS',
      content:
          'Accessing or downloading another user\'s material does not transfer ownership of that material to you.\n\n'
          'Unless expressly permitted by the rights holder or applicable law, you must not:\n'
          '• claim another person\'s material as your own;\n'
          '• commercially redistribute it;\n'
          '• upload it to another platform;\n'
          '• remove copyright notices;\n'
          '• modify it for deceptive purposes;\n'
          '• sell it independently;\n'
          '• use it to infringe another person\'s rights; or\n'
          '• otherwise exploit it beyond the permission provided through Mirror Digital.',
    ),
    LegalSection(
      title: '10. COPYRIGHT AND INTELLECTUAL PROPERTY COMPLAINTS',
      content:
          'Mirror Digital respects intellectual-property rights.\n\n'
          'If you believe that content available through Mirror Digital infringes your copyright or another legally protected right, contact:\n\n'
          'mirrorlaikipia@gmail.com\n\n'
          'A copyright complaint should provide sufficient information to identify:\n'
          '• the complainant;\n'
          '• the rights claimed;\n'
          '• the relevant work;\n'
          '• the allegedly infringing material;\n'
          '• where the material appears on the Platform;\n'
          '• the basis of the complaint; and\n'
          '• supporting information reasonably required to assess the complaint.\n\n'
          'Where applicable, formal copyright takedown requests will be handled in accordance with applicable Kenyan copyright law.\n\n'
          'Nothing in these Terms limits statutory rights or procedures available to rights holders.\n\n'
          'Where Kenyan statutory takedown procedures apply, Mirror Digital may be required to follow prescribed notice, notification, counter-notice and access-disabling procedures.\n\n'
          'Mirror Digital may remove or restrict access to allegedly infringing content while a complaint is being assessed where reasonably necessary.\n\n'
          'Users who repeatedly upload infringing content may have content removed and may have their accounts restricted, suspended or permanently terminated.',
    ),
    LegalSection(
      title: '11. CONTENT MODERATION',
      content:
          'Mirror Digital may review, moderate, restrict, remove, archive or disable access to User Content where reasonably necessary, including where content:\n'
          '• violates these Terms;\n'
          '• violates applicable law;\n'
          '• is subject to a copyright complaint;\n'
          '• creates a security risk;\n'
          '• contains malicious software;\n'
          '• involves fraud;\n'
          '• threatens users;\n'
          '• contains prohibited abusive conduct;\n'
          '• creates a significant risk to the Platform;\n'
          '• is reported by users;\n'
          '• is required to be removed by a lawful authority; or\n'
          '• otherwise requires intervention to protect the Platform or its users.\n\n'
          'Mirror Digital does not guarantee that every violation will be detected immediately.\n\n'
          'The absence of removal does not constitute approval, endorsement or confirmation that content is lawful.',
    ),
    LegalSection(
      title: '12. COMMUNITY CONDUCT',
      content:
          'You must use Mirror Digital respectfully and lawfully.\n\n'
          'The following conduct is prohibited:\n'
          '• hate speech;\n'
          '• harassment;\n'
          '• bullying;\n'
          '• threats;\n'
          '• intimidation;\n'
          '• discriminatory abuse;\n'
          '• incitement to violence or unlawful conduct;\n'
          '• targeted abuse;\n'
          '• sexual exploitation or abusive sexual content;\n'
          '• non-consensual intimate material;\n'
          '• impersonation;\n'
          '• fraud;\n'
          '• malicious deception;\n'
          '• unlawful content;\n'
          '• deliberate misinformation intended to cause harm;\n'
          '• doxxing or unlawful exposure of personal information;\n'
          '• spam;\n'
          '• abusive reporting;\n'
          '• manipulation of ratings or platform metrics;\n'
          '• attempts to compromise another user\'s account;\n'
          '• attempts to compromise Mirror Digital systems;\n'
          '• distribution of malware;\n'
          '• unauthorized scraping or automated extraction where prohibited;\n'
          '• circumvention of access controls;\n'
          '• bypassing subscription or payment controls;\n'
          '• reverse engineering where prohibited by applicable law;\n'
          '• interference with Platform operation; and\n'
          '• any other conduct prohibited by applicable law.',
    ),
    LegalSection(
      title: '13. REPORTING ABUSIVE CONTENT',
      content:
          'Users should report serious abuse, threats, harassment, bullying, copyright concerns, illegal content and other violations promptly.\n\n'
          'Mirror Digital may investigate reports and take action where appropriate.\n\n'
          'Depending on the circumstances, action may include:\n'
          '• warning;\n'
          '• content removal;\n'
          '• content restriction;\n'
          '• account restriction;\n'
          '• temporary suspension;\n'
          '• permanent termination;\n'
          '• referral to appropriate authorities; or\n'
          '• other measures reasonably necessary to protect users and the Platform.\n\n'
          'Mirror Digital aims to review serious moderation reports as promptly as reasonably practicable and, where operationally feasible, within approximately 48 hours.\n\n'
          'This is an operational target and not a guarantee that every report will be resolved within that period.',
    ),
    LegalSection(
      title: '14. MIRROR DIGITAL\'S INTELLECTUAL PROPERTY',
      content:
          'Except for User Content and third-party material, Mirror Digital and its licensors retain all rights in the Platform and its original components, including where applicable:\n'
          '• Mirror Digital branding;\n'
          '• names and logos;\n'
          '• software;\n'
          '• source code;\n'
          '• interface design;\n'
          '• graphics;\n'
          '• original text;\n'
          '• original articles;\n'
          '• databases and database structures;\n'
          '• platform architecture;\n'
          '• icons;\n'
          '• layouts;\n'
          '• functionality;\n'
          '• original promotional material; and\n'
          '• other proprietary material.\n\n'
          'You may not copy, reproduce, modify, distribute, sell, lease, sublicense or commercially exploit Mirror Digital\'s proprietary material except where expressly permitted.\n\n'
          'Nothing in these Terms grants you ownership of Mirror Digital\'s intellectual property.',
    ),
    LegalSection(
      title: '15. PAID PACKAGES, PASSES AND SUBSCRIPTIONS',
      content:
          'Mirror Digital may offer paid packages, passes, subscriptions or other paid platform features.\n\n'
          'Pricing, duration, benefits and applicable conditions will be displayed before purchase or activation where reasonably practicable.\n\n'
          'Packages may include different durations or access benefits.\n\n'
          'A successful payment does not transfer ownership of any individual educational material.\n\n'
          'Mirror Digital is a platform providing technological and related services.\n\n'
          'Where users pay for packages, passes or subscriptions, the payment is intended to support and pay for platform services and infrastructure, which may include:\n'
          '• hosting;\n'
          '• storage;\n'
          '• servers;\n'
          '• databases;\n'
          '• software development;\n'
          '• platform maintenance;\n'
          '• administration;\n'
          '• moderation;\n'
          '• security;\n'
          '• customer/user support;\n'
          '• technical operations;\n'
          '• payment infrastructure;\n'
          '• notifications;\n'
          '• content management; and\n'
          '• other services necessary to operate and maintain Mirror Digital.\n\n'
          'A payment for a package, pass or subscription should not by itself be interpreted as a purchase of ownership or copyright in a particular user-uploaded educational material.\n\n'
          'Nothing in this section overrides rights or obligations imposed by applicable consumer-protection or other law.',
    ),
    LegalSection(
      title: '16. PAYMENT PROCESSING',
      content:
          'Payments may be processed through third-party payment providers.\n\n'
          'Mirror Digital may receive or retain transaction-related information necessary to:\n'
          '• verify payment;\n'
          '• activate services;\n'
          '• reconcile transactions;\n'
          '• provide support;\n'
          '• detect fraud;\n'
          '• maintain financial records;\n'
          '• resolve disputes; and\n'
          '• comply with legal obligations.\n\n'
          'Mirror Digital does not request or intentionally store payment credentials such as an M-Pesa PIN.\n\n'
          'Payment providers may separately process information under their own terms and privacy policies.\n\n'
          'A package may not activate until Mirror Digital receives appropriate confirmation of successful payment.',
    ),
    LegalSection(
      title: '17. REFUNDS AND PAYMENT DISPUTES',
      content:
          'Unless applicable law requires otherwise, purchases are generally intended to be final once successfully processed and activated.\n\n'
          'Mirror Digital does not ordinarily provide refunds solely because a user:\n'
          '• changes their mind;\n'
          '• selects an unsuitable package;\n'
          '• fails to use the purchased service;\n'
          '• does not like the package;\n'
          '• purchases a package unintentionally where no legal refund right applies; or\n'
          '• does not use all available benefits before expiry.\n\n'
          'However, this does not exclude remedies that cannot lawfully be excluded.\n\n'
          'Mirror Digital may investigate and address cases involving:\n'
          '• duplicate charges;\n'
          '• unauthorized transactions;\n'
          '• technical payment failures;\n'
          '• payments received without corresponding activation;\n'
          '• demonstrable system errors;\n'
          '• fraudulent transactions; or\n'
          '• other circumstances where applicable law requires a remedy.\n\n'
          'Users should report payment problems promptly.',
    ),
    LegalSection(
      title: '18. ADVERTISING',
      content:
          'Mirror Digital may display advertisements from Mirror Digital or third-party advertising providers.\n\n'
          'Advertisements may include:\n'
          '• manually managed advertisements;\n'
          '• banner advertisements;\n'
          '• rewarded advertisements;\n'
          '• sponsored content;\n'
          '• promotional messages; or\n'
          '• other advertising formats.\n\n'
          'The presence of an advertisement does not necessarily constitute endorsement by Mirror Digital.\n\n'
          'Third-party advertisers and advertising providers may operate under separate terms and privacy policies.',
    ),
    LegalSection(
      title: '19. NEWS AND THIRD-PARTY CONTENT',
      content:
          'Mirror Digital may provide news, articles, summaries, links, headlines or other information obtained from third-party sources or generated through permitted systems.\n\n'
          'Third-party content remains subject to the rights and terms of its respective owners.\n\n'
          'Mirror Digital does not claim ownership of third-party copyrighted material merely because it is referenced, linked, summarized or displayed through the Platform.\n\n'
          'Mirror Digital does not guarantee the accuracy, completeness, timeliness or reliability of third-party information.',
    ),
    LegalSection(
      title: '20. THIRD-PARTY SERVICES',
      content:
          'Mirror Digital relies on third-party technology and service providers to operate portions of the Platform.\n\n'
          'These may include infrastructure, authentication, storage, payment, advertising, image, notification, analytics, AI or other service providers.\n\n'
          'Third-party services may experience:\n'
          '• outages;\n'
          '• maintenance;\n'
          '• technical failures;\n'
          '• changes in functionality;\n'
          '• security incidents;\n'
          '• policy changes;\n'
          '• pricing changes; or\n'
          '• termination.\n\n'
          'Mirror Digital is not responsible for failures that are solely attributable to third-party services, subject always to applicable law.\n\n'
          'Your use of third-party services may also be subject to the third party\'s terms and privacy policies.',
    ),
    LegalSection(
      title: '21. SECURITY AND PROHIBITED TECHNICAL ACTIVITY',
      content:
          'You must not attempt to:\n'
          '• gain unauthorized access to Mirror Digital;\n'
          '• access another user\'s account;\n'
          '• access administrative systems without authorization;\n'
          '• bypass authentication;\n'
          '• bypass subscription controls;\n'
          '• interfere with payment verification;\n'
          '• manipulate server-side data;\n'
          '• exploit vulnerabilities for unauthorized purposes;\n'
          '• introduce malware;\n'
          '• conduct denial-of-service attacks;\n'
          '• scrape restricted information;\n'
          '• reverse engineer protected components where prohibited;\n'
          '• interfere with security controls; or\n'
          '• otherwise compromise the Platform.\n\n'
          'Security vulnerabilities should be responsibly reported to Mirror Digital rather than exploited.',
    ),
    LegalSection(
      title: '22. ACCOUNT SUSPENSION AND TERMINATION',
      content:
          'Mirror Digital may suspend, restrict or terminate an account where reasonably necessary, including where a user:\n'
          '• violates these Terms;\n'
          '• repeatedly violates content rules;\n'
          '• infringes copyright;\n'
          '• engages in fraud;\n'
          '• compromises security;\n'
          '• abuses other users;\n'
          '• bypasses payment controls;\n'
          '• engages in unlawful conduct;\n'
          '• creates significant risk to the Platform; or\n'
          '• otherwise materially breaches these Terms.\n\n'
          'Mirror Digital may also suspend or terminate services where required by law or where continued operation would create significant legal, security or operational risk.\n\n'
          'Where reasonably practicable, Mirror Digital may provide notice or an opportunity to address the issue, but immediate action may be taken where necessary to protect users, the Platform, third parties or legal interests.',
    ),
    LegalSection(
      title: '23. ACCOUNT DELETION',
      content:
          'Users may request account deletion through available Platform functionality or by contacting Mirror Digital.\n\n'
          'Deletion may not result in immediate destruction of every record.\n\n'
          'Mirror Digital may retain information where reasonably necessary for:\n'
          '• legal compliance;\n'
          '• fraud prevention;\n'
          '• security;\n'
          '• dispute resolution;\n'
          '• financial records;\n'
          '• copyright enforcement;\n'
          '• audit records;\n'
          '• enforcement of these Terms;\n'
          '• backups; or\n'
          '• other legitimate and lawful purposes.\n\n'
          'Retention will remain subject to applicable data-protection requirements.',
    ),
    LegalSection(
      title: '24. PLATFORM AVAILABILITY',
      content:
          'Mirror Digital aims to provide a reliable service but does not guarantee uninterrupted or error-free availability.\n\n'
          'The Platform may become unavailable due to:\n'
          '• maintenance;\n'
          '• updates;\n'
          '• technical failures;\n'
          '• internet connectivity;\n'
          '• hosting failures;\n'
          '• third-party services;\n'
          '• security incidents;\n'
          '• force majeure events;\n'
          '• payment-provider issues;\n'
          '• telecommunications failures; or\n'
          '• other circumstances outside reasonable control.\n\n'
          'Mirror Digital does not guarantee that User Content will never be lost, corrupted, unavailable or inaccessible.\n\n'
          'Users are responsible for maintaining their own copies of important materials.',
    ),
    LegalSection(
      title: '25. NO WARRANTY',
      content:
          'To the maximum extent permitted by applicable law, Mirror Digital provides the Platform on an "as available" and "as reasonably provided" basis.\n\n'
          'Mirror Digital does not warrant that:\n'
          '• the Platform will always be available;\n'
          '• all content will be accurate;\n'
          '• all content will remain available;\n'
          '• every defect will be corrected immediately;\n'
          '• third-party services will remain available;\n'
          '• educational information will be suitable for every user;\n'
          '• the Platform will be free from every security risk; or\n'
          '• every User Content submission will be reviewed.\n\n'
          'Nothing in these Terms excludes a warranty or legal right that cannot lawfully be excluded.',
    ),
    LegalSection(
      title: '26. LIMITATION OF LIABILITY',
      content:
          'To the maximum extent permitted by applicable law, Mirror Digital, its developer, owner, operators, administrators, employees, contractors and service providers shall not be liable for indirect, incidental, consequential, special or punitive losses arising from or connected with use of the Platform.\n\n'
          'This may include, where legally permissible:\n'
          '• loss of data;\n'
          '• loss of academic opportunity;\n'
          '• loss of profits;\n'
          '• loss of business;\n'
          '• loss of reputation;\n'
          '• service interruption;\n'
          '• reliance on inaccurate educational information;\n'
          '• actions of other users;\n'
          '• User Content;\n'
          '• copyright disputes between users;\n'
          '• third-party service failures;\n'
          '• payment-provider failures;\n'
          '• unauthorized access caused by circumstances outside reasonable control; or\n'
          '• inability to access the Platform.\n\n'
          'Nothing in these Terms excludes or limits liability to the extent that applicable law prohibits such exclusion or limitation.',
    ),
    LegalSection(
      title: '27. INDEMNIFICATION',
      content:
          'To the extent permitted by applicable law, you agree to indemnify and hold harmless Mirror Digital, its owner, developer, operators, administrators, employees and service providers from claims, losses, liabilities, damages, costs and reasonable expenses (including reasonable legal fees) arising from or connected with:\n'
          '• your User Content;\n'
          '• your misuse of the Platform;\n'
          '• your violation of these Terms;\n'
          '• your violation of applicable law; or\n'
          '• your infringement or violation of any rights of another person or entity.',
    ),
    LegalSection(
      title: '28. CHANGES TO THESE TERMS',
      content:
          'We may update these Terms when reasonably necessary because of changes to the Platform, changes in law, security requirements, or other operational reasons.\n\n'
          'The current version will be made available through Mirror Digital.\n\n'
          'Where a material change requires notice under applicable law, Mirror Digital will provide appropriate notice. Continued use of the Platform after changes are posted constitutes acceptance of the modified Terms.',
    ),
    LegalSection(
      title: '29. GOVERNING LAW AND JURISDICTION',
      content:
          'These Terms shall be governed by and construed in accordance with the laws of Kenya.\n\n'
          'Any dispute, controversy or claim arising under or in connection with these Terms or use of the Platform shall be resolved in accordance with applicable Kenyan law.',
    ),
    LegalSection(
      title: '30. QUESTIONS AND CONTACT',
      content:
          'For questions or concerns regarding these Terms & Conditions:\n\n'
          'Mirror Digital\n'
          'Email: mirrorlaikipia@gmail.com',
    ),
  ];

  static const String termsAcknowledgement =
      'By using Mirror Digital, you acknowledge that you have read, understood and agreed to these Terms & Conditions.\n\n'
      'Mirror Digital\n'
      'Terms & Conditions — Version 1.0';

  // Privacy Policy content
  static const String privacyPolicyIntro =
      'Mirror Digital ("we", "our", or "Platform") respects your privacy and is committed to protecting personal information.\n\n'
      'By creating an account, accessing, browsing or using Mirror Digital, you acknowledge that you have read and understood this Privacy Policy.';

  static const List<LegalSection> privacyPolicySections = [
    LegalSection(
      title: '1. ABOUT THIS PRIVACY POLICY',
      content:
          'Mirror Digital ("we", "our", or "Platform") respects your privacy and is committed to protecting personal information. Mirror Digital determines the purposes and means of processing and may use third-party data processors or service providers to provide specific services.\n\n'
          'The contact email for privacy and data-related requests is:\n\n'
          'mirrorlaikipia@gmail.com',
    ),
    LegalSection(
      title: '2. INFORMATION WE MAY COLLECT',
      content:
          'Depending on how you use the Platform, we may collect or process different categories of information.\n\n'
          'We do not necessarily collect every category from every user.',
    ),
    LegalSection(
      title: '3. ACCOUNT INFORMATION',
      content:
          'This may include:\n'
          '• username;\n'
          '• email address;\n'
          '• telephone number;\n'
          '• profile name;\n'
          '• profile photograph;\n'
          '• account identifier;\n'
          '• authentication provider information;\n'
          '• account creation information;\n'
          '• account status;\n'
          '• role or permission information; and\n'
          '• other information necessary to maintain your account.',
    ),
    LegalSection(
      title: '4. ACADEMIC AND PERSONALIZATION INFORMATION',
      content:
          'Where you choose to provide it, Mirror Digital may process information used to personalize educational features, such as:\n'
          '• institution;\n'
          '• programme/course;\n'
          '• programme code;\n'
          '• year of study;\n'
          '• semester;\n'
          '• academic preferences;\n'
          '• curriculum selections; and\n'
          '• related educational preferences.\n\n'
          'This information is used to provide and personalize relevant educational functionality.\n\n'
          'You should avoid providing unnecessary sensitive personal information through academic fields.',
    ),
    LegalSection(
      title: '5. PROFILE PHOTOGRAPHS AND USER-PROVIDED INFORMATION',
      content:
          'If you choose to upload a profile photograph or other personal information, we process it for the purposes associated with your account and the relevant Platform feature.\n\n'
          'You should only upload information that you have the right to provide.\n\n'
          'Profile information may be visible to other users depending on the Platform\'s functionality, account settings and the feature through which it is displayed.',
    ),
    LegalSection(
      title: '6. USER-UPLOADED MATERIALS',
      content:
          'Mirror Digital allows users to upload educational materials.\n\n'
          'Uploaded material may contain personal information depending on what the uploader chooses to submit.\n\n'
          'Users are responsible for reviewing material before uploading it and should not upload unnecessary personal information belonging to themselves or another person.\n\n'
          'Where educational material contains personal information belonging to another person, the uploader is responsible for having the appropriate legal basis or authorization to share it.\n\n'
          'Mirror Digital may process uploaded material to:\n'
          '• store it;\n'
          '• host it;\n'
          '• organize it;\n'
          '• display it;\n'
          '• generate metadata;\n'
          '• generate previews or thumbnails;\n'
          '• provide search and discovery;\n'
          '• facilitate access by permitted users;\n'
          '• moderate content;\n'
          '• investigate reports;\n'
          '• address copyright complaints;\n'
          '• maintain security; and\n'
          '• operate the Platform.',
    ),
    LegalSection(
      title: '7. COMMENTS, REPORTS AND COMMUNITY ACTIVITY',
      content:
          'If you comment on materials, submit a report, interact with moderation systems or otherwise participate in community features, we may process:\n'
          '• your account identifier;\n'
          '• the content of your comment or report;\n'
          '• the material concerned;\n'
          '• timestamps;\n'
          '• moderation information;\n'
          '• administrative actions; and\n'
          '• information necessary to investigate the matter.\n\n'
          'Reports may be reviewed by authorized administrators or personnel where necessary to investigate abuse, copyright complaints, security incidents or violations of Platform rules.',
    ),
    LegalSection(
      title: '8. PAYMENT AND SUBSCRIPTION INFORMATION',
      content:
          'Mirror Digital may provide paid packages, passes or subscriptions.\n\n'
          'When you make a payment, we may process transaction-related information such as:\n'
          '• payment reference;\n'
          '• package purchased;\n'
          '• amount;\n'
          '• currency;\n'
          '• payment status;\n'
          '• transaction date/time;\n'
          '• payment phone number where relevant;\n'
          '• subscription status;\n'
          '• activation and expiry information;\n'
          '• refund/dispute information; and\n'
          '• other information necessary to reconcile or support a transaction.\n\n'
          'Payment providers may separately process payment information under their own privacy policies and terms.\n\n'
          'Mirror Digital does not intentionally request or store your M-Pesa PIN.\n\n'
          'Where card or other sensitive payment credentials are processed by a payment provider, those credentials may be handled directly by the relevant provider rather than by Mirror Digital.',
    ),
    LegalSection(
      title: '9. WHY WE PROCESS PERSONAL INFORMATION',
      content:
          'Depending on the circumstances, Mirror Digital may process personal information to:\n'
          '• create and manage accounts;\n'
          '• authenticate users;\n'
          '• provide educational personalization;\n'
          '• provide requested Platform services;\n'
          '• host and manage user-uploaded materials;\n'
          '• facilitate access to educational content;\n'
          '• process subscriptions and payments;\n'
          '• provide customer support;\n'
          '• respond to complaints;\n'
          '• moderate content;\n'
          '• investigate reports;\n'
          '• address copyright complaints;\n'
          '• prevent fraud;\n'
          '• protect Platform security;\n'
          '• detect abuse;\n'
          '• maintain audit records;\n'
          '• send relevant service notifications;\n'
          '• provide advertising where applicable;\n'
          '• improve Platform functionality;\n'
          '• troubleshoot technical problems;\n'
          '• comply with legal obligations;\n'
          '• respond to lawful requests;\n'
          '• protect the rights and safety of users and Mirror Digital; and\n'
          '• perform other purposes reasonably connected to the services you request.\n\n'
          'We seek to process information for specific and legitimate purposes and avoid collecting information that is unnecessary for those purposes.',
    ),
    LegalSection(
      title: '10. LAWFUL PROCESSING',
      content:
          'Depending on the circumstances and applicable law, processing may be based on grounds such as:\n'
          '• your consent;\n'
          '• performance of a contract or provision of requested services;\n'
          '• compliance with a legal obligation;\n'
          '• protection of vital interests where applicable;\n'
          '• legitimate interests that are not overridden by applicable rights and freedoms; or\n'
          '• another lawful basis recognized by applicable law.\n\n'
          'Where consent is relied upon, you may have rights concerning withdrawal of consent, subject to legal and operational limitations.\n\n'
          'Withdrawal of consent does not necessarily invalidate processing that was lawfully carried out before withdrawal.',
    ),
    LegalSection(
      title: '11. ADMINISTRATIVE ACCESS',
      content:
          'Authorized Mirror Digital administrators may access certain account and Platform information when reasonably necessary for:\n'
          '• account support;\n'
          '• moderation;\n'
          '• security;\n'
          '• fraud investigation;\n'
          '• payment reconciliation;\n'
          '• copyright complaints;\n'
          '• user reports;\n'
          '• troubleshooting;\n'
          '• legal compliance;\n'
          '• enforcement of Platform rules; or\n'
          '• administration of Mirror Digital.\n\n'
          'Administrative access should be limited to authorized personnel and legitimate operational purposes.\n\n'
          'Payment and security information may receive additional access restrictions.',
    ),
    LegalSection(
      title: '12. DEVICE AND TECHNICAL INFORMATION',
      content:
          'Depending on the Platform features and services used, technical information may be collected or processed, including:\n'
          '• device type;\n'
          '• operating-system information;\n'
          '• application version;\n'
          '• technical identifiers;\n'
          'session information;\n'
          '• authentication information;\n'
          '• notification identifiers/tokens;\n'
          '• diagnostic information;\n'
          '• crash information;\n'
          '• security logs;\n'
          '• network-related information; and\n'
          '• other technical information generated when the Platform is used.\n\n'
          'This information may be used for:\n'
          '• security;\n'
          '• authentication;\n'
          '• troubleshooting;\n'
          '• reliability;\n'
          '• fraud prevention;\n'
          '• diagnostics;\n'
          '• notifications;\n'
          '• performance monitoring; and\n'
          '• Platform improvement.',
    ),
    LegalSection(
      title: '13. NOTIFICATIONS',
      content:
          'Mirror Digital may process notification-related information, such as a device notification token, where necessary to deliver:\n'
          '• account notifications;\n'
          '• service notifications;\n'
          '• administrative notices;\n'
          '• moderation notifications;\n'
          '• subscription information;\n'
          '• Platform announcements; or\n'
          '• other notifications you have enabled.\n\n'
          'You may be able to control notifications through your device settings or Platform settings depending on the type of notification.\n\n'
          'Some essential service or security notifications may still be delivered where necessary.',
    ),
    LegalSection(
      title: '14. ADVERTISING',
      content:
          'Mirror Digital may use advertising services, including third-party advertising providers, to display advertisements.\n\n'
          'Advertising providers may process technical information and advertising-related identifiers according to their own policies and applicable law.\n\n'
          'Depending on the configuration of the advertising service, information may be used for:\n'
          '• displaying advertisements;\n'
          '• measuring advertisements;\n'
          '• preventing advertising fraud;\n'
          '• frequency management;\n'
          '• understanding advertising performance; or\n'
          '• personalization where permitted.\n\n'
          'Mirror Digital may also display advertisements that it manages directly.\n\n'
          'The existence of an advertisement does not necessarily mean that Mirror Digital endorses the advertiser.',
    ),
    LegalSection(
      title: '15. SUBSCRIPTIONS AND ADVERTISEMENT-RELATED FEATURES',
      content:
          'Mirror Digital may use subscription status to determine whether certain advertising or rewarded-ad features should be displayed or whether certain paid benefits should be enabled.\n\n'
          'Information concerning package activation, expiry and termination may therefore be processed as part of account and subscription administration.',
    ),
    LegalSection(
      title: '16. THIRD-PARTY SERVICE PROVIDERS',
      content:
          'Mirror Digital may rely on third-party providers to operate portions of the Platform.\n\n'
          'Depending on the services currently enabled, these may include providers for:\n'
          '• cloud infrastructure;\n'
          '• authentication;\n'
          '• databases;\n'
          '• storage;\n'
          '• image processing;\n'
          '• payment processing;\n'
          '• advertising;\n'
          '• notifications;\n'
          '• analytics;\n'
          '• AI-assisted processing;\n'
          '• content/news services; and\n'
          '• other technical services.\n\n'
          'Third-party providers may process information on Mirror Digital\'s behalf or independently according to their applicable terms.\n\n'
          'We seek to use appropriate contractual, technical and organizational safeguards where required.',
    ),
    LegalSection(
      title: '17. FIREBASE AND GOOGLE SERVICES',
      content:
          'Mirror Digital may use Google/Firebase services for functions such as:\n'
          '• authentication;\n'
          '• databases;\n'
          '• cloud functions;\n'
          '• hosting or infrastructure;\n'
          '• storage;\n'
          '• notifications;\n'
          '• security;\n'
          '• application services; and\n'
          '• other Platform functionality.\n\n'
          'Information processed through these services may be subject to the applicable Google/Firebase terms and privacy practices.',
    ),
    LegalSection(
      title: '18. PAYMENT PROVIDERS',
      content:
          'Mirror Digital may use third-party payment providers, including payment infrastructure such as Paystack or M-Pesa-related services where enabled.\n\n'
          'Payment providers may process personal and transaction information required to authorize, complete, verify, secure and reconcile transactions.\n\n'
          'Mirror Digital does not control the independent privacy practices of third-party payment providers.\n\n'
          'Users should review the applicable provider\'s privacy notice where appropriate.',
    ),
    LegalSection(
      title: '19. AI SERVICES',
      content:
          'Mirror Digital may use artificial-intelligence services for specific Platform functions, such as generating or processing content, article-related functionality, image generation or other permitted technical operations.\n\n'
          'Where information is sent to an AI service, the information should be limited to what is reasonably necessary for the relevant function.\n\n'
          'Users should not deliberately upload highly sensitive personal information to an AI-powered feature unless the feature expressly requires it and the user has an appropriate legal basis to provide it.\n\n'
          'AI-generated information may contain errors and should not automatically be treated as verified fact.',
    ),
    LegalSection(
      title: '20. NEWS AND CONTENT SERVICES',
      content:
          'Mirror Digital may use third-party news or content services to support news and information features.\n\n'
          'Where applicable, external services may receive technical requests or public-content queries necessary to provide those features.\n\n'
          'Mirror Digital does not intentionally disclose unrelated private account information to a third-party news provider merely because you use a news feature.',
    ),
    LegalSection(
      title: '21. HOW WE SHARE INFORMATION',
      content:
          'Mirror Digital may disclose or provide access to personal information where reasonably necessary to:\n'
          '• authorized administrators;\n'
          '• service providers;\n'
          '• payment providers;\n'
          '• cloud/infrastructure providers;\n'
          '• advertising providers;\n'
          '• security providers;\n'
          '• AI providers where relevant;\n'
          '• professional advisers;\n'
          '• courts;\n'
          '• regulators;\n'
          '• law-enforcement authorities;\n'
          '• persons entitled to receive information under applicable law; or\n'
          '• other parties where necessary to protect legal rights, safety or the Platform.\n\n'
          'We do not intend to sell personal information merely as a commercial commodity.\n\n'
          'Where disclosure is legally required, we may comply with the applicable legal process.',
    ),
    LegalSection(
      title: '22. COPYRIGHT AND LEGAL COMPLAINTS',
      content:
          'Where necessary to investigate or respond to a valid copyright, legal or safety complaint, Mirror Digital may process and disclose relevant information to the extent permitted or required by applicable law.\n\n'
          'For example, information concerning an uploader may need to be reviewed when responding to a legally valid copyright complaint or counter-notice.\n\n'
          'We seek to limit disclosures to information reasonably necessary for the relevant matter.',
    ),
    LegalSection(
      title: '23. DATA RETENTION',
      content:
          'We retain personal information for as long as reasonably necessary for the purposes for which it was collected, subject to applicable law.\n\n'
          'Retention periods may depend on:\n'
          '• the nature of the information;\n'
          '• whether your account remains active;\n'
          '• legal requirements;\n'
          '• payment and accounting requirements;\n'
          '• dispute resolution;\n'
          '• fraud prevention;\n'
          '• security;\n'
          '• copyright enforcement;\n'
          '• moderation;\n'
          '• audit requirements;\n'
          '• backup systems; and\n'
          '• other legitimate operational requirements.\n\n'
          'When information is no longer required, we may delete it, anonymize it or securely dispose of it, subject to lawful retention requirements.',
    ),
    LegalSection(
      title: '24. ACCOUNT DELETION',
      content:
          'You may request deletion of your Mirror Digital account.\n\n'
          'Where account deletion is available through the Platform, you may use that functionality.\n\n'
          'You may also contact:\n\n'
          'mirrorlaikipia@gmail.com\n\n'
          'Deletion may not immediately remove every record from active or backup systems.\n\n'
          'Some information may need to be retained for lawful reasons, including:\n'
          '• financial records;\n'
          '• fraud prevention;\n'
          '• security;\n'
          '• legal claims;\n'
          '• copyright disputes;\n'
          '• regulatory requirements;\n'
          '• enforcement of Platform rules;\n'
          '• audit records; or\n'
          '• backups.\n\n'
          'Where information is retained, we seek to limit its use to the purposes for which retention is necessary.',
    ),
    LegalSection(
      title: '25. DATA SECURITY',
      content:
          'Mirror Digital uses reasonable technical and organizational measures intended to protect personal information against unauthorized access, loss, misuse, alteration or disclosure.\n\n'
          'Security measures may include:\n'
          '• authentication controls;\n'
          '• access restrictions;\n'
          '• administrative permissions;\n'
          '• server-side security controls;\n'
          '• database rules;\n'
          '• secure transmission where supported;\n'
          '• monitoring;\n'
          '• audit records;\n'
          '• separation of administrative privileges;\n'
          '• secure handling of payment information; and\n'
          '• other appropriate technical and organizational safeguards.\n\n'
          'However, no internet-connected system can be guaranteed to be completely secure.\n\n'
          'Accordingly, Mirror Digital cannot promise absolute security or guarantee that unauthorized persons will never defeat security measures.',
    ),
    LegalSection(
      title: '26. DATA BREACHES AND SECURITY INCIDENTS',
      content:
          'If Mirror Digital becomes aware of a security incident involving personal information, we will assess and respond to the incident in accordance with applicable law and our security procedures.\n\n'
          'Where applicable law requires notification to affected persons or regulatory authorities, Mirror Digital will take appropriate steps within the legally required framework.\n\n'
          'Users should promptly report suspected account compromise or security vulnerabilities.',
    ),
    LegalSection(
      title: '27. INTERNATIONAL OR CROSS-BORDER PROCESSING',
      content:
          'Some service providers used by Mirror Digital may process information outside Kenya.\n\n'
          'Where personal information is transferred or processed outside Kenya, Mirror Digital will seek to comply with applicable legal requirements concerning international or cross-border data transfers, including appropriate safeguards or another lawful basis where required.\n\n'
          'Because third-party infrastructure may change over time, the exact physical location of every processing operation may depend on the providers and services enabled at a particular time.',
    ),
    LegalSection(
      title: '28. YOUR DATA-PROTECTION RIGHTS',
      content:
          'Subject to applicable law and relevant conditions, you may have rights including:\n'
          '• the right to be informed about processing;\n'
          '• the right to access personal information;\n'
          '• the right to request correction of inaccurate information;\n'
          '• the right to request deletion or erasure where applicable;\n'
          '• the right to object to certain processing;\n'
          '• the right to restrict processing where applicable;\n'
          '• the right to data portability where applicable; and\n'
          '• the right to lodge a complaint with the relevant data-protection authority.\n\n'
          'The precise scope of each right may depend on applicable law and the circumstances of the request.',
    ),
    LegalSection(
      title: '29. HOW TO EXERCISE YOUR RIGHTS',
      content:
          'To make a privacy or data-protection request, contact:\n\n'
          'Mirror Digital\n'
          'Email: mirrorlaikipia@gmail.com\n\n'
          'Please provide sufficient information to allow us to understand and process your request.\n\n'
          'We may need to verify your identity before providing access to, correcting or deleting information in order to prevent unauthorized disclosure.\n\n'
          'We will handle valid requests within the timeframes required by applicable law.',
    ),
    LegalSection(
      title: '30. CHILDREN AND MINORS',
      content:
          'Mirror Digital is an educational platform and may be accessible to students of different ages.\n\n'
          'Where a user is a minor, the user should use the Platform only with any parental, guardian or other authorization required by applicable law.\n\n'
          'We do not intentionally seek unnecessary personal information from children.\n\n'
          'Where applicable law imposes additional requirements concerning children\'s personal information, parental/guardian authorization, age verification or processing of children\'s data, Mirror Digital will seek to comply with those requirements.\n\n'
          'Users should not upload another person\'s personal information, especially a child\'s information, unless they have the appropriate legal authority or permission to do so.',
    ),
    LegalSection(
      title: '31. USER RESPONSIBILITY FOR INFORMATION PROVIDED',
      content:
          'You are responsible for ensuring that information you voluntarily provide to Mirror Digital is reasonably accurate and that you have the right to provide it.\n\n'
          'You should not submit:\n'
          '• passwords;\n'
          '• M-Pesa PINs;\n'
          '• payment security codes;\n'
          '• private encryption keys;\n'
          '• authentication secrets;\n'
          '• unnecessary identity documents; or\n'
          '• other highly sensitive information\n'
          'through ordinary Platform features unless specifically requested through a secure and legitimate process.',
    ),
    LegalSection(
      title: '32. DATA ABOUT OTHER PEOPLE',
      content:
          'If you upload, submit or otherwise provide information about another person, you are responsible for ensuring that you have a lawful basis or authorization to provide that information.\n\n'
          'You should not use Mirror Digital to expose another person\'s private information, confidential information or sensitive personal information unlawfully.',
    ),
    LegalSection(
      title: '33. AUTOMATED PROCESSING',
      content:
          'Some Platform functionality may involve automated processing, recommendations, classification, content organization, moderation assistance or AI-assisted processing.\n\n'
          'Where automated systems are used, outputs may contain errors.\n\n'
          'Where applicable law provides rights concerning automated decision-making or profiling, those rights will apply according to the circumstances and legal requirements.',
    ),
    LegalSection(
      title: '34. LINKS TO THIRD-PARTY SERVICES',
      content:
          'The Platform may contain links or integrations to third-party websites and services.\n\n'
          'Mirror Digital does not control the privacy practices of those third parties.\n\n'
          'You should review their privacy policies before providing personal information to them.',
    ),
    LegalSection(
      title: '35. CHANGES TO THIS PRIVACY POLICY',
      content:
          'We may update this Privacy Policy when reasonably necessary because of:\n'
          '• changes to the Platform;\n'
          '• changes in technology;\n'
          '• new services;\n'
          '• changes to third-party providers;\n'
          '• changes in law;\n'
          '• security requirements;\n'
          '• changes in data-processing practices; or\n'
          '• other operational reasons.\n\n'
          'The current version will be made available through Mirror Digital.\n\n'
          'The effective date and version should be displayed so that users can identify the current policy.\n\n'
          'Where a material change requires notice under applicable law, Mirror Digital will provide appropriate notice.',
    ),
    LegalSection(
      title: '36. GOVERNING LAW',
      content:
          'This Privacy Policy is intended to operate subject to the applicable laws of Kenya, including applicable data-protection requirements.\n\n'
          'Nothing in this Privacy Policy removes any mandatory rights or protections available to a data subject under applicable law.',
    ),
    LegalSection(
      title: '37. QUESTIONS, REQUESTS AND COMPLAINTS',
      content:
          'For questions, privacy requests, account-data requests or complaints concerning Mirror Digital\'s processing of personal information:\n\n'
          'Mirror Digital\n'
          'Email: mirrorlaikipia@gmail.com\n\n'
          'If you believe your data-protection rights have not been appropriately addressed, you may also have the right to lodge a complaint with the relevant data-protection authority in accordance with applicable law.',
    ),
  ];

  static const String privacyPolicyAcknowledgement =
      'By using Mirror Digital, you acknowledge that you have been provided access to this Privacy Policy and understand that your personal information may be processed as described above, subject to applicable law.\n\n'
      'Mirror Digital\n'
      'Privacy Policy — Version 1.0';
}
