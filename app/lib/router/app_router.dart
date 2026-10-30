import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/admin_console_screen.dart';
import '../features/admin/admin_dashboard_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/business/business_screens.dart';
import '../features/calls/screens/active_call_screen.dart';
import '../features/calls/screens/call_history_screen.dart';
import '../features/calls/screens/call_settings_screen.dart';
import '../features/calls/screens/incoming_call_screen.dart';
import '../features/calls/screens/outgoing_call_screen.dart';
import '../features/channels/channels_screens.dart';
import '../features/communities/screens/community_create_screen.dart';
import '../features/communities/screens/community_directory_screen.dart';
import '../features/communities/screens/community_profile_screen.dart';
import '../features/discovery/screens/discovery_screen.dart';
import '../features/feed/screens/create_post_screen.dart';
import '../features/feed/screens/post_detail_screen.dart';
import '../features/feed/screens/social_feed_screen.dart';
import '../features/groups/screens/group_info_screen.dart';
import '../features/home/home_shell.dart';
import '../features/messaging/business_messaging_screen.dart';
import '../features/messaging/chat_list_screen.dart';
import '../features/messaging/conversation_screen.dart';
import '../features/messaging/new_chat_screen.dart';
import '../features/messaging/search_screen.dart';
import '../features/moderation/screens/report_screen.dart';
import '../features/owner/owner_dashboard_screen.dart';
import '../features/owner/admin_management_screen.dart';
import '../features/owner/platform_settings_screen.dart';
import '../features/owner/security_center_screen.dart';
import '../features/owner/audit_log_screen.dart';
import '../features/owner/owner_control_center_screen.dart';
import '../features/moderation/moderation_center_screen.dart';
import '../features/partners/partners_screens.dart';
import '../features/settings/settings_screens.dart';
import '../features/stories/screens/story_editor_screen.dart';
import '../features/stories/screens/story_insights_screen.dart';
import '../features/stories/screens/story_viewer_screen.dart';
import '../features/verification/verification_screens.dart';
import '../models/social.dart';
import '../state/providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final refresh = ref.watch(routerRefreshProvider);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = client.auth.currentSession != null;
      final onSignIn = state.matchedLocation == '/sign-in';
      if (!signedIn && !onSignIn) return '/sign-in';
      if (signedIn && onSignIn) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/sign-in', builder: (context, state) => const SignInScreen()),
      ShellRoute(
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
          GoRoute(path: '/chats', builder: (context, state) => const ChatListScreen()),
          GoRoute(path: '/channels', builder: (context, state) => const ChannelsScreen()),
          GoRoute(path: '/business', builder: (context, state) => const BusinessHomeScreen()),
          GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
        ],
      ),
      GoRoute(path: '/official', builder: (context, state) => const OfficialChannelScreen()),
      GoRoute(path: '/channels/new', builder: (context, state) => const CreateChannelScreen()),
      GoRoute(
        path: '/channels/:id',
        builder: (context, state) => ChannelDetailScreen(channelId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/verification', builder: (context, state) => const VerificationHomeScreen()),
      GoRoute(
        path: '/verification/apply/:type',
        builder: (context, state) => ApplyVerificationScreen(
          applicationType: state.pathParameters['type']!,
          preselectedId: state.uri.queryParameters['id'],
        ),
      ),
      GoRoute(
          path: '/verification/queue',
          builder: (context, state) => const VerificationQueueScreen()),
      GoRoute(path: '/partners', builder: (context, state) => const PartnersScreen()),
      GoRoute(path: '/partners/apply', builder: (context, state) => const PartnerApplyScreen()),
      GoRoute(path: '/partners/queue', builder: (context, state) => const PartnerQueueScreen()),
      GoRoute(path: '/business/new', builder: (context, state) => const CreateBusinessScreen()),
      GoRoute(
        path: '/business/:id',
        builder: (context, state) =>
            BusinessDashboardScreen(businessId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/settings/profile', builder: (context, state) => const ProfileEditScreen()),
      GoRoute(path: '/owner', builder: (context, state) => const OwnerDashboardScreen()),
      GoRoute(path: '/owner/control', builder: (context, state) => const OwnerControlCenterScreen()),
      GoRoute(path: '/owner/admins', builder: (context, state) => const AdminManagementScreen()),
      GoRoute(path: '/owner/settings', builder: (context, state) => const PlatformSettingsScreen()),
      GoRoute(path: '/owner/security', builder: (context, state) => const SecurityCenterScreen()),
      GoRoute(path: '/owner/audit', builder: (context, state) => const AuditLogScreen()),
      GoRoute(path: '/admin/dashboard', builder: (context, state) => const AdminDashboardScreen()),
      GoRoute(path: '/admin', builder: (context, state) => const AdminConsoleScreen()),
      GoRoute(path: '/admin/verification', builder: (context, state) => const VerificationQueueScreen()),
      GoRoute(path: '/admin/partners', builder: (context, state) => const PartnersQueueScreen()),
      GoRoute(path: '/admin/moderation', builder: (context, state) => const ModerationCenterScreen()),
      GoRoute(path: '/admin/announcements', builder: (context, state) => const OfficialChannelScreen()),
      GoRoute(path: '/chats/search', builder: (context, state) => const SearchScreen()),
      GoRoute(path: '/chats/new', builder: (context, state) => const NewChatScreen()),
      GoRoute(path: '/chats/new-group', builder: (context, state) => const NewGroupScreen()),
      GoRoute(path: '/chats/:id', builder: (context, state) => ConversationScreen(conversationId: state.pathParameters['id']!)),
      GoRoute(path: '/business/:bid/messaging', builder: (context, state) => BusinessMessagingScreen(businessId: state.pathParameters['bid']!)),
      GoRoute(path: '/calls/history', builder: (context, state) => const CallHistoryScreen()),
      GoRoute(path: '/calls/settings', builder: (context, state) => const CallSettingsScreen()),
      GoRoute(path: '/calls/incoming/:id', builder: (context, state) => IncomingCallScreen(callId: state.pathParameters['id']!)),
      GoRoute(path: '/calls/outgoing/:id', builder: (context, state) => OutgoingCallScreen(callId: state.pathParameters['id']!)),
      GoRoute(path: '/calls/active/:id', builder: (context, state) => ActiveCallScreen(callId: state.pathParameters['id']!)),
      // Stories
      GoRoute(path: '/stories/create', builder: (context, state) => const StoryEditorScreen()),
      GoRoute(path: '/stories/view/:authorId', builder: (context, state) {
        final stories = state.extra as List<Story>?;
        return StoryViewerScreen(authorId: state.pathParameters['authorId']!, initialStories: stories);
      }),
      GoRoute(path: '/stories/insights/:storyId', builder: (context, state) => StoryInsightsScreen(storyId: state.pathParameters['storyId']!)),
      // Communities
      GoRoute(path: '/communities', builder: (context, state) => const CommunityDirectoryScreen()),
      GoRoute(path: '/communities/new', builder: (context, state) => const CommunityCreateScreen()),
      GoRoute(path: '/communities/:id', builder: (context, state) => CommunityProfileScreen(communityId: state.pathParameters['id']!)),
      // Feed
      GoRoute(path: '/feed', builder: (context, state) => const SocialFeedScreen()),
      GoRoute(path: '/feed/create', builder: (context, state) {
        final communityId = state.extra as String?;
        return CreatePostScreen(communityId: communityId);
      }),
      GoRoute(path: '/feed/:id', builder: (context, state) => PostDetailScreen(postId: state.pathParameters['id']!)),
      GoRoute(path: '/hashtag/:tag', builder: (context, state) => Scaffold(appBar: AppBar(title: Text('#${state.pathParameters['tag']}')), body: Center(child: Text('Posts for #${state.pathParameters['tag']} — uses post_hashtags with RLS')))),
      GoRoute(path: '/discovery', builder: (context, state) => const DiscoveryScreen()),
      GoRoute(path: '/groups/:id/info', builder: (context, state) => GroupInfoScreen(conversationId: state.pathParameters['id']!)),
      GoRoute(path: '/reports/new', builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return ReportScreen(targetType: extra?['type'] as String?, targetId: extra?['id'] as String?);
      }),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(
        child: FilledButton(
          onPressed: () => context.go('/home'),
          child: const Text('Back to home'),
        ),
      ),
    ),
  );
});
