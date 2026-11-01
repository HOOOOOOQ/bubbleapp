import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/business_partner.dart';
import '../../state/business_partner_providers.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

const _businessCategories = [
  'Retail',
  'Food & drink',
  'Services',
  'Media',
  'Education',
  'Technology',
  'Health',
  'Other',
];

const _assignableRoles = ['admin', 'manager', 'support', 'operator', 'catalog', 'analyst'];

const _inquiryStatuses = ['new', 'open', 'resolved', 'closed'];
const _inquiryPriorities = ['low', 'normal', 'high'];
const _catalogStatuses = ['draft', 'published', 'out_of_stock', 'archived'];

// ---------------------------------------------------------------- overview

class BusinessWorkspaceScreen extends ConsumerWidget {
  const BusinessWorkspaceScreen({super.key, required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(businessProfileProvider(businessId));
    final setup = ref.watch(businessSetupProgressProvider(businessId));
    final mode = ref.watch(activeAccountModeProvider);

    return BubblePage(
      title: 'Business workspace',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: () {
            ref.invalidate(businessProfileProvider(businessId));
            ref.invalidate(businessSetupProgressProvider(businessId));
            ref.invalidate(businessTeamProvider(businessId));
          },
        ),
      ],
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(businessProfileProvider(businessId));
          ref.invalidate(businessSetupProgressProvider(businessId));
          ref.invalidate(myBusinessMembershipsProvider);
          ref.invalidate(activeAccountModeProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AsyncBody<BusinessProfile>(
              value: profile,
              onRetry: () => ref.invalidate(businessProfileProvider(businessId)),
              builder: (b) => GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundImage: b.logoUrl == null ? null : NetworkImage(b.logoUrl!),
                      child: b.logoUrl == null ? Text(b.name.isEmpty ? '?' : b.name[0].toUpperCase()) : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Flexible(
                            child: Text(b.name,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          ),
                          if (b.isVerified) ...[const SizedBox(width: 6), const VerifiedMark()],
                        ]),
                        Text('@${b.username} · ${b.category}'),
                        Text('${b.followersCount} followers · ${b.catalogCount} listings'),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    StatusBadge(label: b.status.isEmpty ? 'unknown' : b.status),
                    if (b.isMember && b.myRole.isNotEmpty) StatusBadge(label: b.myRole, color: Colors.teal),
                    if (b.isSetupComplete) const StatusBadge(label: 'Published')
                    else const StatusBadge(label: 'Setup incomplete', color: Colors.orange),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Public page'),
                        onPressed: () => context.push('/businesses/${b.id}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (b.myRole == 'owner' || b.can('profile.edit'))
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit'),
                          onPressed: () => context.push('/business/$businessId/edit'),
                        ),
                      ),
                  ]),
                ]),
              ),
            ),
            const SectionHeader('Setup checklist'),
            AsyncBody<BusinessSetupProgress>(
              value: setup,
              onRetry: () => ref.invalidate(businessSetupProgressProvider(businessId)),
              builder: (s) => GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  LinearProgressIndicator(value: s.percent / 100),
                  const SizedBox(height: 8),
                  Text('${s.completed}/${s.total} steps completed (${s.percent}%)'),
                  if (s.missing.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Everything the setup checklist asks for is in place.'),
                    )
                  else
                    ...s.missing.map((m) => Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(children: [
                            const Icon(Icons.radio_button_unchecked, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(m)),
                          ]),
                        )),
                ]),
              ),
            ),
            const SectionHeader('Account mode'),
            AsyncBody<ActiveAccountMode>(
              value: mode,
              onRetry: () => ref.invalidate(activeAccountModeProvider),
              builder: (m) => GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.isBusiness && m.businessId == businessId
                      ? 'This business is your active account.'
                      : 'You are acting as ${m.mode.label.toLowerCase()}.'),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.storefront_outlined),
                        label: const Text('Use business mode'),
                        onPressed: m.isBusiness && m.businessId == businessId
                            ? null
                            : () async {
                                final ok = await runAction(
                                  context,
                                  () => ref.read(businessPartnerRepositoryProvider).switchAccountMode(
                                        mode: AccountMode.business,
                                        businessId: businessId,
                                      ),
                                  success: 'Business mode is active',
                                );
                                if (ok) {
                                  ref.invalidate(activeAccountModeProvider);
                                  ref.invalidate(myBusinessesProvider);
                                }
                              },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.person_outline),
                        label: const Text('Personal mode'),
                        onPressed: !m.isBusiness
                            ? null
                            : () async {
                                final ok = await runAction(
                                  context,
                                  () => ref
                                      .read(businessPartnerRepositoryProvider)
                                      .switchAccountMode(mode: AccountMode.personal),
                                  success: 'Personal mode is active',
                                );
                                if (ok) {
                                  ref.invalidate(activeAccountModeProvider);
                                  ref.invalidate(myBusinessesProvider);
                                }
                              },
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
            const SectionHeader('Manage'),
            _WorkspaceTile(
              icon: Icons.people_outline,
              title: 'Team & roles',
              subtitle: 'Invite members, change roles and fine-tune permissions',
              onTap: () => context.push('/business/$businessId/team'),
            ),
            _WorkspaceTile(
              icon: Icons.inventory_2_outlined,
              title: 'Catalog',
              subtitle: 'Products, services, pricing and availability',
              onTap: () => context.push('/business/$businessId/catalog'),
            ),
            _WorkspaceTile(
              icon: Icons.forum_outlined,
              title: 'Customer inbox',
              subtitle: 'Real inquiries from the messaging engine',
              onTap: () => context.push('/business/$businessId/inbox'),
            ),
            _WorkspaceTile(
              icon: Icons.people_alt_outlined,
              title: 'Customers',
              subtitle: 'Internal notes, labels and follow-up status',
              onTap: () => context.push('/business/$businessId/customers'),
            ),
            _WorkspaceTile(
              icon: Icons.insights_outlined,
              title: 'Analytics',
              subtitle: 'Only metrics the platform actually records',
              onTap: () => context.push('/business/$businessId/analytics'),
            ),
            _WorkspaceTile(
              icon: Icons.verified_outlined,
              title: 'Verification',
              subtitle: 'Business blue check and decision history',
              onTap: () => context.push('/business/$businessId/verification'),
            ),
            _WorkspaceTile(
              icon: Icons.design_services_outlined,
              title: 'Messaging tools',
              subtitle: 'Labels, quick replies and business messages',
              onTap: () => context.push('/business/$businessId/messaging'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({
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

// ---------------------------------------------------------------- profile edit

class BusinessProfileEditScreen extends ConsumerStatefulWidget {
  const BusinessProfileEditScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<BusinessProfileEditScreen> createState() => _BusinessProfileEditScreenState();
}

class _BusinessProfileEditScreenState extends ConsumerState<BusinessProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _website = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _responseNote = TextEditingController();
  final _instagram = TextEditingController();
  String _category = _businessCategories.first;
  bool _showEmail = true;
  bool _showPhone = false;
  bool _listed = true;
  bool _acceptMessages = true;
  bool _busy = false;
  bool _loaded = false;

  @override
  void dispose() {
    for (final c in [_name, _description, _website, _email, _phone, _address, _responseNote, _instagram]) {
      c.dispose();
    }
    super.dispose();
  }

  void _hydrate(BusinessProfile b) {
    if (_loaded) return;
    _loaded = true;
    _name.text = b.name;
    _description.text = b.description;
    _website.text = b.website ?? '';
    _email.text = b.businessEmail ?? '';
    _phone.text = b.businessPhone ?? '';
    _address.text = b.address ?? '';
    _responseNote.text = b.responseNote ?? '';
    _instagram.text = (b.socialLinks['instagram'] ?? '').toString();
    if (_businessCategories.contains(b.category)) _category = b.category;
    _showEmail = b.visibility['show_email'] != false;
    _showPhone = b.visibility['show_phone'] == true;
    _listed = b.visibility['listed'] != false;
    _acceptMessages = b.acceptsInquiries;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    // Only send optional contact fields when they have a value: the RPC validates
    // the format of every key it receives, so an empty email must be omitted.
    final patch = <String, dynamic>{
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'category': _category,
      'accepts_inquiries': _acceptMessages,
      'social_links': {
        if (_instagram.text.trim().isNotEmpty) 'instagram': _instagram.text.trim(),
      },
      'visibility': {
        'show_email': _showEmail,
        'show_phone': _showPhone,
        'listed': _listed,
      },
    };
    final website = _website.text.trim();
    if (website.isNotEmpty) patch['website'] = website;
    final email = _email.text.trim();
    if (email.isNotEmpty) patch['business_email'] = email;
    final phone = _phone.text.trim();
    if (phone.isNotEmpty) patch['business_phone'] = phone;
    final address = _address.text.trim();
    if (address.isNotEmpty) patch['address'] = address;
    final note = _responseNote.text.trim();
    if (note.isNotEmpty) patch['response_note'] = note;
    final ok = await runAction(
      context,
      () => ref.read(businessPartnerRepositoryProvider).updateProfile(widget.businessId, patch),
      success: 'Business profile updated',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(businessProfileProvider(widget.businessId));
      ref.invalidate(businessSetupProgressProvider(widget.businessId));
      ref.invalidate(myBusinessMembershipsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(businessProfileProvider(widget.businessId));
    return BubblePage(
      title: 'Edit business',
      child: AsyncBody<BusinessProfile>(
        value: profile,
        onRetry: () => ref.invalidate(businessProfileProvider(widget.businessId)),
        builder: (b) {
          _hydrate(b);
          final canEdit = b.can('profile.edit');
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!canEdit)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('Your role cannot edit the business profile.'),
                  ),
                TextFormField(
                  controller: _name,
                  enabled: canEdit,
                  decoration: const InputDecoration(labelText: 'Business name'),
                  validator: (v) => (v ?? '').trim().length < 2 ? 'Enter a business name' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [for (final c in _businessCategories) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: canEdit ? (v) => setState(() => _category = v ?? _category) : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  enabled: canEdit,
                  maxLines: 4,
                  maxLength: 1000,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                TextFormField(
                  controller: _website,
                  enabled: canEdit,
                  decoration: const InputDecoration(labelText: 'Website'),
                  validator: (v) {
                    final text = (v ?? '').trim();
                    if (text.isEmpty) return null;
                    return text.startsWith('http://') || text.startsWith('https://')
                        ? null
                        : 'Use a full https:// URL';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  enabled: canEdit,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Business email'),
                  validator: (v) {
                    final text = (v ?? '').trim();
                    if (text.isEmpty) return null;
                    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)
                        ? null
                        : 'Enter a valid email';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  enabled: canEdit,
                  decoration: const InputDecoration(labelText: 'Business phone'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _address,
                  enabled: canEdit,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _instagram,
                  enabled: canEdit,
                  decoration: const InputDecoration(labelText: 'Instagram URL'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _responseNote,
                  enabled: canEdit,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Response note'),
                ),
                const SectionHeader('Visibility'),
                SwitchListTile(
                  value: _showEmail,
                  onChanged: canEdit ? (v) => setState(() => _showEmail = v) : null,
                  title: const Text('Show business email publicly'),
                ),
                SwitchListTile(
                  value: _showPhone,
                  onChanged: canEdit ? (v) => setState(() => _showPhone = v) : null,
                  title: const Text('Show business phone publicly'),
                ),
                SwitchListTile(
                  value: _listed,
                  onChanged: canEdit ? (v) => setState(() => _listed = v) : null,
                  title: const Text('List this business in discovery'),
                ),
                SwitchListTile(
                  value: _acceptMessages,
                  onChanged: canEdit ? (v) => setState(() => _acceptMessages = v) : null,
                  title: const Text('Accept new customer inquiries'),
                ),
                const SizedBox(height: 16),
                GradientButton(
                  label: 'Save changes',
                  icon: Icons.check,
                  busy: _busy,
                  onPressed: canEdit ? _save : null,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- team

class BusinessTeamScreen extends ConsumerWidget {
  const BusinessTeamScreen({super.key, required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(businessTeamProvider(businessId));
    return BubblePage(
      title: 'Team & roles',
      child: AsyncBody<BusinessTeam>(
        value: team,
        onRetry: () => ref.invalidate(businessTeamProvider(businessId)),
        builder: (t) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!t.canManage)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Only members with team.manage can change the team.'),
              ),
            if (t.canManage)
              GradientButton(
                label: 'Invite a teammate',
                icon: Icons.person_add_alt,
                onPressed: () => _showInviteDialog(context, ref, businessId),
              ),
            const SectionHeader('Members'),
            ...t.members.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    child: Row(children: [
                      CircleAvatar(
                        backgroundImage: m.avatarUrl == null ? null : NetworkImage(m.avatarUrl!),
                        child: m.avatarUrl == null
                            ? Text(m.displayName.isEmpty ? '?' : m.displayName[0].toUpperCase())
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Flexible(
                              child: Text(m.displayName,
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            if (m.isVerified) ...[const SizedBox(width: 4), const VerifiedMark(size: 14)],
                          ]),
                          Text('@${m.username}'),
                          Text('${m.permissions.length} permissions · ${m.status}'),
                        ]),
                      ),
                      StatusBadge(label: m.role),
                      if (t.canManage && m.role != 'owner' && m.userId != ref.watch(supabaseClientProvider).auth.currentUser?.id)
                        PopupMenuButton<String>(
                          tooltip: 'Manage member',
                          onSelected: (value) async {
                            if (value == 'remove') {
                              final confirmed = await confirmAction(
                                context,
                                title: 'Remove ${m.displayName}?',
                                body: 'They immediately lose access to the team inbox, catalog and customers.',
                                confirmLabel: 'Remove',
                              );
                              if (!confirmed) return;
                              final ok = await runAction(
                                context,
                                () => ref.read(businessPartnerRepositoryProvider).removeMember(businessId, m.userId),
                                success: 'Member removed',
                              );
                              if (ok) ref.invalidate(businessTeamProvider(businessId));
                            } else if (value.startsWith('role:')) {
                              final role = value.substring(5);
                              final ok = await runAction(
                                context,
                                () => ref
                                    .read(businessPartnerRepositoryProvider)
                                    .setMemberRole(businessId, m.userId, role),
                                success: 'Role updated to $role',
                              );
                              if (ok) ref.invalidate(businessTeamProvider(businessId));
                            } else if (value == 'permissions') {
                              await _showPermissionSheet(context, ref, businessId, t, m);
                            }
                          },
                          itemBuilder: (_) => [
                            for (final role in _assignableRoles)
                              PopupMenuItem(value: 'role:$role', child: Text('Set role: $role')),
                            const PopupMenuItem(value: 'permissions', child: Text('Custom permissions')),
                            const PopupMenuDivider(),
                            const PopupMenuItem(value: 'remove', child: Text('Remove from team')),
                          ],
                        ),
                    ]),
                  ),
                )),
            if (t.invites.isNotEmpty) ...[
              const SectionHeader('Pending invitations'),
              ...t.invites.map((i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      child: Row(children: [
                        const Icon(Icons.mail_outline),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('@${i.username} · ${i.role}'),
                            if (i.note != null && i.note!.isNotEmpty) Text(i.note!),
                          ]),
                        ),
                        if (t.canManage)
                          TextButton(
                            onPressed: () async {
                              final ok = await runAction(
                                context,
                                () => ref.read(businessPartnerRepositoryProvider).revokeInvite(i.id),
                                success: 'Invitation revoked',
                              );
                              if (ok) ref.invalidate(businessTeamProvider(businessId));
                            },
                            child: const Text('Revoke'),
                          ),
                      ]),
                    ),
                  )),
            ],
            const SectionHeader('Permission catalog'),
            Text('Roles are defaults; every member can be narrowed or extended individually.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            ...t.permissionCatalog.map((p) => ListTile(
                  dense: true,
                  title: Text(p.label),
                  subtitle: Text(p.description),
                  trailing: p.ownerOnly ? const StatusBadge(label: 'Owner only') : null,
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _showInviteDialog(BuildContext context, WidgetRef ref, String businessId) async {
    final username = TextEditingController();
    var role = 'support';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite a teammate'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: username,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'BubbleApp username', prefixText: '@'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: [for (final r in _assignableRoles) DropdownMenuItem(value: r, child: Text(r))],
            onChanged: (v) => role = v ?? role,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send invitation')),
        ],
      ),
    );
    final name = username.text.trim();
    username.dispose();
    if (result != true || name.isEmpty || !context.mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(businessPartnerRepositoryProvider).inviteMember(
            businessId: businessId,
            username: name,
            role: role,
          ),
      success: 'Invitation sent',
    );
    if (ok) ref.invalidate(businessTeamProvider(businessId));
  }

  Future<void> _showPermissionSheet(
    BuildContext context,
    WidgetRef ref,
    String businessId,
    BusinessTeam team,
    BusinessTeamMember member,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            Text('Permissions for ${member.displayName}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text('Role: ${member.role}. Overrides apply immediately.'),
            const SizedBox(height: 12),
            ...team.permissionCatalog.where((p) => !p.ownerOnly).map((p) {
              final granted = member.permissions.contains(p.key);
              return SwitchListTile(
                value: granted,
                title: Text(p.label),
                subtitle: Text(p.description),
                onChanged: (value) async {
                  final ok = await runAction(
                    context,
                    () => ref.read(businessPartnerRepositoryProvider).setMemberPermission(
                          businessId,
                          member.userId,
                          p.key,
                          granted: value,
                        ),
                    success: value ? '${p.label} granted' : '${p.label} revoked',
                  );
                  if (ok) {
                    ref.invalidate(businessTeamProvider(businessId));
                    if (ctx.mounted) Navigator.pop(ctx);
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- catalog

class BusinessCatalogScreen extends ConsumerStatefulWidget {
  const BusinessCatalogScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<BusinessCatalogScreen> createState() => _BusinessCatalogScreenState();
}

class _BusinessCatalogScreenState extends ConsumerState<BusinessCatalogScreen> {
  String? _status;

  @override
  Widget build(BuildContext context) {
    final query = CatalogQuery(widget.businessId, status: _status);
    final items = ref.watch(businessCatalogProvider(query));
    final profile = ref.watch(businessProfileProvider(widget.businessId)).valueOrNull;
    final canManage = profile?.can('catalog.manage') ?? false;

    return BubblePage(
      title: 'Catalog',
      actions: [
        if (canManage)
          IconButton(
            tooltip: 'Add listing',
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/business/${widget.businessId}/catalog/new'),
          ),
      ],
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(spacing: 8, children: [
            ChoiceChip(
              label: const Text('All'),
              selected: _status == null,
              onSelected: (_) => setState(() => _status = null),
            ),
            for (final s in _catalogStatuses)
              ChoiceChip(
                label: Text(s.replaceAll('_', ' ')),
                selected: _status == s,
                onSelected: (_) => setState(() => _status = s),
              ),
          ]),
        ),
        Expanded(
          child: AsyncBody<List<BusinessCatalogItem>>(
            value: items,
            onRetry: () => ref.invalidate(businessCatalogProvider(query)),
            builder: (list) {
              if (list.isEmpty) {
                return const EmptyState(message: 'No listings for this filter yet.', icon: Icons.inventory_2_outlined);
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final item = list[i];
                  return GlassCard(
                    onTap: () => context.push('/business/${widget.businessId}/catalog/${item.id}'),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        StatusBadge(
                          label: item.status.replaceAll('_', ' '),
                          color: item.isPublished ? Colors.green : Colors.orange,
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text('${item.kind}${item.category.isEmpty ? '' : ' · ${item.category}'}'),
                      if (item.priceLabel != null) Text(item.priceLabel!),
                      Text('${item.viewCount} views · ${item.shareCount} shares'),
                    ]),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

class BusinessCatalogEditorScreen extends ConsumerStatefulWidget {
  const BusinessCatalogEditorScreen({super.key, required this.businessId, this.itemId});

  final String businessId;
  final String? itemId;

  @override
  ConsumerState<BusinessCatalogEditorScreen> createState() => _BusinessCatalogEditorScreenState();
}

class _BusinessCatalogEditorScreenState extends ConsumerState<BusinessCatalogEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _category = TextEditingController();
  final _price = TextEditingController();
  final _currency = TextEditingController(text: 'IDR');
  final _stock = TextEditingController();
  final _externalUrl = TextEditingController();
  final _imageUrl = TextEditingController();
  final _gallery = TextEditingController();
  String _kind = 'product';
  String _status = 'draft';
  bool _busy = false;
  bool _hydrated = false;

  @override
  void dispose() {
    for (final c in [_name, _description, _category, _price, _currency, _stock, _externalUrl, _imageUrl, _gallery]) {
      c.dispose();
    }
    super.dispose();
  }

  void _hydrate(BusinessCatalogItem item) {
    if (_hydrated) return;
    _hydrated = true;
    _name.text = item.name;
    _description.text = item.description;
    _category.text = item.category;
    _price.text = item.priceMinor == null ? '' : (item.priceMinor! / 100).toString();
    _currency.text = item.currency;
    _stock.text = item.stockQuantity?.toString() ?? '';
    _externalUrl.text = item.externalUrl ?? '';
    _imageUrl.text = item.imageUrl ?? '';
    _gallery.text = item.gallery.join(', ');
    _kind = item.kind;
    _status = item.status;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final priceText = _price.text.trim();
    final stockText = _stock.text.trim();
    final draft = CatalogDraft(
      itemId: widget.itemId,
      kind: _kind,
      name: _name.text,
      description: _description.text,
      category: _category.text.trim().isEmpty ? null : _category.text.trim(),
      priceMinor: priceText.isEmpty ? null : (double.tryParse(priceText)! * 100).round(),
      currency: _currency.text.trim().toUpperCase(),
      imageUrl: _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
      gallery: _gallery.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      status: _status,
      stockQuantity: stockText.isEmpty ? null : int.tryParse(stockText),
      externalUrl: _externalUrl.text.trim().isEmpty ? null : _externalUrl.text.trim(),
    );
    final id = await runValue(
      context,
      () => ref.read(businessPartnerRepositoryProvider).saveCatalogItem(widget.businessId, draft),
      success: 'Listing saved',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (id != null) {
      ref.invalidate(businessCatalogProvider(CatalogQuery(widget.businessId)));
      ref.invalidate(businessSetupProgressProvider(widget.businessId));
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemId == null) {
      return BubblePage(
        title: 'New listing',
        child: _form(context, null),
      );
    }
    final detail = ref.watch(catalogDetailProvider(widget.itemId!));
    return BubblePage(
      title: 'Edit listing',
      child: AsyncBody<CatalogDetail>(
        value: detail,
        onRetry: () => ref.invalidate(catalogDetailProvider(widget.itemId!)),
        builder: (d) {
          _hydrate(d.item);
          return _form(context, d.item);
        },
      ),
    );
  }

  Widget _form(BuildContext context, BusinessCatalogItem? item) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _kind,
            decoration: const InputDecoration(labelText: 'Type'),
            items: const [
              DropdownMenuItem(value: 'product', child: Text('Product')),
              DropdownMenuItem(value: 'service', child: Text('Service')),
            ],
            onChanged: (v) => setState(() => _kind = v ?? _kind),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            maxLines: 3,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          TextFormField(
            controller: _category,
            decoration: const InputDecoration(labelText: 'Category'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Price'),
                validator: (v) {
                  final text = (v ?? '').trim();
                  if (text.isEmpty) return null;
                  return double.tryParse(text) == null ? 'Numbers only' : null;
                },
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: TextFormField(
                controller: _currency,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Currency'),
                validator: (v) =>
                    RegExp(r'^[A-Za-z]{3}$').hasMatch((v ?? '').trim()) ? null : '3 letters',
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _stock,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Stock quantity (optional)'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _externalUrl,
            decoration: const InputDecoration(labelText: 'External link (optional)'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _imageUrl,
            decoration: const InputDecoration(labelText: 'Main image URL'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _gallery,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Gallery URLs',
              helperText: 'Comma separated; up to 10 images',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: [
              for (final s in _catalogStatuses)
                DropdownMenuItem(value: s, child: Text(s.replaceAll('_', ' '))),
            ],
            onChanged: (v) => setState(() => _status = v ?? _status),
          ),
          const SizedBox(height: 20),
          GradientButton(label: 'Save listing', icon: Icons.check, busy: _busy, onPressed: _save),
          if (item != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete listing'),
              onPressed: () async {
                final confirmed = await confirmAction(
                  context,
                  title: 'Delete this listing?',
                  body: 'The listing is removed from the catalog. Archive it instead if you want to keep the history.',
                  confirmLabel: 'Delete',
                );
                if (!confirmed) return;
                final ok = await runAction(
                  context,
                  () => ref.read(businessPartnerRepositoryProvider).deleteCatalogItem(item.id),
                  success: 'Listing deleted',
                );
                if (!ok) return;
                ref.invalidate(businessCatalogProvider(CatalogQuery(widget.businessId)));
                if (context.mounted) context.pop();
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- inbox

class BusinessInboxScreen extends ConsumerStatefulWidget {
  const BusinessInboxScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<BusinessInboxScreen> createState() => _BusinessInboxScreenState();
}

class _BusinessInboxScreenState extends ConsumerState<BusinessInboxScreen> {
  String? _status;

  @override
  Widget build(BuildContext context) {
    final args = (widget.businessId, _status);
    final inquiries = ref.watch(businessInquiriesProvider(args));
    return BubblePage(
      title: 'Customer inbox',
      child: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            ChoiceChip(
              label: const Text('All'),
              selected: _status == null,
              onSelected: (_) => setState(() => _status = null),
            ),
            for (final s in _inquiryStatuses) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(s),
                selected: _status == s,
                onSelected: (_) => setState(() => _status = s),
              ),
            ],
          ]),
        ),
        Expanded(
          child: AsyncBody<List<BusinessInquiry>>(
            value: inquiries,
            onRetry: () => ref.invalidate(businessInquiriesProvider(args)),
            builder: (list) {
              if (list.isEmpty) {
                return const EmptyState(
                  message: 'No inquiries yet. Customer messages from your listings land here.',
                  icon: Icons.forum_outlined,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final inquiry = list[i];
                  return GlassCard(
                    onTap: () => context.push('/business/${widget.businessId}/inbox/${inquiry.id}'),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(inquiry.customerName,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        StatusBadge(
                          label: inquiry.status,
                          color: inquiry.isOpen ? Colors.blue : Colors.green,
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text(inquiry.subject),
                      if (inquiry.lastMessage != null)
                        Text(
                          inquiry.lastMessage!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, children: [
                        StatusBadge(label: inquiry.priority, color: Colors.orange),
                        Text('${inquiry.messageCount} messages'),
                        if (inquiry.catalogItemName != null) Text(inquiry.catalogItemName!),
                      ]),
                    ]),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

class BusinessInquiryScreen extends ConsumerWidget {
  const BusinessInquiryScreen({super.key, required this.businessId, required this.inquiryId});

  final String businessId;
  final String inquiryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(inquiryDetailProvider(inquiryId));
    return BubblePage(
      title: 'Inquiry',
      child: AsyncBody<BusinessInquiryDetail>(
        value: detail,
        onRetry: () => ref.invalidate(inquiryDetailProvider(inquiryId)),
        builder: (d) {
          final i = d.inquiry;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(i.customerName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                    if (i.customerVerified) const VerifiedMark(),
                  ]),
                  Text('@${i.customerUsername} · ${i.subject}'),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    StatusBadge(label: i.status),
                    StatusBadge(label: i.priority, color: Colors.orange),
                    Text('${i.messageCount} messages'),
                  ]),
                  if (i.firstResponseAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('First response: ${i.firstResponseAt}'),
                    ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Open conversation'),
                        onPressed: i.conversationId.isEmpty
                            ? null
                            : () => context.push('/chats/${i.conversationId}'),
                      ),
                    ),
                  ]),
                ]),
              ),
              if (d.customerRecord != null) ...[
                const SectionHeader('Customer record'),
                GlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Follow-up: ${d.customerRecord!.followUpStatus}'),
                    Text('Inquiries: ${d.customerRecord!.inquiryCount} · open ${d.customerRecord!.openInquiries}'),
                    if (d.customerRecord!.internalNote.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('Note: ${d.customerRecord!.internalNote}'),
                      ),
                  ]),
                ),
              ],
              if (i.canManage) ...[
                const SectionHeader('Manage'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final status in _inquiryStatuses)
                    OutlinedButton(
                      onPressed: status == i.status
                          ? null
                          : () async {
                              final ok = await runAction(
                                context,
                                () => ref
                                    .read(businessPartnerRepositoryProvider)
                                    .setInquiryStatus(i.id, status),
                                success: 'Inquiry moved to $status',
                              );
                              if (ok) {
                                ref.invalidate(inquiryDetailProvider(inquiryId));
                                ref.invalidate(businessInquiriesProvider((businessId, null)));
                              }
                            },
                      child: Text('Mark $status'),
                    ),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final priority in _inquiryPriorities)
                    OutlinedButton(
                      onPressed: priority == i.priority
                          ? null
                          : () async {
                              final ok = await runAction(
                                context,
                                () => ref
                                    .read(businessPartnerRepositoryProvider)
                                    .setInquiryPriority(i.id, priority),
                                success: 'Priority set to $priority',
                              );
                              if (ok) ref.invalidate(inquiryDetailProvider(inquiryId));
                            },
                      child: Text('Priority: $priority'),
                    ),
                ]),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- customers

class BusinessCustomersScreen extends ConsumerStatefulWidget {
  const BusinessCustomersScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<BusinessCustomersScreen> createState() => _BusinessCustomersScreenState();
}

class _BusinessCustomersScreenState extends ConsumerState<BusinessCustomersScreen> {
  final _search = TextEditingController();
  String? _query;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = (widget.businessId, _query);
    final customers = ref.watch(businessCustomersProvider(args));
    final labels = ref.watch(businessLabelsProvider(widget.businessId)).valueOrNull ?? const [];

    return BubblePage(
      title: 'Customers',
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: 'Search customers',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _search.clear();
                  setState(() => _query = null);
                },
              ),
            ),
            onSubmitted: (v) => setState(() => _query = v.trim().isEmpty ? null : v.trim()),
          ),
        ),
        Expanded(
          child: AsyncBody<List<BusinessCustomer>>(
            value: customers,
            onRetry: () => ref.invalidate(businessCustomersProvider(args)),
            builder: (list) {
              if (list.isEmpty) {
                return const EmptyState(
                  message: 'Customers appear here after their first inquiry.',
                  icon: Icons.people_alt_outlined,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final c = list[index];
                  return GlassCard(
                    onTap: () => _openCustomer(context, ref, c, labels),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(c.displayName,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        if (c.isVerified) const VerifiedMark(size: 14),
                        StatusBadge(label: c.followUpStatus.replaceAll('_', ' ')),
                      ]),
                      Text('@${c.username}'),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final label in c.labels)
                          StatusBadge(label: label.name, color: _hexColor(label.color)),
                        Text('${c.inquiryCount} inquiries'),
                      ]),
                    ]),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  Future<void> _openCustomer(
    BuildContext context,
    WidgetRef ref,
    BusinessCustomer customer,
    List<CustomerLabel> labels,
  ) async {
    final noteController = TextEditingController(text: customer.internalNote);
    var followUp = customer.followUpStatus;
    final selected = customer.labels.map((l) => l.id).toSet();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(customer.displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text('@${customer.username}'),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Internal note (never shown to the customer)'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: followUp,
                decoration: const InputDecoration(labelText: 'Follow-up status'),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('No follow-up')),
                  DropdownMenuItem(value: 'follow_up', child: Text('Follow up')),
                  DropdownMenuItem(value: 'waiting', child: Text('Waiting on customer')),
                  DropdownMenuItem(value: 'closed', child: Text('Closed')),
                ],
                onChanged: (v) => setSheetState(() => followUp = v ?? followUp),
              ),
              const SizedBox(height: 12),
              const Text('Labels'),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final label in labels)
                  FilterChip(
                    label: Text(label.name),
                    selected: selected.contains(label.id),
                    onSelected: (on) => setSheetState(() {
                      if (on) {
                        selected.add(label.id);
                      } else {
                        selected.remove(label.id);
                      }
                    }),
                  ),
              ]),
              const SizedBox(height: 16),
              GradientButton(
                label: 'Save customer',
                icon: Icons.check,
                onPressed: () async {
                  final ok = await runAction(
                    ctx,
                    () async {
                      final repo = ref.read(businessPartnerRepositoryProvider);
                      await repo.updateCustomer(customer.id, {
                        'internal_note': noteController.text.trim(),
                        'follow_up_status': followUp,
                      });
                      await repo.setCustomerLabels(customer.id, selected.toList());
                    },
                    success: 'Customer updated',
                  );
                  if (ok && ctx.mounted) Navigator.pop(ctx, true);
                },
              ),
            ]),
          ),
        ),
      ),
    );
    noteController.dispose();
    if (saved == true) {
      ref.invalidate(businessCustomersProvider((widget.businessId, _query)));
    }
  }
}


// ---------------------------------------------------------------- public page

/// Public business page used by visitors. Views are recorded as real events so
/// the owner's analytics reflect actual traffic.
class BusinessPublicProfileScreen extends ConsumerStatefulWidget {
  const BusinessPublicProfileScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<BusinessPublicProfileScreen> createState() => _BusinessPublicProfileScreenState();
}

class _BusinessPublicProfileScreenState extends ConsumerState<BusinessPublicProfileScreen> {
  bool _recorded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_recorded) return;
      _recorded = true;
      try {
        await ref.read(businessPartnerRepositoryProvider).recordView(widget.businessId);
      } catch (_) {
        // A view counter must never block the page.
      }
    });
  }

  Future<void> _message(BusinessProfile business, {String? catalogItemId}) async {
    final controller = TextEditingController();
    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Message ${business.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          maxLength: 4000,
          decoration: const InputDecoration(labelText: 'Your message'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    final text = controller.text.trim();
    controller.dispose();
    if (sent != true || text.isEmpty || !mounted) return;
    final result = await runValue(
      context,
      () => ref.read(businessPartnerRepositoryProvider).startInquiry(
            businessId: widget.businessId,
            message: text,
            catalogItemId: catalogItemId,
          ),
      success: 'Message sent',
    );
    if (result == null || !mounted) return;
    ref.invalidate(myBusinessInquiriesProvider);
    context.push('/chats/${result.conversationId}');
  }

  void _showItemSheet(BuildContext context, BusinessProfile business, BusinessCatalogItem item) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          if (item.category.isNotEmpty) Text(item.category),
          if (item.priceLabel != null) ...[
            const SizedBox(height: 6),
            Text(item.priceLabel!, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
          if (item.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(item.description),
          ],
          if (item.stockQuantity != null) ...[
            const SizedBox(height: 6),
            Text('Availability: ${item.stockQuantity}'),
          ],
          if (item.gallery.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: item.gallery.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, index) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(item.gallery[index], width: 80, height: 80, fit: BoxFit.cover),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (business.acceptsInquiries && business.status != 'closed')
            GradientButton(
              label: 'Ask about this item',
              icon: Icons.chat_bubble_outline,
              onPressed: () {
                Navigator.pop(ctx);
                _message(business, catalogItemId: item.id);
              },
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(businessPublicProfileProvider(widget.businessId));
    final query = CatalogQuery(widget.businessId, publicOnly: true);
    final catalog = ref.watch(businessCatalogProvider(query));
    return BubblePage(
      title: 'Business',
      child: AsyncBody<BusinessProfile>(
        value: profile,
        onRetry: () => ref.invalidate(businessPublicProfileProvider(widget.businessId)),
        builder: (b) {
          if (!b.isSetupComplete && !b.isMember) {
            return const EmptyState(
              message: 'This business has not published its profile yet.',
              icon: Icons.storefront_outlined,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (b.coverUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(b.coverUrl!, height: 140, fit: BoxFit.cover),
                ),
              const SizedBox(height: 12),
              Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage: b.logoUrl == null ? null : NetworkImage(b.logoUrl!),
                  child: b.logoUrl == null ? Text(b.name.isEmpty ? '?' : b.name[0].toUpperCase()) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(
                        child: Text(b.name,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      ),
                      if (b.isVerified) ...[const SizedBox(width: 6), const VerifiedMark()],
                    ]),
                    Text('@${b.username} · ${b.category}'),
                    Text('${b.followersCount} followers · ${b.catalogCount} listings'),
                  ]),
                ),
              ]),
              if (b.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(b.description),
              ],
              if (b.responseNote != null) ...[
                const SizedBox(height: 6),
                Text(b.responseNote!, style: Theme.of(context).textTheme.bodySmall),
              ],
              if (b.socialLinks.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final entry in b.socialLinks.entries)
                    Chip(label: Text('${entry.key}: ${entry.value}')),
                ]),
              ],
              if (b.workingHours.isNotEmpty) ...[
                const SectionHeader('Opening hours'),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in b.workingHours.entries)
                        Text('${entry.key}: ${entry.value}'),
                    ],
                  ),
                ),
              ],
              if (b.businessEmail != null || b.businessPhone != null || b.address != null) ...[
                const SectionHeader('Contact'),
                GlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (b.businessEmail != null) SelectableText(b.businessEmail!),
                    if (b.businessPhone != null) SelectableText(b.businessPhone!),
                    if (b.address != null) Text(b.address!),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              if (!b.isMember)
                GradientButton(
                  label: b.isFollowing ? 'Following' : 'Follow business',
                  icon: b.isFollowing ? Icons.check : Icons.person_add_alt,
                  onPressed: () async {
                    final ok = await runAction(
                      context,
                      () => ref
                          .read(businessPartnerRepositoryProvider)
                          .followBusiness(b.id, !b.isFollowing),
                      success: b.isFollowing ? 'Unfollowed' : 'Following ${b.name}',
                    );
                    if (ok) ref.invalidate(businessPublicProfileProvider(b.id));
                  },
                ),
              const SizedBox(height: 8),
              if (b.isMember)
                OutlinedButton.icon(
                  icon: const Icon(Icons.dashboard_outlined),
                  label: const Text('Open workspace'),
                  onPressed: () => context.push('/business/${b.id}/workspace'),
                )
              else if (b.acceptsInquiries && b.status != 'closed')
                GradientButton(
                  label: 'Message business',
                  icon: Icons.chat_bubble_outline,
                  onPressed: () => _message(b),
                )
              else
                const Text('This business is not accepting messages right now.'),
              const SectionHeader('Catalog'),
              AsyncBody<List<BusinessCatalogItem>>(
                value: catalog,
                onRetry: () => ref.invalidate(businessCatalogProvider(query)),
                builder: (items) {
                  if (items.isEmpty) {
                    return const EmptyState(
                      message: 'No published listings yet.',
                      icon: Icons.inventory_2_outlined,
                    );
                  }
                  return Column(children: [
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GlassCard(
                          onTap: () => b.isMember
                              ? context.push('/business/${b.id}/catalog/${item.id}')
                              : _showItemSheet(context, b, item),
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                if (item.category.isNotEmpty) Text(item.category),
                                if (item.priceLabel != null) Text(item.priceLabel!),
                              ]),
                            ),
                            const Icon(Icons.chevron_right),
                          ]),
                        ),
                      ),
                  ]);
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

