class CourseService {
  // Mock data for Course Name <-> Code mapping
  final Map<String, String> _courseMap = {
    'Digital Electronics': 'COMP 212',
    'Data Structures & Algorithms': 'COMP 211',
    'Computer Architecture': 'COMP 221',
    'Database Systems': 'COMP 222',
    'Calculus I': 'MATH 111',
    'Calculus II': 'MATH 122',
    'Discrete Mathematics': 'MATH 211',
    'Linear Algebra I': 'MATH 121',
    'Linear Algebra II': 'MATH 221',
    'Operating Systems': 'COMP 311',
    'Software Engineering': 'COMP 321',
    'Physics I': 'PHYS 111',
    'Physics II': 'PHYS 122',
  };

  // Reverse mapping for easy lookup
  late final Map<String, String> _codeMap;

  CourseService() {
    _codeMap = _courseMap.map((key, value) => MapEntry(value, key));
  }

  String? getCodeByName(String name) => _courseMap[name];
  String? getNameByCode(String code) => _codeMap[code];

  List<String> get courseNames => _courseMap.keys.toList();
  List<String> get courseCodes => _courseMap.values.toList();

  // Mock programs list
  final List<String> programsList = [
    'BSc. Computer Science',
    'BSc. Software Engineering',
    'BSc. Information Technology',
    'BSc. Mathematics',
    'BSc. Statistics',
    'BSc. Physics',
    'BSc. Electrical Engineering',
    'BSc. Civil Engineering',
    'Bachelor of Commerce',
    'Bachelor of Economics',
  ];
}
