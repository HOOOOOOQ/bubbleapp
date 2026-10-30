import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../widgets/common.dart';
import '../../../state/social_providers.dart';

class StoryInsightsScreen extends ConsumerWidget {
  const StoryInsightsScreen({super.key, required this.storyId});
  final String storyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(storyInsightsProvider(storyId));
    return Scaffold(
      appBar: AppBar(title: const Text('Story insights')),
      body: AsyncBody(
        value: insights,
        builder: (data) => ListView(padding: const EdgeInsets.all(16), children: [
          GlassCard(child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _Stat(label: 'Views', value: '${data.viewCount}', icon: Icons.visibility_outlined),
            _Stat(label: 'Reactions', value: '${data.reactions}', icon: Icons.favorite_border),
            _Stat(label: 'Replies', value: '${data.replies}', icon: Icons.reply_outlined),
          ])),
          const SectionHeader('Viewers'),
          if (data.viewers.isEmpty) const EmptyState(message: 'No views yet', icon: Icons.visibility_off_outlined)
          else ...data.viewers.map((v) => Padding(padding: const EdgeInsets.only(bottom: 8), child: GlassCard(child: Row(children: [
            CircleAvatar(radius: 20, backgroundImage: v.viewer?.avatarUrl != null ? NetworkImage(v.viewer!.avatarUrl!) : null, child: v.viewer?.avatarUrl == null ? Text((v.viewer?.displayName ?? '?')[0]) : null),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(v.viewer?.displayName ?? v.viewerId, style: const TextStyle(fontWeight: FontWeight.w600)), Text('@${v.viewer?.username ?? ''}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12))])),
            Text(v.viewedAt != null ? '${v.viewedAt!.hour}:${v.viewedAt!.minute.toString().padLeft(2,'0')}' : '', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (v.viewer?.isVerified == true) const Padding(padding: EdgeInsets.only(left: 6), child: VerifiedMark(size: 14)),
          ])))),
          const SizedBox(height: 12),
          Text('Only owners and admins may see viewer lists. Data is from real story_views with RLS (expires after 24h, hidden stories excluded).', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon});
  final String label; final String value; final IconData icon;
  @override
  Widget build(BuildContext context) => Column(children: [Icon(icon, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 6), Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)), Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12))]);
}