Color _hexColor(String hex) {
  final cleaned = hex.replaceAll('#', '');
  final value = int.tryParse(cleaned, radix: 16);
  return value == null ? Colors.blue : Color(0xFF000000 | value);
}

// ---------------------------------------------------------------- analytics

class BusinessAnalyticsScreen extends ConsumerStatefulWidget {
  const BusinessAnalyticsScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<BusinessAnalyticsScreen> createState() => _BusinessAnalyticsScreenState();
}

class _BusinessAnalyticsScreenState extends ConsumerState<BusinessAnalyticsScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final args = (widget.businessId, _days);
    final analytics = ref.watch(businessAnalyticsProvider(args));
    return BubblePage(
      title: 'Business analytics',
      actions: [
        PopupMenuButton<int>(
          tooltip: 'Period',
          icon: const Icon(Icons.calendar_range),
          onSelected: (value) => setState(() => _days = value),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 7, child: Text('Last 7 days')),
            PopupMenuItem(value: 30, child: Text('Last 30 days')),
            PopupMenuItem(value: 90, child: Text('Last 90 days')),
          ],
        ),
      ],
      child: AsyncBody<BusinessAnalytics>(
        value: analytics,
        onRetry: () => ref.invalidate(businessAnalyticsProvider(args)),
        builder: (a) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Last ${a.periodDays} days', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _MetricGrid(
              entries: [
                ('Profile views', a.metric('profile_views')),
                ('Catalog views', a.metric('catalog_views')),
                ('Inquiries', a.metric('inquiries')),
                ('New customers', a.metric('new_customers')),
                ('Followers', a.metric('followers')),
                ('Published listings', a.metric('published_items')),
              ],
            ),
            const SectionHeader('Response performance'),
            GlassCard(
              child: a.response.available
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Answered: ${a.response.answered}'),
                      Text('Unanswered: ${a.response.unanswered}'),
                      if (a.response.avgFirstResponseMinutes != null)
                        Text('Average first response: ${a.response.avgFirstResponseMinutes!.toStringAsFixed(1)} min'),
                      if (a.response.resolutionRate != null)
                        Text('Resolution rate: ${a.response.resolutionRate!.toStringAsFixed(1)}%'),
                    ])
                  : const Text('Not enough answered inquiries yet — the rate appears after the first reply.'),
            ),
            const SectionHeader('Daily activity'),
            GlassCard(
              child: Column(children: [
                for (final point in a.series)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      SizedBox(width: 92, child: Text(point.day, style: Theme.of(context).textTheme.bodySmall)),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: _ratio(point.catalogViews + point.profileViews, a.series),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${point.profileViews + point.catalogViews}'),
                    ]),
                  ),
              ]),
            ),
            if (a.unavailable.isNotEmpty) ...[
              const SectionHeader('Not available yet'),
              GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('These metrics need integrations that are not part of this release:'),
                  const SizedBox(height: 6),
                  ...a.unavailable.map((row) => Text('• ${row['metric'] ?? row['key']}: ${row['reason'] ?? 'not implemented'}')),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  double _ratio(int value, List<AnalyticsPoint> series) {
    var max = 0;
    for (final p in series) {
      final total = p.profileViews + p.catalogViews;
      if (total > max) max = total;
    }
    if (max == 0) return 0;
    return (value / max).clamp(0, 1).toDouble();
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.entries});

  final List<(String, int)> entries;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final entry in entries)
            SizedBox(
              width: 160,
              child: GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${entry.$2}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  Text(entry.$1, style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ),
        ],
      );
}

