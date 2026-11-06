import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/material_model.dart';
import 'course_service.dart';
import 'persistence_service.dart';

/// The three rotating placeholder categories.
enum PlaceholderCategory {
  unitCode,
  lecturerName,
  unitName,
}

/// A non-repeating shuffle-bag for a single category.
class CategoryBag {
  final PlaceholderCategory category;
  List<String> pool;
  int currentIndex;
  String? lastDisplayed;

  CategoryBag({
    required this.category,
    List<String>? pool,
    this.currentIndex = 0,
    this.lastDisplayed,
  }) : pool = pool != null ? List<String>.from(pool) : [];

  Map<String, dynamic> toJson() => {
        'category': category.name,
        'pool': pool,
        'currentIndex': currentIndex,
        'lastDisplayed': lastDisplayed,
      };

  factory CategoryBag.fromJson(Map<String, dynamic> json, PlaceholderCategory category) {
    return CategoryBag(
      category: category,
      pool: (json['pool'] as List?)?.map((e) => e.toString()).toList() ?? [],
      currentIndex: (json['currentIndex'] as num?)?.toInt() ?? 0,
      lastDisplayed: json['lastDisplayed'] as String?,
    );
  }

  /// Reconciles bag with freshly extracted values from the dataset.
  /// Preserves the progress of existing entries, incorporates new entries into unseen portion,
  /// and safely handles removals without index out-of-bounds.
  void reconcileWithValues(List<String> validValues, Random random) {
    if (validValues.isEmpty) {
      pool.clear();
      currentIndex = 0;
      lastDisplayed = null;
      return;
    }

    final validSetLower = validValues.map((v) => v.toLowerCase()).toSet();
    final valueMapByLower = {for (var v in validValues) v.toLowerCase(): v};

    // 1. Filter out deleted entries from pool, tracking shifts in currentIndex
    final newPool = <String>[];
    int adjustedIndex = 0;

    for (int i = 0; i < pool.length; i++) {
      final item = pool[i];
      final itemLower = item.toLowerCase();
      if (validSetLower.contains(itemLower)) {
        // Keep authoritative casing
        newPool.add(valueMapByLower[itemLower] ?? item);
        if (i < currentIndex) {
          adjustedIndex++;
        }
      }
    }

    // 2. Identify newly added values not yet present in the pool
    final existingPoolLower = newPool.map((v) => v.toLowerCase()).toSet();
    final newlyAdded = validValues.where((v) => !existingPoolLower.contains(v.toLowerCase())).toList();

    if (newlyAdded.isNotEmpty) {
      newlyAdded.shuffle(random);
      // Append newly added to the unseen portion of the cycle
      newPool.addAll(newlyAdded);
    }

    pool = newPool;
    currentIndex = adjustedIndex.clamp(0, pool.length);

    // If bag was newly populated, shuffle initial order
    if (pool.isNotEmpty && currentIndex == 0 && newlyAdded.length == pool.length) {
      pool.shuffle(random);
    }
  }

  /// Fetches the next item in the bag cycle, refilling and shuffling when exhausted.
  /// Prevents immediate repetition across cycle boundaries when alternatives exist.
  String? getNextItem(Random random) {
    if (pool.isEmpty) return null;

    // Cycle exhausted: start a new shuffled cycle
    if (currentIndex >= pool.length) {
      pool.shuffle(random);

      // Boundary repeat prevention:
      // If pool has multiple items and first item equals lastDisplayed, swap pool[0] with another item
      if (pool.length > 1 &&
          lastDisplayed != null &&
          pool[0].toLowerCase() == lastDisplayed!.toLowerCase()) {
        final swapIndex = pool.length == 2 ? 1 : (1 + random.nextInt(pool.length - 1));
        final temp = pool[0];
        pool[0] = pool[swapIndex];
        pool[swapIndex] = temp;
      }

      currentIndex = 0;
    }

    final item = pool[currentIndex];
    lastDisplayed = item;
    currentIndex++;
    return item;
  }
}

/// Extracts, cleans, normalizes, and deduplicates fields from resources and curriculum.
class SearchPlaceholderExtractor {
  static const Set<String> genericPlaceholders = {
    'unknown',
    'n/a',
    'na',
    'null',
    'none',
    '-',
    '--',
    '---',
    'tba',
    'tbd',
    'general',
    'other',
    'undefined',
    'not specified',
    'nil',
  };

