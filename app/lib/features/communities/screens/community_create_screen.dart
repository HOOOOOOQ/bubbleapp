import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/social_repository.dart';
import '../../../widgets/common.dart';

class CommunityCreateScreen extends ConsumerStatefulWidget {
  const CommunityCreateScreen({super.key});
  @override
  ConsumerState<CommunityCreateScreen> createState() => _CommunityCreateScreenState();
}

class _CommunityCreateScreenState extends ConsumerState<CommunityCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _desc = TextEditingController();
  final _category = TextEditingController();
  final _rules = TextEditingController();
  String _visibility = 'private';
  bool _joinApproval = false;
  bool _busy = false;

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final c = await ref.read(socialRepositoryProvider).createCommunity(
        name: _name.text.trim(),
        username: _username.text.trim().isEmpty ? null : _username.text.trim(),
        description: _desc.text.trim(),
        category: _category.text.trim().isEmpty ? null : _category.text.trim(),
        rules: _rules.text.trim().isEmpty ? null : _rules.text.trim(),
        visibility: _visibility,
        joinApproval: _joinApproval,
      );
      if (mounted) { showMessage(context, 'Community created'); context.go('/communities/${c.id}'); }
    } catch (e) { if (mounted) showMessage(context, 'Failed: $e'); }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('New community')),
        body: Form(key: _formKey, child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Community name *'), validator: (v) => (v ?? '').trim().length < 2 ? 'Enter a name' : null),
          const SizedBox(height: 12),
          TextFormField(controller: _username, decoration: const InputDecoration(labelText: 'Username/slug (unique)', prefixText: '@', hintText: 'bubble_devs'), validator: (v) { if ((v ?? '').isEmpty) return null; return RegExp(r'^[a-z][a-z0-9_]{2,30}$').hasMatch(v!.trim()) ? null : '3-31 chars: a-z 0-9 _'; }),
          const SizedBox(height: 12),
          TextFormField(controller: _desc, maxLines: 3, decoration: const InputDecoration(labelText: 'Description'), validator: (v) => null),
          const SizedBox(height: 12),
          TextFormField(controller: _category, decoration: const InputDecoration(labelText: 'Category', hintText: 'Tech, Gaming, Music...')),
          const SizedBox(height: 12),
          TextFormField(controller: _rules, maxLines: 3, decoration: const InputDecoration(labelText: 'Community rules')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(value: _visibility, decoration: const InputDecoration(labelText: 'Visibility'), items: const [DropdownMenuItem(value: 'public', child: Text('Public — anyone can find and join')), DropdownMenuItem(value: 'private', child: Text('Private — invite/request only'))], onChanged: (v) => setState(() => _visibility = v!)),
          SwitchListTile(title: const Text('Require approval to join'), value: _joinApproval, onChanged: (v) => setState(() => _joinApproval = v)),
          const SizedBox(height: 16),
          GradientButton(label: 'Create community', icon: Icons.groups_outlined, onPressed: _create, busy: _busy),
          const SizedBox(height: 8),
          Text('Communities use RLS + trusted RPCs: owner is protected, private communities hidden from search, join requests via community_join_requests.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ])),
      );
}
