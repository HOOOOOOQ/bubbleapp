import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/business_partner.dart';
import '../../state/business_partner_providers.dart';
import '../../widgets/common.dart';

// ---------------------------------------------------------------- workspace

class PartnerWorkspaceScreen extends ConsumerWidget {
  const PartnerWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(partnerWorkspaceProvider);
    final applications = ref.watch(myPartnerApplicationsProvider);

    return BubblePage(
      title: 'Partner program',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: () {
            ref.invalidate(partnerWorkspaceProvider);
            ref.invalidate(myPartnerApplicationsProvider);
          },
        ),
      ],
      child: AsyncBody<PartnerWorkspace?>(
        value: workspace,
        onRetry: () => ref.invalidate(partnerWorkspaceProvider),
        builder: (w) {
          if (w == null || !w.isActivePartner) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const GlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('BubbleApp Partners', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    SizedBox(height: 6),
                    Text('Approved partners get a verified partner profile, a directory listing and a direct support channel.'),
                  ]),
                ),
                const SectionHeader('Your application'),
                AsyncBody<List<PartnerApplicationRecord>>(
                  value: applications,
                  onRetry: () => ref.invalidate(myPartnerApplicationsProvider),
                  builder: (list) {
                    if (list.isEmpty) {
                      return Column(children: [
                        const Text('You have not applied yet.'),
                        const SizedBox(height: 12),
                        GradientButton(
                          label: 'Start an application',
                          icon: Icons.arrow_forward,
                          onPressed: () => context.push('/partners/application'),
                        ),
                      ]);
                    }
                    return Column(children: [
                      for (final app in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassCard(
                            onTap: () => context.push('/partners/application?id=${app.id}'),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(app.organization.isEmpty ? 'Draft application' : app.organization,
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text(app.category),
                                  if (app.decisionNote != null) Text('Reviewer note: ${app.decisionNote}'),
                                ]),
                              ),
                              StatusBadge(label: app.status.replaceAll('_', ' ')),
                            ]),
                          ),
                        ),
                      GradientButton(
                        label: list.any((a) => a.isEditable) ? 'Continue draft' : 'New application',
                        icon: Icons.edit_outlined,
                        onPressed: () => context.push('/partners/application?id=${list.first.id}'),
                      ),
                    ]);
                  },
                ),
                const SectionHeader('What partners get'),
                const GlassCard(
                  child: Text('Partner badge, directory listing, announcements, resource library, '
                      'a direct support channel and featured-profile eligibility. Early access and '
                      'revenue sharing are not implemented in this release.'),
                ),
              ],
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(partnerWorkspaceProvider);
              ref.invalidate(myPartnerProfileProvider);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                GlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.handshake_outlined),
                      const SizedBox(width: 8),
                      Text('Active partner', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      if (w.isBadgeVisible) const VerifiedMark(),
                      if (w.isFeatured) const StatusBadge(label: 'Featured', color: Colors.amber),
                    ]),
                    const SizedBox(height: 6),
                    Text('${w.announcements} announcements · ${w.resourcesCount} resources'),
                    if (w.featuredUntil != null) Text('Featured until ${w.featuredUntil}'),
                  ]),
                ),
                const SectionHeader('Benefits'),
                ...w.benefits.map((b) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                        child: Row(children: [
                          Icon(
                            b.usable ? Icons.check_circle : Icons.remove_circle_outline,
                            color: b.usable ? Colors.green : Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(b.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(b.description),
                              if (!b.enabled)
                                const Text('Currently disabled by BubbleApp.',
                                    style: TextStyle(fontSize: 12)),
                            ]),
                          ),
                          StatusBadge(
                            label: b.usable ? 'Active' : 'Unavailable',
                            color: b.usable ? Colors.green : Colors.grey,
                          ),
                        ]),
                      ),
                    )),
                if (w.notImplemented.isNotEmpty) ...[
                  const SectionHeader('Not part of this release'),
                  GlassCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final item in w.notImplemented)
                        Text('• ${item['key']}: ${item['reason']}'),
                    ]),
                  ),
                ],
                const SectionHeader('Quick actions'),
                _PartnerTile(
                  icon: Icons.badge_outlined,
                  title: 'Partner profile',
                  subtitle: 'Headline, bio, specialties and directory visibility',
                  onTap: () => context.push('/partners/profile'),
                ),
                _PartnerTile(
                  icon: Icons.menu_book_outlined,
                  title: 'Resources',
                  subtitle: 'Guides, brand assets and playbooks',
                  onTap: () => context.push('/partners/resources'),
                ),
                _PartnerTile(
                  icon: Icons.support_agent,
                  title: 'Partner support',
                  subtitle: 'Open a request with the BubbleApp team',
                  onTap: () => context.push('/partners/support'),
                ),
                _PartnerTile(
                  icon: Icons.travel_explore,
                  title: 'Partner directory',
                  subtitle: 'Public list of approved partners',
                  onTap: () => context.push('/partners/directory'),
                ),
                const SectionHeader('Recent activity'),
                if (w.activity.isEmpty)
                  const EmptyState(message: 'No partner activity yet.', icon: Icons.history)
                else
                  ...w.activity.take(10).map((a) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.timeline),
                        title: Text(a.summary),
                        subtitle: Text(a.kind),
                      )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PartnerTile extends StatelessWidget {
  const _PartnerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GlassCard(
          onTap: onTap,
          child: Row(children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(subtitle),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      );
}

// ---------------------------------------------------------------- profile

class PartnerProfileEditScreen extends ConsumerStatefulWidget {
  const PartnerProfileEditScreen({super.key});

  @override
  ConsumerState<PartnerProfileEditScreen> createState() => _PartnerProfileEditScreenState();
}

class _PartnerProfileEditScreenState extends ConsumerState<PartnerProfileEditScreen> {
  final _displayName = TextEditingController();
  final _headline = TextEditingController();
  final _bio = TextEditingController();
  final _website = TextEditingController();
  final _logoUrl = TextEditingController();
  final _coverUrl = TextEditingController();
  final _specialties = TextEditingController();
  bool _directoryVisible = true;
  bool _badgeEnabled = true;
  bool _hydrated = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_displayName, _headline, _bio, _website, _logoUrl, _coverUrl, _specialties]) {
      c.dispose();
    }
    super.dispose();
  }

  void _hydrate(PartnerOwnProfile p) {
    if (_hydrated) return;
    _hydrated = true;
    _displayName.text = p.displayName;
    _headline.text = p.headline;
    _bio.text = p.bio;
    _website.text = p.website ?? '';
    _logoUrl.text = p.logoUrl ?? '';
    _coverUrl.text = p.coverUrl ?? '';
    _specialties.text = p.specialties.join(', ');
    _directoryVisible = p.directoryVisible;
    _badgeEnabled = p.isBadgeVisible;
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref.read(businessPartnerRepositoryProvider).updatePartnerProfile({
        'display_name': _displayName.text.trim(),
        'headline': _headline.text.trim(),
        'bio': _bio.text.trim(),
        'website': _website.text.trim(),
        'logo_url': _logoUrl.text.trim(),
        'cover_url': _coverUrl.text.trim(),
        'specialties': _specialties.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .take(8)
            .toList(),
        'directory_visible': _directoryVisible,
        'badge_enabled': _badgeEnabled,
      }),
      success: 'Partner profile updated',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(myPartnerProfileProvider);
      ref.invalidate(partnerWorkspaceProvider);
      ref.invalidate(partnerDirectoryProvider(const PartnerDirectoryQuery()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(myPartnerProfileProvider);
    return BubblePage(
      title: 'Partner profile',
      child: AsyncBody<PartnerOwnProfile?>(
        value: profile,
        onRetry: () => ref.invalidate(myPartnerProfileProvider),
        builder: (p) {
          if (p == null) {
            return const EmptyState(
              message: 'Your partner profile appears after an application is approved.',
              icon: Icons.badge_outlined,
            );
          }
          _hydrate(p);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Status: ${p.partnerStatus}'),
                  Text('Category: ${p.partnerCategory}'),
                  if (p.isFeatured) const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: StatusBadge(label: 'Featured partner', color: Colors.amber),
                  ),
                  const SizedBox(height: 6),
                  const Text('Your status and category are set by BubbleApp and cannot be edited here.',
                      style: TextStyle(fontSize: 12)),
                ]),
              ),
              const SectionHeader('Public presentation'),
              TextField(
                controller: _displayName,
                decoration: const InputDecoration(labelText: 'Display name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _headline,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Headline'),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _bio,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Bio'),
              ),
              TextField(
                controller: _website,
                decoration: const InputDecoration(labelText: 'Website'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _specialties,
                decoration: const InputDecoration(
                  labelText: 'Specialties',
                  helperText: 'Comma separated, up to 8',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _logoUrl,
                decoration: const InputDecoration(labelText: 'Logo URL'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _coverUrl,
                decoration: const InputDecoration(labelText: 'Cover URL'),
              ),
              const SectionHeader('Visibility'),
              SwitchListTile(
                value: _directoryVisible,
                onChanged: (v) => setState(() => _directoryVisible = v),
                title: const Text('List my profile in the partner directory'),
              ),
              SwitchListTile(
                value: _badgeEnabled,
                onChanged: (v) => setState(() => _badgeEnabled = v),
                title: const Text('Show the partner badge on my profile'),
              ),
              const SizedBox(height: 16),
              GradientButton(
                label: 'Save partner profile',
                icon: Icons.check,
                busy: _busy,
                onPressed: _save,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- resources

class PartnerResourcesScreen extends ConsumerWidget {
  const PartnerResourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resources = ref.watch(partnerResourcesProvider);
    return BubblePage(
      title: 'Partner resources',
      child: AsyncBody<List<PartnerResource>>(
        value: resources,
        onRetry: () => ref.invalidate(partnerResourcesProvider),
        builder: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              message: 'No resources have been published yet.',
              icon: Icons.menu_book_outlined,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final r = list[i];
              return GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700))),
                    StatusBadge(label: r.kind),
                  ]),
                  if (r.description.isNotEmpty) Text(r.description),
                  if (r.body != null && r.body!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(r.body!),
                  ],
                  if (r.url != null) ...[
                    const SizedBox(height: 6),
                    SelectableText(r.url!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- support

class PartnerSupportScreen extends ConsumerStatefulWidget {
  const PartnerSupportScreen({super.key});

  @override
  ConsumerState<PartnerSupportScreen> createState() => _PartnerSupportScreenState();
}

class _PartnerSupportScreenState extends ConsumerState<PartnerSupportScreen> {
  Future<void> _create() async {
    final subject = TextEditingController();
    final body = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open a support request'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: subject, decoration: const InputDecoration(labelText: 'Subject')),
          const SizedBox(height: 12),
          TextField(
            controller: body,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'How can we help?'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    final subjectText = subject.text.trim();
    final bodyText = body.text.trim();
    subject.dispose();
    body.dispose();
    if (result != true || subjectText.isEmpty || bodyText.isEmpty || !mounted) return;
    final ok = await runAction(
      context,
      () => ref
          .read(businessPartnerRepositoryProvider)
          .createPartnerSupport(subject: subjectText, body: bodyText),
      success: 'Support request sent',
    );
    if (ok) {
      ref.invalidate(partnerSupportProvider);
      ref.invalidate(partnerWorkspaceProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(partnerSupportProvider);
    return BubblePage(
      title: 'Partner support',
      actions: [
        IconButton(tooltip: 'New request', icon: const Icon(Icons.add), onPressed: _create),
      ],
      child: AsyncBody<List<PartnerSupportRequest>>(
        value: requests,
        onRetry: () => ref.invalidate(partnerSupportProvider),
        builder: (list) {
          if (list.isEmpty) {
            return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const EmptyState(
                message: 'No support requests yet.',
                icon: Icons.support_agent,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: GradientButton(
                  label: 'Open a request',
                  icon: Icons.add,
                  onPressed: _create,
                ),
              ),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final r = list[i];
              return GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(r.subject, style: const TextStyle(fontWeight: FontWeight.w700))),
                    StatusBadge(
                      label: r.status,
                      color: r.status == 'answered' ? Colors.green : Colors.orange,
                    ),
                  ]),
                  Text(r.body),
                  if (r.response != null && r.response!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('BubbleApp: ${r.response}'),
                  ],
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- directory

class PartnerDirectoryScreen extends ConsumerStatefulWidget {
  const PartnerDirectoryScreen({super.key});

  @override
  ConsumerState<PartnerDirectoryScreen> createState() => _PartnerDirectoryScreenState();
}

class _PartnerDirectoryScreenState extends ConsumerState<PartnerDirectoryScreen> {
  final _search = TextEditingController();
  String? _category;
  bool _featuredOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = PartnerDirectoryQuery(
      search: _search.text.trim().isEmpty ? null : _search.text.trim(),
      category: _category,
      featuredOnly: _featuredOnly,
    );
    final directory = ref.watch(partnerDirectoryProvider(query));
    return BubblePage(
      title: 'Partner directory',
      child: AsyncBody<PartnerDirectory>(
        value: directory,
        onRetry: () => ref.invalidate(partnerDirectoryProvider(query)),
        builder: (d) {
          if (!d.enabled) {
            return const EmptyState(
              message: 'The partner directory is currently disabled by BubbleApp.',
              icon: Icons.travel_explore,
            );
          }
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  labelText: 'Search partners',
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (_) => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                FilterChip(
                  label: const Text('Featured only'),
                  selected: _featuredOnly,
                  onSelected: (v) => setState(() => _featuredOnly = v),
                ),
                ChoiceChip(
                  label: const Text('All categories'),
                  selected: _category == null,
                  onSelected: (_) => setState(() => _category = null),
                ),
                for (final category in d.categories)
                  ChoiceChip(
                    label: Text(category),
                    selected: _category == category,
                    onSelected: (_) => setState(() => _category = category),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: d.partners.isEmpty
                  ? const EmptyState(message: 'No partners match this filter.', icon: Icons.travel_explore)
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: d.partners.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final p = d.partners[i];
                        return GlassCard(
                          onTap: () => context.push('/partners/${p.userId}'),
                          child: Row(children: [
                            CircleAvatar(
                              backgroundImage: p.logoUrl == null ? null : NetworkImage(p.logoUrl!),
                              child: p.logoUrl == null
                                  ? Text(p.displayName.isEmpty ? '?' : p.displayName[0].toUpperCase())
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Flexible(
                                    child: Text(p.displayName,
                                        style: const TextStyle(fontWeight: FontWeight.w700)),
                                  ),
                                  if (p.isBadgeVisible) ...[
                                    const SizedBox(width: 4),
                                    const VerifiedMark(size: 14),
                                  ],
                                  if (p.isFeatured) ...[
                                    const SizedBox(width: 6),
                                    const StatusBadge(label: 'Featured', color: Colors.amber),
                                  ],
                                ]),
                                if (p.headline.isNotEmpty) Text(p.headline),
                                Text('${p.partnerCategory}${p.specialties.isEmpty ? '' : ' · ${p.specialties.join(', ')}'}'),
                              ]),
                            ),
                            const Icon(Icons.chevron_right),
                          ]),
                        );
                      },
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

class PartnerPublicProfileScreen extends ConsumerWidget {
  const PartnerPublicProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(partnerPublicProfileProvider(userId));
    return BubblePage(
      title: 'Partner',
      child: AsyncBody<PartnerPublicProfile?>(
        value: profile,
        onRetry: () => ref.invalidate(partnerPublicProfileProvider(userId)),
        builder: (p) {
          if (p == null) {
            return const EmptyState(
              message: 'This partner profile is not publicly listed.',
              icon: Icons.travel_explore,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (p.coverUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(p.coverUrl!, height: 140, fit: BoxFit.cover),
                ),
              const SizedBox(height: 12),
              Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage: p.logoUrl == null ? null : NetworkImage(p.logoUrl!),
                  child: p.logoUrl == null ? Text(p.displayName.isEmpty ? '?' : p.displayName[0].toUpperCase()) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(
                        child: Text(p.displayName,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      ),
                      if (p.isBadgeVisible) ...[const SizedBox(width: 6), const VerifiedMark()],
                    ]),
                    Text('@${p.username}'),
                    Text(p.partnerCategory),
                  ]),
                ),
              ]),
              if (p.headline.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(p.headline, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
              if (p.bio.isNotEmpty) ...[const SizedBox(height: 8), Text(p.bio)],
              if (p.specialties.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final s in p.specialties) Chip(label: Text(s)),
                ]),
              ],
              if (p.website != null) ...[
                const SizedBox(height: 12),
                SelectableText(p.website!),
              ],
              const SizedBox(height: 20),
              if (p.canMessage)
                GradientButton(
                  label: 'Message this partner',
                  icon: Icons.chat_bubble_outline,
                  onPressed: () => context.push('/chats/new'),
                )
              else
                const Text('Messaging is not available for this partner yet.'),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- application

class PartnerApplicationScreen extends ConsumerStatefulWidget {
  const PartnerApplicationScreen({super.key, this.applicationId});

  final String? applicationId;

  @override
  ConsumerState<PartnerApplicationScreen> createState() => _PartnerApplicationScreenState();
}

class _PartnerApplicationScreenState extends ConsumerState<PartnerApplicationScreen> {
  final _organization = TextEditingController();
  final _proposal = TextEditingController();
  final _description = TextEditingController();
  final _website = TextEditingController();
  final _instagram = TextEditingController();
  String _category = 'Agency';
  bool _hydrated = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_organization, _proposal, _description, _website, _instagram]) {
      c.dispose();
    }
    super.dispose();
  }

  void _hydrate(List<PartnerApplicationRecord> list) {
    if (_hydrated || widget.applicationId == null) return;
    final match = list.where((a) => a.id == widget.applicationId).firstOrNull;
    if (match == null) return;
    _hydrated = true;
    _organization.text = match.organization;
    _proposal.text = match.proposal;
    _website.text = match.website ?? '';
    if (match.category.isNotEmpty) _category = match.category;
  }

  Future<void> _saveDraft({bool submit = false}) async {
    setState(() => _busy = true);
    final repo = ref.read(businessPartnerRepositoryProvider);
    final payload = {
      'organization': _organization.text.trim(),
      'partnership_category': _category,
      'proposal': _proposal.text.trim(),
      'description': _description.text.trim(),
      'website': _website.text.trim(),
      'social_media': {
        if (_instagram.text.trim().isNotEmpty) 'instagram': _instagram.text.trim(),
      },
    };
    final id = await runValue(
      context,
      () => repo.savePartnerDraft(payload),
      success: submit ? null : 'Draft saved',
    );
    if (id != null && submit) {
      final submitted = await runValue(
        context,
        () => repo.submitPartnerApplication(id),
        success: 'Application submitted for review',
      );
      if (submitted == null) {
        if (mounted) setState(() => _busy = false);
        ref.invalidate(myPartnerApplicationsProvider);
        return;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(myPartnerApplicationsProvider);
    ref.invalidate(partnerWorkspaceProvider);
    if (submit && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final requirements = ref.watch(partnerRequirementsProvider);
    final applications = ref.watch(myPartnerApplicationsProvider);

    return BubblePage(
      title: 'Partner application',
      child: AsyncBody<PartnerApplicationRequirements>(
        value: requirements,
        onRetry: () => ref.invalidate(partnerRequirementsProvider),
        builder: (req) {
          final list = applications.valueOrNull ?? const <PartnerApplicationRecord>[];
          _hydrate(list);
          final current = widget.applicationId == null
              ? null
              : list.where((a) => a.id == widget.applicationId).firstOrNull;
          final locked = current != null && !current.isEditable && !current.needsInfo;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!req.isOpen)
                const GlassCard(
                  child: Text('Applications are currently closed. You can still prepare a draft.'),
                ),
              if (!req.canApply) ...[
                const SizedBox(height: 8),
                GlassCard(
                  child: Text(req.reason ?? 'You are not eligible to apply right now.'),
                ),
              ],
              const SectionHeader('Your organisation'),
              TextField(
                controller: _organization,
                enabled: !locked,
                decoration: const InputDecoration(labelText: 'Organisation / studio name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: req.categories.contains(_category) ? _category : (req.categories.isEmpty ? _category : req.categories.first),
                decoration: const InputDecoration(labelText: 'Partnership category'),
                items: [
                  for (final c in req.categories.isEmpty ? const ['Other'] : req.categories)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: locked ? null : (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _proposal,
                enabled: !locked,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Proposal',
                  helperText: 'Minimum 30 characters. Reviewed by the BubbleApp team.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                enabled: !locked,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'About your work'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _website,
                enabled: !locked,
                decoration: const InputDecoration(labelText: 'Website'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _instagram,
                enabled: !locked,
                decoration: const InputDecoration(labelText: 'Instagram URL'),
              ),
              if (current != null && current.needsInfo && current.infoRequested != null) ...[
                const SectionHeader('BubbleApp asked for more information'),
                GlassCard(child: Text(current.infoRequested!)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.reply),
                  label: const Text('Respond to the review team'),
                  onPressed: () async {
                    final response = await promptText(
                      context,
                      title: 'Respond to the review team',
                      label: 'Your answer',
                      mandatory: true,
                    );
                    if (response == null || response.isEmpty) return;
                    final ok = await runAction(
                      context,
                      () => repo_respond(ref, current.id, response),
                      success: 'Response sent',
                    );
                    if (ok) {
                      ref.invalidate(myPartnerApplicationsProvider);
                      ref.invalidate(partnerWorkspaceProvider);
                    }
                  },
                ),
              ],
              if (current != null && !current.isDecided && !locked) ...[
                const SectionHeader('Withdraw'),
                OutlinedButton.icon(
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Withdraw application'),
                  onPressed: () async {
                    final confirmed = await confirmAction(
                      context,
                      title: 'Withdraw this application?',
                      body: 'You can submit a new application after the cooldown period.',
                      confirmLabel: 'Withdraw',
                    );
                    if (!confirmed) return;
                    final ok = await runAction(
                      context,
                      () => ref
                          .read(businessPartnerRepositoryProvider)
                          .withdrawPartnerApplication(current.id),
                      success: 'Application withdrawn',
                    );
                    if (ok) {
                      ref.invalidate(myPartnerApplicationsProvider);
                      ref.invalidate(partnerRequirementsProvider);
                    }
                  },
                ),
              ],
              const SizedBox(height: 20),
              if (!locked) ...[
                GradientButton(
                  label: 'Submit for review',
                  icon: Icons.send,
                  busy: _busy,
                  onPressed: () => _saveDraft(submit: true),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save draft'),
                  onPressed: _busy ? null : () => _saveDraft(),
                ),
              ],
              const SizedBox(height: 16),
              Text(req.requirements, style: Theme.of(context).textTheme.bodySmall),
            ],
          );
        },
      ),
    );
  }

  Future<void> repo_respond(WidgetRef ref, String applicationId, String response) =>
      ref.read(businessPartnerRepositoryProvider).respondPartnerInfo(applicationId, response);
}
