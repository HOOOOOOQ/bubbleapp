import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/bubble_error.dart';
import '../../../data/social_repository.dart';
import '../../../models/social.dart';
import '../../../widgets/common.dart';

class PollWidget extends ConsumerStatefulWidget {
  const PollWidget({super.key, required this.pollId});
  final String pollId;
  @override
  ConsumerState<PollWidget> createState() => _PollWidgetState();
}

class _PollWidgetState extends ConsumerState<PollWidget> {
  Poll? _poll;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try { final p = await ref.read(socialRepositoryProvider).pollWithOptions(widget.pollId); setState(() { _poll = p; _loading = false; }); } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator());
    if (_poll == null) return const Text('Poll not found');
    final poll = _poll!;
    final total = poll.totalVotes == 0 ? 1 : poll.totalVotes;
    return GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(poll.question, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text('${poll.totalVotes} votes • ${poll.isExpired ? 'Expired' : (poll.expiresAt != null ? 'Ends ${poll.expiresAt}' : 'Live')} • ${poll.allowMultiple ? 'Multiple choice' : 'Single choice'} ${poll.allowAnonymous ? '• Anonymous' : ''}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 10),
      ...poll.options.map((o) {
        final pct = (o.voteCount / total * 100).round();
        final selected = poll.myVotes.contains(o.id);
        return Padding(padding: const EdgeInsets.only(bottom: 8), child: InkWell(
          onTap: poll.isExpired ? null : () async { try { await ref.read(socialRepositoryProvider).votePoll(poll.id, o.id); await _load(); if (mounted) showMessage(context, 'Voted'); } catch (e) { if (mounted) showMessage(context, friendlyError(e)); } },
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: selected ? Theme.of(context).colorScheme.primary.withOpacity(0.12) : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6), borderRadius: BorderRadius.circular(12), border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent)),
            child: Row(children: [
              Icon(selected ? Icons.check_circle : Icons.circle_outlined, size: 18, color: selected ? Theme.of(context).colorScheme.primary : null),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(o.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)), const SizedBox(height: 4), ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: o.voteCount / total, minHeight: 6)) ])),
              const SizedBox(width: 8),
              Text('$pct% • ${o.voteCount}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ),
        ));
      }),
      if (!poll.isExpired && poll.allowChange && poll.myVotes.isNotEmpty) TextButton(onPressed: () async { await ref.read(socialRepositoryProvider).unvotePoll(poll.id); await _load(); }, child: const Text('Change vote')),
      Text('Duplicate votes prevented by DB (poll_votes PK + guard_poll_vote). Anonymous votes hide voter identity in UI but still enforce one vote per user server-side.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]));
  }
}