// ---------------------------------------------------------------- verification

class BusinessVerificationScreen extends ConsumerWidget {
  const BusinessVerificationScreen({super.key, required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(businessVerificationProvider(businessId));
    return BubblePage(
      title: 'Business verification',
      child: AsyncBody<BusinessVerificationState>(
        value: state,
        onRetry: () => ref.invalidate(businessVerificationProvider(businessId)),
        builder: (s) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.verified_outlined),
                  const SizedBox(width: 8),
                  Text(s.isVerified ? 'Verified business' : 'Not verified yet',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (s.isVerified) ...[const SizedBox(width: 6), const VerifiedMark()],
                ]),
                if (s.application != null) ...[
                  const SizedBox(height: 8),
                  Text('Latest application: ${s.status}'),
                  if (s.decisionNote.isNotEmpty) Text('Reviewer note: ${s.decisionNote}'),
                ] else
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Submit the business verification form to request the blue check.'),
                  ),
                const SizedBox(height: 12),
                if (s.canSubmit)
                  GradientButton(
                    label: 'Start verification',
                    icon: Icons.arrow_forward,
                    onPressed: () => context.push('/verification/apply/business?id=$businessId'),
                  )
                else
                  const Text('A new application becomes available when the current one is decided.'),
              ]),
            ),
            const SectionHeader('Requirements'),
            GlassCard(
              child: Text(
                (s.requirements['summary'] ?? 'Business name, category, contact details and a reason for verification.').toString(),
              ),
            ),
            const SectionHeader('Decision history'),
            if (s.history.isEmpty)
              const EmptyState(message: 'No verification events yet.', icon: Icons.history)
            else
              ...s.history.map((e) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.timeline),
                    title: Text('${e.action} → ${e.toStatus}'),
                    subtitle: Text([
                      if (e.fromStatus != null) 'from ${e.fromStatus}',
                      if (e.note != null && e.note!.isNotEmpty) e.note!,
                      if (e.createdAt != null) '${e.createdAt}',
                    ].join(' · ')),
                  )),
          ],
        ),
      ),
    );
  }
}
