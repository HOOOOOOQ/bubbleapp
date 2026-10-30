import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/admin_console_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/business/business_screens.dart';
import '../features/channels/channels_screens.dart';
import '../features/home/home_shell.dart';
import '../features/messaging/business_messaging_screen.dart';
import '../features/messaging/chat_list_screen.dart';
import '../features/messaging/conversation_screen.dart';
import '../features/messaging/new_chat_screen.dart';
import '../features/messaging/search_screen.dart';
import '../features/owner/owner_dashboard_screen.dart';
import '../features/partners/partners_screens.dart';
import '../features/settings/settings_screens.dart';
import '../features/verification/verification_screens.dart';
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
      GoRoute(path: '/admin', builder: (context, state) => const AdminConsoleScreen()),
      GoRoute(path: '/chats/search', builder: (context, state) => const SearchScreen()),
      GoRoute(path: '/chats/new', builder: (context, state) => const NewChatScreen()),
      GoRoute(path: '/chats/new-group', builder: (context, state) => const NewGroupScreen()),
      GoRoute(path: '/chats/:id', builder: (context, state) => ConversationScreen(conversationId: state.pathParameters['id']!)),
      GoRoute(path: '/business/:bid/messaging', builder: (context, state) => BusinessMessagingScreen(businessId: state.pathParameters['bid']!)),
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
