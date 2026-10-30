import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/social_repository.dart';
import '../models/social.dart';

final supabaseClientProvider2 = Provider<SupabaseClient>((ref) => Supabase.instance.client);
final socialRepositoryProvider = Provider<SocialRepository>((ref) => SocialRepository(ref.watch(supabaseClientProvider2)));

// Stories
final storiesFeedProvider = FutureProvider<List<Story>>((ref) {
  ref.watch(sessionProvider2);
  return ref.watch(socialRepositoryProvider).feedStories();
});
final storyInsightsProvider = FutureProvider.family<StoryInsight, String>((ref, storyId) => ref.watch(socialRepositoryProvider).storyInsights(storyId));

final sessionProvider2 = Provider<Session?>((ref) {
  final client = ref.watch(supabaseClientProvider2);
  return client.auth.currentSession;
});

// Communities
final communitiesProvider = FutureProvider<List<Community>>((ref) => ref.watch(socialRepositoryProvider).communities());
final communityProvider = FutureProvider.family<Community?, String>((ref, id) => ref.watch(socialRepositoryProvider).community(id));
final communityMembersProvider = FutureProvider.family<List<CommunityMember>, String>((ref, id) => ref.watch(socialRepositoryProvider).communityMembers(id));
final communityJoinRequestsProvider = FutureProvider.family<List<CommunityJoinRequest>, String>((ref, id) => ref.watch(socialRepositoryProvider).communityJoinRequests(id));

// Feed
final feedProvider = FutureProvider.family<List<Post>, String>((ref, kind) => ref.watch(socialRepositoryProvider).feed(kind: kind));
final postProvider = FutureProvider.family<Post?, String>((ref, id) => ref.watch(socialRepositoryProvider).post(id));
final commentsProvider = FutureProvider.family<List<Comment>, String>((ref, postId) => ref.watch(socialRepositoryProvider).comments(postId));
final trendingPostsProvider = FutureProvider<List<Post>>((ref) => ref.watch(socialRepositoryProvider).trendingPosts());
final trendingHashtagsProvider = FutureProvider<List<Hashtag>>((ref) => ref.watch(socialRepositoryProvider).trendingHashtags());

// Discovery
final searchProvider = FutureProvider.family<SearchResult, String>((ref, q) => ref.watch(socialRepositoryProvider).searchAll(q));
final recentSearchesProvider = FutureProvider<List<String>>((ref) => ref.watch(socialRepositoryProvider).recentSearches());

// Groups
final groupSettingsProvider = FutureProvider.family<GroupSettings, String>((ref, convId) => ref.watch(socialRepositoryProvider).groupSettings(convId));
