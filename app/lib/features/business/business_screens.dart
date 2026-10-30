import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

const _businessCategories = ['Retail', 'Food & drink', 'Services', 'Media', 'Education', 'Technology', 'Other'];

class BusinessHomeScreen extends ConsumerWidget {
  const BusinessHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businesses = ref.watch(myBusinessesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Business'),
        actions: [
          IconButton(
            tooltip: 'Create business',
            icon: const Icon(Icons.add_business_outlined),
            onPressed: () => context.push('/business/new'),
          ),
        ],
      ),
      body: AsyncBody<List<BusinessSummary>>(
        value: businesses,
        onRetry: () => ref.invalidate(myBusinessesProvider),
        builder: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Set up a business account to manage a public profile, catalog and quick replies.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    GradientButton(
                      label: 'Create business',
                      icon: Icons.add_business_outlined,
                      onPressed: () => context.push('/business/new'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final b = list[i];
              return GlassCard(
                onTap: () => context.push('/business/${b.id}'),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                        if (b.isVerified) ...[const SizedBox(width: 4), const VerifiedMark()],
                      ]),
                      Text('@${b.username} · ${b.category}'),
                      if (!b.isSetupComplete) const StatusBadge(label: 'Setup incomplete', color: Colors.orange),
                    ]),
                  ),
                  const Icon(Icons.chevron_right),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

class CreateBusinessScreen extends ConsumerStatefulWidget {
  const CreateBusinessScreen({super.key});

  @override
  ConsumerState<CreateBusinessScreen> createState() => _CreateBusinessScreenState();
}

class _CreateBusinessScreenState extends ConsumerState<CreateBusinessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _website = TextEditingController();
  final _description = TextEditingController();
  String _category = _businessCategories.first;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _username, _email, _website, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final id = await runValue(
      context,
      () => ref.read(repositoryProvider).createBusiness(
            name: _name.text,
            username: _username.text,
            category: _category,
            businessEmail: _email.text,
            description: _description.text,
            website: _website.text,
          ),
      success: 'Business created',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(myBusinessesProvider);
    if (id != null) context.go('/business/$id');
  }

  @override
  Widget build(BuildContext context) => BubblePage(
        title: 'Create business',
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Business name'),
                  validator: (v) => (v ?? '').trim().length < 2 ? 'Enter a name' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _username, decoration: const InputDecoration(labelText: 'Username', prefixText: '@'),
                  validator: (v) => RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch((v ?? '').trim())
                      ? null
                      : '3–32 letters, numbers or underscores'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [for (final c in _businessCategories) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _email, keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Business email'),
                  validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email'),
              const SizedBox(height: 12),
              TextFormField(controller: _website, decoration: const InputDecoration(labelText: 'Website (optional)')),
              const SizedBox(height: 12),
              TextFormField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'Description')),
              const SizedBox(height: 20),
              GradientButton(label: 'Create business', icon: Icons.check, onPressed: _create, busy: _busy),
            ],
          ),
        ),
      );
}

final _businessDashboardProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) {
  ref.watch(sessionProvider);
  return ref.watch(repositoryProvider).businessDashboard(id);
});

class BusinessDashboardScreen extends ConsumerWidget {
  const BusinessDashboardScreen({super.key, required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(myBusinessesProvider).valueOrNull?.where((b) => b.id == businessId).firstOrNull;
    final dash = ref.watch(_businessDashboardProvider(businessId));
    return BubblePage(
      title: business?.name ?? 'Business',
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_businessDashboardProvider(businessId));
          ref.invalidate(myBusinessesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AsyncBody<Map<String, dynamic>>(
              value: dash,
              onRetry: () => ref.invalidate(_businessDashboardProvider(businessId)),
              builder: (d) => GlassCard(
                child: Wrap(spacing: 18, runSpacing: 8, children: [
                  _Metric(label: 'Operators', value: d['operators']),
                  _Metric(label: 'Catalog items', value: d['catalog_items']),
                  _Metric(label: 'Quick replies', value: d['quick_replies']),
                  _Metric(label: 'Verified', value: d['is_verified'] == true ? 'Yes' : 'No'),
                ]),
              ),
            ),
            const SectionHeader('Mode'),
            GradientButton(
              label: 'Switch to business mode',
              icon: Icons.storefront_outlined,
              onPressed: () async {
                final ok = await runAction(
                  context,
                  () => ref.read(repositoryProvider).switchAccountMode(mode: 'business', businessId: businessId),
                  success: 'Business mode is active',
                );
                if (ok) ref.invalidate(myBusinessesProvider);
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.person_outline),
              label: const Text('Switch to personal mode'),
              onPressed: () async {
                final ok = await runAction(
                  context,
                  () => ref.read(repositoryProvider).switchAccountMode(mode: 'personal'),
                  success: 'Personal mode is active',
                );
                if (ok) ref.invalidate(myBusinessesProvider);
              },
            ),
            const SectionHeader('Messaging'),
            GlassCard(
              onTap: () => context.push('/business/$businessId/messaging'),
              child: const Row(children: [
                Icon(Icons.chat_bubble_outline),
                SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Customer chats', style: TextStyle(fontWeight: FontWeight.w700)), Text('Labels, quick replies, welcome & away messages')])),
                Icon(Icons.chevron_right),
              ]),
            ),
            const SectionHeader('Verification'),
            OutlinedButton.icon(
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Apply to verify this business'),
              onPressed: () => context.push('/verification/apply/business?id=$businessId'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text('${value ?? 0}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Text(label),
      ]);
}
