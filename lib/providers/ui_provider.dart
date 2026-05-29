import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/persistence_service.dart';

class UIState {
  final int mainNavigationIndex;
  final String dashboardCategory;
  final String libraryCategory;
  final String exploreCategory;
  final String dashboardSearch;
  final String librarySearchDownloads;
  final String librarySearchUploads;
  final Map<String, String> dashboardFilters;
  final Map<String, String> libraryFilters;

  UIState({
    this.mainNavigationIndex = 0,
    this.dashboardCategory = 'All',
    this.libraryCategory = 'All',
    this.exploreCategory = 'For You',
    this.dashboardSearch = '',
    this.librarySearchDownloads = '',
    this.librarySearchUploads = '',
    this.dashboardFilters = const {},
    this.libraryFilters = const {},
  });

  UIState copyWith({
    int? mainNavigationIndex,
    String? dashboardCategory,
    String? libraryCategory,
    String? exploreCategory,
    String? dashboardSearch,
    String? librarySearchDownloads,
    String? librarySearchUploads,
    Map<String, String>? dashboardFilters,
    Map<String, String>? libraryFilters,
  }) {
    return UIState(
      mainNavigationIndex: mainNavigationIndex ?? this.mainNavigationIndex,
      dashboardCategory: dashboardCategory ?? this.dashboardCategory,
      libraryCategory: libraryCategory ?? this.libraryCategory,
      exploreCategory: exploreCategory ?? this.exploreCategory,
      dashboardSearch: dashboardSearch ?? this.dashboardSearch,
      librarySearchDownloads: librarySearchDownloads ?? this.librarySearchDownloads,
      librarySearchUploads: librarySearchUploads ?? this.librarySearchUploads,
      dashboardFilters: dashboardFilters ?? this.dashboardFilters,
      libraryFilters: libraryFilters ?? this.libraryFilters,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mainNavigationIndex': mainNavigationIndex,
      'dashboardCategory': dashboardCategory,
      'libraryCategory': libraryCategory,
      'exploreCategory': exploreCategory,
      'dashboardSearch': dashboardSearch,
      'librarySearchDownloads': librarySearchDownloads,
      'librarySearchUploads': librarySearchUploads,
      'dashboardFilters': dashboardFilters,
      'libraryFilters': libraryFilters,
    };
  }

  factory UIState.fromJson(Map<String, dynamic> json) {
    return UIState(
      mainNavigationIndex: json['mainNavigationIndex'] ?? 0,
      dashboardCategory: json['dashboardCategory'] ?? 'All',
      libraryCategory: json['libraryCategory'] ?? 'All',
      exploreCategory: json['exploreCategory'] ?? 'For You',
      dashboardSearch: json['dashboardSearch'] ?? '',
      librarySearchDownloads: json['librarySearchDownloads'] ?? '',
      librarySearchUploads: json['librarySearchUploads'] ?? '',
      dashboardFilters: Map<String, String>.from(json['dashboardFilters'] ?? {}),
      libraryFilters: Map<String, String>.from(json['libraryFilters'] ?? {}),
    );
  }
}

class UIStateNotifier extends StateNotifier<UIState> {
  UIStateNotifier() : super(UIState()) {
    _restoreState();
  }

  void _restoreState() {
    final json = PersistenceService().getJson('ui_state');
    if (json != null) {
      state = UIState.fromJson(json);
    }
  }

  Future<void> _saveState() async {
    await PersistenceService().setJson('ui_state', state.toJson());
  }

  void setMainNavigationIndex(int index) {
    state = state.copyWith(mainNavigationIndex: index);
    _saveState();
  }

  void setDashboardCategory(String category) {
    state = state.copyWith(dashboardCategory: category);
    _saveState();
  }

  void setLibraryCategory(String category) {
    state = state.copyWith(libraryCategory: category);
    _saveState();
  }

  void setExploreCategory(String category) {
    state = state.copyWith(exploreCategory: category);
    _saveState();
  }

  void setDashboardSearch(String search) {
    state = state.copyWith(dashboardSearch: search);
    _saveState();
  }

  void setLibrarySearchDownloads(String search) {
    state = state.copyWith(librarySearchDownloads: search);
    _saveState();
  }

  void setLibrarySearchUploads(String search) {
    state = state.copyWith(librarySearchUploads: search);
    _saveState();
  }

  void setDashboardFilters(Map<String, String> filters) {
    state = state.copyWith(dashboardFilters: filters);
    _saveState();
  }

  void setLibraryFilters(Map<String, String> filters) {
    state = state.copyWith(libraryFilters: filters);
    _saveState();
  }
  
  void resetDashboardUI() {
    state = state.copyWith(
      dashboardSearch: '',
      dashboardFilters: {},
      dashboardCategory: 'All',
    );
    _saveState();
  }

  void resetLibraryUI() {
    state = state.copyWith(
      librarySearchDownloads: '',
      librarySearchUploads: '',
      libraryFilters: {},
      libraryCategory: 'All',
    );
    _saveState();
  }
}

final uiStateProvider = StateNotifierProvider<UIStateNotifier, UIState>((ref) {
  return UIStateNotifier();
});
