import 'package:cloud_firestore/cloud_firestore.dart';

class CurriculumRecord {
  final String id;
  final String programCode;
  final String programName;
  final String unitCode;
  final String unitName;
  final String yearOfStudy;
  final String semester;
  final String lecturerName;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? updatedBy;

  CurriculumRecord({
    required this.id,
    required this.programCode,
    required this.programName,
    required this.unitCode,
    required this.unitName,
    required this.yearOfStudy,
    required this.semester,
    this.lecturerName = '',
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.updatedBy,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Canonical deterministic document ID generator based on curriculum uniqueness
  /// (Program Code + Unit Code + Year + Semester).
  static String generateId({
    required String programCode,
    required String unitCode,
    required String yearOfStudy,
    required String semester,
  }) {
    String clean(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    
    // Normalize year: '1st Year' -> '1', 'Year 2' -> '2', '3' -> '3'
    String normYear(String y) {
      final m = RegExp(r'\d+').firstMatch(y);
      return m != null ? m.group(0)! : clean(y);
    }

    // Normalize semester: 'Semester 1' -> '1', 'Sem 2' -> '2', '1' -> '1'
    String normSem(String s) {
      final m = RegExp(r'\d+').firstMatch(s);
      return m != null ? m.group(0)! : clean(s);
    }

    final p = clean(programCode);
    final u = clean(unitCode);
    final y = normYear(yearOfStudy);
    final s = normSem(semester);

    return '${p}_${u}_y${y}_s$s';
  }

  /// Critical rule: A record can ONLY be activated if all required core fields are populated.
  bool get isValidForActivation {
    return programCode.trim().isNotEmpty &&
        programName.trim().isNotEmpty &&
        unitCode.trim().isNotEmpty &&
        unitName.trim().isNotEmpty &&
        yearOfStudy.trim().isNotEmpty &&
        semester.trim().isNotEmpty;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'programCode': programCode.trim(),
      'programName': programName.trim(),
      'unitCode': unitCode.trim(),
      'unitName': unitName.trim(),
      'yearOfStudy': yearOfStudy.trim(),
      'semester': semester.trim(),
      'lecturerName': lecturerName.trim(),
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      if (updatedBy != null && updatedBy!.trim().isNotEmpty) 'updatedBy': updatedBy!.trim(),
    };
  }

  factory CurriculumRecord.fromMap(Map<String, dynamic> map, [String? docId]) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    final pCode = (map['programCode'] ?? map['Program Code'] ?? map['program Code'] ?? '').toString();
    final uCode = (map['unitCode'] ?? map['Unit Code'] ?? map['unit Code'] ?? '').toString();
    final yStudy = (map['yearOfStudy'] ?? map['Year of Study'] ?? map['Year of study'] ?? map['year of Study'] ?? '').toString();
    final sem = (map['semester'] ?? map['Semester'] ?? '').toString();

    final computedId = docId ?? (map['id'] as String?) ?? generateId(
      programCode: pCode,
      unitCode: uCode,
      yearOfStudy: yStudy,
      semester: sem,
    );

    return CurriculumRecord(
      id: computedId,
      programCode: pCode,
      programName: (map['programName'] ?? map['Program Name'] ?? map['program Name'] ?? '').toString(),
      unitCode: uCode,
      unitName: (map['unitName'] ?? map['Unit Name'] ?? map['unit Name'] ?? '').toString(),
      yearOfStudy: yStudy,
      semester: sem,
      lecturerName: (map['lecturerName'] ?? map["Lecturer's Name"] ?? map["lecturer's Name"] ?? '').toString(),
      isActive: map['isActive'] == null ? true : (map['isActive'] == true),
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
      updatedBy: map['updatedBy'] as String?,
    );
  }

  CurriculumRecord copyWith({
    String? id,
    String? programCode,
    String? programName,
    String? unitCode,
    String? unitName,
    String? yearOfStudy,
    String? semester,
    String? lecturerName,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return CurriculumRecord(
      id: id ?? this.id,
      programCode: programCode ?? this.programCode,
      programName: programName ?? this.programName,
      unitCode: unitCode ?? this.unitCode,
      unitName: unitName ?? this.unitName,
      yearOfStudy: yearOfStudy ?? this.yearOfStudy,
      semester: semester ?? this.semester,
      lecturerName: lecturerName ?? this.lecturerName,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}
