import 'dart:convert';
import 'package:flutter/services.dart';

class CourseUnit {
  final String unitName;
  final String unitCode;
  final String programCode;
  final String programName;
  final String yearOfStudy;
  final String semester;
  final String lecturerName;

  CourseUnit({
    required this.unitName,
    required this.unitCode,
    required this.programCode,
    required this.programName,
    required this.yearOfStudy,
    required this.semester,
    required this.lecturerName,
  });

  factory CourseUnit.fromJson(Map<String, dynamic> json) {
    return CourseUnit(
      unitName: json['Unit Name'] ?? json['unit Name'] ?? '',
      unitCode: json['Unit Code'] ?? json['unit Code'] ?? '',
      programCode: json['Program Code'] ?? json['program Code'] ?? '',
      programName: json['Program Name'] ?? json['program Name'] ?? '',
      yearOfStudy: json['Year of Study'] ?? json['Year of study'] ?? json['year of Study'] ?? '',
      semester: json['Semester'] ?? json['semester'] ?? '',
      lecturerName: json["Lecturer's Name"] ?? json["lecturer's Name"] ?? '',
    );
  }
}

class CourseService {
  List<CourseUnit> _allUnits = [];
  final Map<String, String> _courseMap = {}; // Name -> Code
  final Map<String, String> _codeMap = {}; // Code -> Name
  final Map<String, String> _programCodeMap = {}; // Program Name -> Program Code
  final Map<String, String> _reverseProgramCodeMap = {}; // Program Code -> Program Name

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      final String response = await rootBundle.loadString('assets/lessons.json');
      final List<dynamic> data = json.decode(response);
      _allUnits = data.map((json) => CourseUnit.fromJson(json)).toList();

      for (var unit in _allUnits) {
        if (unit.unitName.isEmpty) continue;

        // Store primary mapping
        _courseMap[unit.unitName] = unit.unitCode;
        
        // Handle combined codes like "MATH/MAT 121"
        final codes = _parseCodes(unit.unitCode);
        for (var code in codes) {
          _codeMap[code] = unit.unitName;
        }
        // Also map the original full code string
        _codeMap[unit.unitCode] = unit.unitName;

        if (unit.programName.isNotEmpty) {
          _programCodeMap[unit.programName] = unit.programCode;
          _reverseProgramCodeMap[unit.programCode] = unit.programName;
        }
      }

      _isInitialized = true;
    } catch (e) {
      // In a real app, you might want to log this or show an error
      print('Error loading course data: $e');
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
        .map((u) => u.lecturerName)
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
  }

  List<CourseUnit> get allUnits => _allUnits;

  List<CourseUnit> getUnitsByProgram(String programName) {
    return _allUnits.where((u) => u.programName == programName).toList();
  }

  List<CourseUnit> getUnitsByCode(String code) {
    return _allUnits.where((u) => u.unitCode == code || _parseCodes(u.unitCode).contains(code)).toList();
  }
}