  static String normalizeWhitespace(String text) {
    return text.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool isMeaningful(String text) {
    final normalized = normalizeWhitespace(text);
    if (normalized.length < 2) return false;
    if (genericPlaceholders.contains(normalized.toLowerCase())) return false;
    // Must contain at least one alphanumeric character
    if (!RegExp(r'[a-zA-Z0-9]').hasMatch(normalized)) return false;
    return true;
  }

  /// Deduplicates items case-insensitively while preserving preferred display capitalization.
  static List<String> cleanAndDeduplicate(Iterable<String> rawItems) {
    final Map<String, String> map = {};

    for (final raw in rawItems) {
      if (!isMeaningful(raw)) continue;
      final normalized = normalizeWhitespace(raw);
      final key = normalized.toLowerCase();

      if (!map.containsKey(key)) {
        map[key] = normalized;
      } else {
        // Prefer variant with more uppercase letters (e.g. "MATH 121" over "math 121")
        final existing = map[key]!;
        final existingUpper = existing.replaceAll(RegExp(r'[^A-Z]'), '').length;
        final currentUpper = normalized.replaceAll(RegExp(r'[^A-Z]'), '').length;
        if (currentUpper > existingUpper) {
          map[key] = normalized;
        }
      }
    }

    return map.values.toList();
  }

  static List<String> extractUnitCodes(List<Resource> resources, [List<CourseUnit>? courseUnits]) {
    final raw = <String>[];
    for (final r in resources) {
      if (r.unitCode.isNotEmpty) raw.add(r.unitCode);
    }
    if (courseUnits != null) {
      for (final u in courseUnits) {
        if (u.unitCode.isNotEmpty) raw.add(u.unitCode);
      }
    }
    return cleanAndDeduplicate(raw);
  }

  static List<String> extractLecturers(List<Resource> resources, [List<CourseUnit>? courseUnits]) {
    final raw = <String>[];
    for (final r in resources) {
      for (final l in r.lecturers) {
        if (l.isNotEmpty) raw.add(l);
      }
    }
    if (courseUnits != null) {
      for (final u in courseUnits) {
        if (u.lecturerName.isNotEmpty) raw.add(u.lecturerName);
      }
    }
    return cleanAndDeduplicate(raw);
  }

  static List<String> extractUnitNames(List<Resource> resources, [List<CourseUnit>? courseUnits]) {
    final raw = <String>[];
    for (final r in resources) {
      if (r.unitName.isNotEmpty) raw.add(r.unitName);
    }
    if (courseUnits != null) {
      for (final u in courseUnits) {
        if (u.unitName.isNotEmpty) raw.add(u.unitName);
      }
    }
    return cleanAndDeduplicate(raw);
  }
}

/// Service managing the three-category rotation state and local persistence.
class SearchPlaceholderService {
  static final SearchPlaceholderService _instance = SearchPlaceholderService._internal();
  factory SearchPlaceholderService() => _instance;
  SearchPlaceholderService._internal();

  static const String persistenceKey = 'search_placeholder_rotation_state_v1';
  static const String permanentPrefix = 'Search ';
  static const String defaultStaticHint = 'Search materials...';

  Random _random = Random();
  @visibleForTesting
  void setRandom(Random random) {
    _random = random;
  }

  int _currentCategoryIndex = 0;
  int get currentCategoryIndex => _currentCategoryIndex;

  @visibleForTesting
  void setCurrentCategoryIndex(int index) {
    _currentCategoryIndex = index % 3;
  }

  final Map<PlaceholderCategory, CategoryBag> _bags = {
    PlaceholderCategory.unitCode: CategoryBag(category: PlaceholderCategory.unitCode),
    PlaceholderCategory.lecturerName: CategoryBag(category: PlaceholderCategory.lecturerName),
    PlaceholderCategory.unitName: CategoryBag(category: PlaceholderCategory.unitName),
  };

  Map<PlaceholderCategory, CategoryBag> get bags => _bags;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Loads persisted rotation state from local storage.
  Future<void> init({Map<String, dynamic>? customJson}) async {
    await loadPersistedState(customJson: customJson);
    _isInitialized = true;
  }

