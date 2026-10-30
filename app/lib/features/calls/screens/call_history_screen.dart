import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../config/theme.dart';
import '../../../data/call_repository.dart';
import '../../../models/call_models.dart';
import '../../../widgets/common.dart';
import '../state/call_manager.dart';

class CallHistoryScreen extends ConsumerStatefulWidget {
  const CallHistoryScreen({super.key});
  @override
  ConsumerState<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends ConsumerState<CallHistoryScreen> {
  List<CallHistoryEntry> _entries = [];
  bool _loading = true;
  String _filter = 'all'; // all | missed | incoming | outgoing

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final entries = await ref.read(callRepositoryProvider).myCallHistory(limit: 100);
      setState(() { _entries = entries; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  List<CallHistoryEntry> get _filtered {
    switch (_filter) {
      case 'missed': return _entries.where((e) => e.isMissed).toList();
      case 'incoming': return _entries.where((e) => e.isIncoming).toList();
      case 'outgoing': return _entries.where((e) => e.isOutgoing).toList();
      default: return _entries;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(title: const Text('Calls')), body: const Center(child: CircularProgressIndicator()));
    final list = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calls'),
        actions: [
          PopupMenuButton<String>(onSelected: (v) async {
            if (v == 'clear') {
              final ok = await confirmAction(context, title: 'Clear call history?', body: 'This will hide all calls from your history. Others still see their records.', confirmLabel: 'Clear');
              if (ok && context.mounted) { await ref.read(callRepositoryProvider).clearCallHistory(); _load(); }
            }
          }, itemBuilder: (c) => [PopupMenuItem(value: 'clear', child: Text('Clear history')),]),
        ],
      ),
      body: Column(children: [
        SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: [
          _Chip(label: 'All', selected: _filter=='all', onTap: () => setState(() => _filter='all')),
          _Chip(label: 'Missed', selected: _filter=='missed', onTap: () => setState(() => _filter='missed')),
          _Chip(label: 'Incoming', selected: _filter=='incoming', onTap: () => setState(() => _filter=='incoming')),
          _Chip(label: 'Outgoing', selected: _filter=='outgoing', onTap: () => setState(() => _filter=='outgoing')),
        ])),
        Expanded(child: list.isEmpty ? const EmptyState(message: 'No calls yet', icon: Icons.call_outlined) : RefreshIndicator(onRefresh: _load, child: ListView.separated(padding: const EdgeInsets.all(12), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (c,i) {
          final e = list[i];
          final title = e.titleFallback(ref.read(callRepositoryProvider).currentUserId ?? '');
          final avatar = e.otherUser?.avatarUrl;
          return Dismissible(key: ValueKey(e.call.id), direction: DismissDirection.endToStart, background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16), decoration: BoxDecoration(color: BubbleColors.danger, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.delete_outline, color: Colors.white)), onDismissed: (_) async { await ref.read(callRepositoryProvider).hideCallHistory(e.call.id); setState(() => _entries.remove(e)); }, child: GlassCard(onTap: () => context.push('/chats/${e.call.conversationId}'), child: Row(children: [
            Stack(children: [CircleAvatar(radius: 22, backgroundImage: avatar != null ? NetworkImage(avatar) : null, child: avatar==null ? Text(title[0].toUpperCase()) : null), if (e.isMissed) Positioned(right: 0, bottom: 0, child: Container(width: 14, height: 14, decoration: BoxDecoration(color: BubbleColors.danger, shape: BoxShape.circle, border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2)), child: const Icon(Icons.call_missed, size: 8, color: Colors.white)))]),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Flexible(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))), if (e.otherUser?.isVerified == true) const Padding(padding: EdgeInsets.only(left: 4), child: VerifiedMark(size: 14)), if (e.isGroup) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.group, size: 14))]),
              Row(children: [Icon(e.isOutgoing ? Icons.call_made : e.isMissed ? Icons.call_missed : Icons.call_received, size: 14, color: e.isMissed ? BubbleColors.danger : Theme.of(context).colorScheme.onSurfaceVariant), const SizedBox(width: 4), Text(_subtitle(e), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)), const SizedBox(width: 6), Icon(e.isVideo ? Icons.videocam : Icons.call, size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)]),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(e.call.startedAt != null ? DateFormat('MMM d, h:mm a').format(e.call.startedAt!) : '', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)), if (e.call.durationSeconds != null) Text(_dur(e.call.durationSeconds!), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant))]),
            IconButton(icon: const Icon(Icons.call, color: BubbleColors.blue), onPressed: () async { final mgr = ref.read(callManagerProvider.notifier); await mgr.startCall(conversationId: e.call.conversationId, media: e.isVideo ? 'video' : 'voice'); if (context.mounted) context.push('/calls/outgoing/${e.call.id}'); }),
          ])) );
        })) ),
      ]),
    );
  }

  String _subtitle(CallHistoryEntry e) {
    if (e.isMissed) return 'Missed';
    if (e.call.isDeclined) return 'Declined';
    if (e.call.isCancelled) return 'Cancelled';
    if (e.call.durationSeconds != null) return _dur(e.call.durationSeconds!);
    return e.direction;
  }
  String _dur(int s) { final m = s ~/ 60; final sec = s % 60; if (m > 0) return '${m}m ${sec}s'; return '${sec}s'; }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label; final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(selected: selected, label: Text(label), onSelected: (_) => onTap(), selectedColor: BubbleColors.blue, labelStyle: TextStyle(color: selected ? Colors.white : null, fontWeight: FontWeight.w600)));
}
