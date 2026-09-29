import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/curriculum_model.dart';

// Riverpod Provider is now consolidated in lib/providers/service_providers.dart

class CourseUnit {
  final String id;
  final String unitName;
  final String unitCode;
  final String programCode;
  final String programName;
  final String yearOfStudy;
  final String semester;
  final String lecturerName;
  final bool isActive;

  CourseUnit({
    this.id = '',
    required this.unitName,
    required this.unitCode,
    required this.programCode,
    required this.programName,
    required this.yearOfStudy,
    required this.semester,
    required this.lecturerName,
    this.isActive = true,
  });

  factory CourseUnit.fromJson(Map<String, dynamic> json, [String? id]) {
    return CourseUnit(
      id: id ?? (json['id'] as String? ?? ''),
      unitName: json['Unit Name'] ?? json['unit Name'] ?? json['unitName'] ?? '',
      unitCode: json['Unit Code'] ?? json['unit Code'] ?? json['unitCode'] ?? '',
      programCode: json['Program Code'] ?? json['program Code'] ?? json['programCode'] ?? '',
      programName: json['Program Name'] ?? json['program Name'] ?? json['programName'] ?? '',
      yearOfStudy: json['Year of Study'] ?? json['Year of study'] ?? json['year of Study'] ?? json['yearOfStudy'] ?? '',
      semester: json['Semester'] ?? json['semester'] ?? '',
      lecturerName: json["Lecturer's Name"] ?? json["lecturer's Name"] ?? json['lecturerName'] ?? '',
      isActive: json['isActive'] == null ? true : (json['isActive'] == true),
    );
  }

  factory CourseUnit.fromCurriculumRecord(CurriculumRecord record) {
    return CourseUnit(
      id: record.id,
      unitName: record.unitName,
      unitCode: record.unitCode,
      programCode: record.programCode,
      programName: record.programName,
      yearOfStudy: record.yearOfStudy,
      semester: record.semester,
      lecturerName: record.lecturerName,
      isActive: record.isActive,
    );
  }
}

class University {
  final String name;
  final String location;
  final String type;

  University({required this.name, required this.location, required this.type});

  factory University.fromJson(Map<String, dynamic> json) {
    return University(
      name: json['name'] ?? '',
      location: json['location'] ?? '',
      type: json['type'] ?? '',
    );
  }
}

class CourseService {
  static final CourseService _instance = CourseService._internal();
  factory CourseService() => _instance;
  CourseService._internal();

  List<CourseUnit> _allUnits = [];
  List<University> _allUniversities = [];
  final Map<String, String> _courseMap = {}; // Name -> Code
  final Map<String, String> _codeMap = {}; // Code -> Name
  final Map<String, String> _programCodeMap = {}; // Program Name -> Program Code
  final Map<String, String> _reverseProgramCodeMap = {}; // Program Code -> Program Name

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  @visibleForTesting
  void clearForTesting() {
    _allUnits.clear();
    _courseMap.clear();
    _codeMap.clear();
    _programCodeMap.clear();
    _reverseProgramCodeMap.clear();
    _isInitialized = false;
  }

  void syncFromCurriculumRecords(List<CurriculumRecord> records) {
    _allUnits = records.map((r) => CourseUnit.fromCurriculumRecord(r)).toList();
    _rebuildMaps();
  }

  void _rebuildMaps() {
    _courseMap.clear();
    _codeMap.clear();
    _programCodeMap.clear();
    _reverseProgramCodeMap.clear();

    for (var unit in _allUnits) {
      if (!unit.isActive || unit.unitName.isEmpty) continue; // ONLY active units!

      _courseMap[unit.unitName] = unit.unitCode;
      
      final codes = _parseCodes(unit.unitCode);
      for (var code in codes) {
        _codeMap[code] = unit.unitName;
      }
      _codeMap[unit.unitCode] = unit.unitName;

      if (unit.programName.isNotEmpty) {
        _programCodeMap[unit.programName] = unit.programCode;
        _reverseProgramCodeMap[unit.programCode] = unit.programName;
      }
    }
  }

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // Load Programs and Units from bundled fallback if not already populated
      if (_allUnits.isEmpty) {
        final String response = await rootBundle.loadString('assets/lessons.json');
        final List<dynamic> data = json.decode(response);
        _allUnits = data.map((json) => CourseUnit.fromJson(json)).toList();
        _rebuildMaps();
      }

      // Load Universities
      final String univResponse = await rootBundle.loadString('assets/universities.json');
      final List<dynamic> univData = json.decode(univResponse);
      _allUniversities = univData.map((json) => University.fromJson(json)).toList();

      _isInitialized = true;
    } catch (e) {
      debugPrint('Error loading course data: $e');
    }
  }

  List<String> _parseCodes(String unitCode) {
    final results = <String>[];
    final parts = unitCode.split('/');
    
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i].trim();
      if (RegExp(r'\d').hasMatch(p)) {
        results.add(p);
      } else {
        // Find the next part that has a number
        for (var j = i + 1; j < parts.length; j++) {
          var nextP = parts[j].trim();
          final numberMatch = RegExp(r'(\d+.*)$').firstMatch(nextP);
          if (numberMatch != null) {
            results.add('$p ${numberMatch.group(1)}'.trim());
            break;
          }
        }
      }
    }
    return results;
  }

  String? getCodeByName(String name) => _courseMap[name];
  String? getNameByCode(String code) => _codeMap[code];
  String? getProgramCode(String program) => _programCodeMap[program];
  String? getProgramNameByCode(String code) => _reverseProgramCodeMap[code];

  List<String> get courseNames => _courseMap.keys.toList();
  List<String> get courseCodes {
    final allCodes = <String>{..._codeMap.keys};
    return allCodes.toList();
  }
  List<String> get programCodes => _reverseProgramCodeMap.keys.toList();
  List<String> get programsList => _programCodeMap.keys.toList();
  List<String> get lecturersList {
    return _allUnits
        .where((u) => u.isActive)
        .map((u) => u.lecturerName)
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
  }

  /// Returns only active units.
  List<CourseUnit> get allUnits => _allUnits.where((u) => u.isActive).toList();

  /// Returns raw units including inactive ones (e.g. for inspection).
  List<CourseUnit> get allUnitsIncludingInactive => List.unmodifiable(_allUnits);

  List<CourseUnit> getUnitsByProgram(String programName) {
    return _allUnits.where((u) => u.isActive && u.programName == programName).toList();
  }

  List<CourseUnit> getUnitsByCode(String code) {
    return _allUnits.where((u) => u.isActive && (u.unitCode == code || _parseCodes(u.unitCode).contains(code))).toList();
  }

  List<University> get universities => _allUniversities;
  
  List<String> get universityNames => _allUniversities.map((u) => u.name).toList();
  
  String? getUniversityLocation(String name) {
    try {
      return _allUniversities.firstWhere((u) => u.name == name).location;
    } catch (e) {
      return null;
    }
  }
}