  Future<void> loadPersistedState({Map<String, dynamic>? customJson}) async {
    try {
      final json = customJson ??
          (PersistenceService().isInitialized
              ? PersistenceService().getJson(persistenceKey)
              : null);
      if (json != null && json is Map<String, dynamic>) {
        _currentCategoryIndex = (json['categoryIndex'] as num?)?.toInt() ?? 0;
        final catsJson = json['categories'] as Map<String, dynamic>?;
        if (catsJson != null) {
          for (final cat in PlaceholderCategory.values) {
            final catData = catsJson[cat.name];
            if (catData != null && catData is Map<String, dynamic>) {
              _bags[cat] = CategoryBag.fromJson(catData, cat);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('SearchPlaceholderService: Failed to restore state: $e');
    }
  }

  /// Persists current rotation state to SharedPreferences.
  Future<void> saveState({Function(Map<String, dynamic> data)? onPersist}) async {
    try {
      final data = {
        'categoryIndex': _currentCategoryIndex,
        'categories': {
          for (final entry in _bags.entries) entry.key.name: entry.value.toJson(),
        },
      };

      if (onPersist != null) {
        onPersist(data);
      }

      if (PersistenceService().isInitialized) {
        await PersistenceService().setJson(persistenceKey, data);
      }
    } catch (e) {
      debugPrint('SearchPlaceholderService: Failed to save state: $e');
    }
  }

  /// Ingests updated resources and reconciles pools.
  void syncWithResources(List<Resource> resources, [List<CourseUnit>? courseUnits]) {
    final unitCodes = SearchPlaceholderExtractor.extractUnitCodes(resources, courseUnits);
    final lecturers = SearchPlaceholderExtractor.extractLecturers(resources, courseUnits);
    final unitNames = SearchPlaceholderExtractor.extractUnitNames(resources, courseUnits);

    _bags[PlaceholderCategory.unitCode]!.reconcileWithValues(unitCodes, _random);
    _bags[PlaceholderCategory.lecturerName]!.reconcileWithValues(lecturers, _random);
    _bags[PlaceholderCategory.unitName]!.reconcileWithValues(unitNames, _random);
  }

  /// Fetches the next phrase according to rotation rule:
  /// UNIT CODE -> LECTURER NAME -> UNIT NAME -> UNIT CODE...
  /// Returns the raw phrase (e.g. "MATH 121") or null if all empty.
  String? getNextPhrase({Function(Map<String, dynamic> data)? onPersist}) {
    final categories = [
      PlaceholderCategory.unitCode,
      PlaceholderCategory.lecturerName,
      PlaceholderCategory.unitName,
    ];

    // Try up to 3 attempts to find a non-empty category
    for (int i = 0; i < categories.length; i++) {
      final cat = categories[_currentCategoryIndex];
      _currentCategoryIndex = (_currentCategoryIndex + 1) % categories.length;

      final item = _bags[cat]!.getNextItem(_random);
      if (item != null) {
        // Save state at meaningful phrase transitions
        saveState(onPersist: onPersist);
        return item;
      }
    }

    return null;
  }

  @visibleForTesting
  void reset() {
    _currentCategoryIndex = 0;
    _bags[PlaceholderCategory.unitCode] = CategoryBag(category: PlaceholderCategory.unitCode);
    _bags[PlaceholderCategory.lecturerName] = CategoryBag(category: PlaceholderCategory.lecturerName);
    _bags[PlaceholderCategory.unitName] = CategoryBag(category: PlaceholderCategory.unitName);
  }
}

enum TypewriterPhase {
  idle,
  typing,
  holding,
  deleting,
}

/// Lifecycle-safe controller driving character-by-character typewriter animation.
class TypewriterPlaceholderController {
  final SearchPlaceholderService service;
  final ValueNotifier<String> textNotifier =
      ValueNotifier<String>(SearchPlaceholderService.defaultStaticHint);

  Timer? _tickTimer;
  bool _isDisposed = false;
  bool _isPaused = false;
  String _currentFullBody = '';
  int _charIndex = 0;
  TypewriterPhase _phase = TypewriterPhase.idle;

  TypewriterPhase get phase => _phase;
  String get currentFullBody => _currentFullBody;
  int get charIndex => _charIndex;
  bool get isPaused => _isPaused;

  TypewriterPlaceholderController({SearchPlaceholderService? service})
      : service = service ?? SearchPlaceholderService();

  /// Starts or resumes the animation loop.
  void start() {
    if (_isDisposed) return;
    if (_phase == TypewriterPhase.idle) {
      _advanceToNextPhrase();
    }
  }

  /// Pauses the animation immediately (e.g. when search field gains focus).
  void pause() {
    _isPaused = true;
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  /// Resumes the animation (e.g. when search field loses focus and text is empty).
  void resume() {
    if (_isDisposed || !_isPaused) return;
    _isPaused = false;
    _scheduleNextTick();
  }

  /// Advances to the next phrase in the rotation.
  void _advanceToNextPhrase() {
    if (_isDisposed || _isPaused) return;

    final rawItem = service.getNextPhrase();
    if (rawItem == null) {
      textNotifier.value = SearchPlaceholderService.defaultStaticHint;
      _phase = TypewriterPhase.idle;
      // Recheck later in case resources load
      _tickTimer?.cancel();
      _tickTimer = Timer(const Duration(seconds: 2), _advanceToNextPhrase);
      return;
    }

    _currentFullBody = '$rawItem...';
    _charIndex = 0;
    _phase = TypewriterPhase.typing;
    textNotifier.value = SearchPlaceholderService.permanentPrefix;

    final delay = getTypingCharDurationMs(_currentFullBody.length);
    _tickTimer?.cancel();
    _tickTimer = Timer(Duration(milliseconds: delay), _onTick);
  }

  void _onTick() {
    if (_isDisposed || _isPaused) return;

    switch (_phase) {
      case TypewriterPhase.typing:
        _charIndex++;
        final typed = _currentFullBody.substring(0, _charIndex);
        textNotifier.value = '${SearchPlaceholderService.permanentPrefix}$typed';

        if (_charIndex < _currentFullBody.length) {
          final delay = getTypingCharDurationMs(_currentFullBody.length);
          _tickTimer = Timer(Duration(milliseconds: delay), _onTick);
        } else {
          // Finished typing: enter hold phase
          _phase = TypewriterPhase.holding;
          final hold = getHoldDurationMs(_currentFullBody.length);
          _tickTimer = Timer(Duration(milliseconds: hold), _onTick);
        }
        break;

      case TypewriterPhase.holding:
        // Hold complete: enter deleting phase
        _phase = TypewriterPhase.deleting;
        final delay = getDeletingCharDurationMs(_currentFullBody.length);
        _tickTimer = Timer(Duration(milliseconds: delay), _onTick);
        break;

      case TypewriterPhase.deleting:
        _charIndex--;
        if (_charIndex > 0) {
          final typed = _currentFullBody.substring(0, _charIndex);
          textNotifier.value = '${SearchPlaceholderService.permanentPrefix}$typed';
          final delay = getDeletingCharDurationMs(_currentFullBody.length);
          _tickTimer = Timer(Duration(milliseconds: delay), _onTick);
        } else {
          // Deleted back to permanent prefix
          textNotifier.value = SearchPlaceholderService.permanentPrefix;
          _phase = TypewriterPhase.idle;
          // Brief pause before next phrase
          _tickTimer = Timer(const Duration(milliseconds: 250), _advanceToNextPhrase);
        }
        break;

      case TypewriterPhase.idle:
        _advanceToNextPhrase();
        break;
    }
  }

  void _scheduleNextTick() {
    if (_isDisposed || _isPaused) return;

    switch (_phase) {
      case TypewriterPhase.typing:
        final delay = getTypingCharDurationMs(_currentFullBody.length);
        _tickTimer = Timer(Duration(milliseconds: delay), _onTick);
        break;
      case TypewriterPhase.holding:
        final hold = getHoldDurationMs(_currentFullBody.length);
        _tickTimer = Timer(Duration(milliseconds: hold), _onTick);
        break;
      case TypewriterPhase.deleting:
        final delay = getDeletingCharDurationMs(_currentFullBody.length);
        _tickTimer = Timer(Duration(milliseconds: delay), _onTick);
        break;
      case TypewriterPhase.idle:
        _advanceToNextPhrase();
        break;
    }
  }

  /// Variable typing timing: 100–120ms per character with sensible bounds.
  static int getTypingCharDurationMs(int phraseLength) {
    if (phraseLength <= 10) return 120;
    if (phraseLength <= 20) return 110;
    return 100;
  }

  /// Variable hold timing: 1,500–2,000ms with sensible bounds.
  static int getHoldDurationMs(int phraseLength) {
    return (1500 + phraseLength * 20).clamp(1500, 2000);
  }

  /// Variable deleting timing: 50–70ms per character with sensible bounds.
  static int getDeletingCharDurationMs(int phraseLength) {
    if (phraseLength <= 10) return 70;
    if (phraseLength <= 20) return 60;
    return 50;
  }

  /// Disposes controller and cancels active timers.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _tickTimer?.cancel();
    _tickTimer = null;
    textNotifier.dispose();
  }
}
