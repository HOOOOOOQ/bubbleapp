import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/bubble_repository.dart';
import '../models/models.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final repositoryProvider = Provider<BubbleRepository>(
  (ref) => BubbleRepository(ref.watch(supabaseClientProvider)),
);

/// Emits on every Supabase auth change (sign-in, sign-out, token refresh).
final authEventsProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseClientProvider).auth.onAuthStateChange,
);

final sessionProvider = Provider<Session?>((ref) {
  final event = ref.watch(authEventsProvider).valueOrNull;
  if (event != null) return event.session;
  return ref.watch(supabaseClientProvider).auth.currentSession;
});

/// Bridges auth events into a Listenable so GoRouter re-runs its redirects.
final routerRefreshProvider = Provider<ValueNotifier<int>>((ref) {
  final notifier = ValueNotifier<int>(0);
  final sub = ref.watch(supabaseClientProvider).auth.onAuthStateChange.listen((_) {
    notifier.value++;
  });
  ref.onDispose(() {
    sub.cancel();
    notifier.dispose();
  });
  return notifier;
});

final myProfileProvider = FutureProvider<UserProfile?>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).myProfile();
});

/// Effective access for the signed-in account. Used only to choose which panels appear;
/// every privileged action is re-checked by the database.
final accessProvider = FutureProvider<AccessSnapshot>((ref) {
  if (ref.watch(sessionProvider) == null) return AccessSnapshot.empty;
  return ref.watch(repositoryProvider).myAccess();
});

final channelsProvider = FutureProvider<List<ChannelModel>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).channels();
});

final mySubscriptionsProvider = FutureProvider<List<ChannelModel>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).mySubscriptions();
});

final myBusinessesProvider = FutureProvider<List<BusinessSummary>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).myBusinesses();
});

final myVerificationProvider = FutureProvider<List<VerificationApplication>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).myVerificationApplications();
});

final partnerDashboardProvider = FutureProvider<PartnerDashboard?>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).partnerDashboard();
});

final myPartnerApplicationsProvider = FutureProvider<List<PartnerApplication>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).myPartnerApplications();
});

final notificationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).myNotifications();
});
