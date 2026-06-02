import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/resource_service.dart';
import '../services/download_service.dart';
import '../services/subscription_service.dart';
import '../services/view_service.dart';
import '../services/comment_service.dart';
import '../services/course_service.dart';
import '../services/auth_service.dart';
import '../services/file_service.dart';
import '../services/upload_service.dart';
import 'user_provider.dart';

export 'user_provider.dart' show userProfileProvider, UserProfile;

// Service Providers - Consolidated to a single source of truth
final resourceServiceProvider = ChangeNotifierProvider((ref) => ResourceService());
final downloadServiceProvider = ChangeNotifierProvider((ref) => DownloadService());
final viewServiceProvider = ChangeNotifierProvider((ref) => ViewService());
final commentServiceProvider = ChangeNotifierProvider((ref) => CommentService());
final subscriptionServiceProvider = ChangeNotifierProvider((ref) => SubscriptionService());
final courseServiceProvider = Provider((ref) => CourseService());
final authServiceProvider = Provider((ref) => AuthService());
final fileServiceProvider = Provider((ref) => FileService());
final uploadServiceProvider = Provider((ref) => UploadService());
