import 'package:flutter/material.dart';
import '../../../widgets/common.dart';

class PollCreatorDialog extends StatefulWidget {
  const PollCreatorDialog({super.key});
  @override
  State<PollCreatorDialog> createState() => _PollCreatorDialogState();
}

class _PollCreatorDialogState extends State<PollCreatorDialog> {
  final _question = TextEditingController();
  final List<TextEditingController> _options = [TextEditingController(), TextEditingController()];
  bool _allowMultiple = false;
  bool _allowAnonymous = false;
  bool _allowChange = true;
  DateTime? _expiresAt;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Create poll'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _question, decoration: const InputDecoration(labelText: 'Question *', hintText: 'What do you think?'), maxLength: 300),
          ..._options.asMap().entries.map((e) => Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [Expanded(child: TextField(controller: e.value, decoration: InputDecoration(labelText: 'Option ${e.key + 1}'))), IconButton(icon: const Icon(Icons.close), onPressed: _options.length > 2 ? () => setState(() => _options.removeAt(e.key)) : null)]))),
          TextButton.icon(onPressed: () => setState(() => _options.add(TextEditingController())), icon: const Icon(Icons.add), label: const Text('Add option')),
          SwitchListTile(title: const Text('Allow multiple choices'), value: _allowMultiple, onChanged: (v) => setState(() => _allowMultiple = v)),
          SwitchListTile(title: const Text('Anonymous'), value: _allowAnonymous, onChanged: (v) => setState(() => _allowAnonymous = v)),
          SwitchListTile(title: const Text('Allow vote change'), value: _allowChange, onChanged: (v) => setState(() => _allowChange = v)),
          ListTile(title: const Text('Expiration'), subtitle: Text(_expiresAt == null ? 'No expiration' : _expiresAt.toString()), trailing: IconButton(icon: const Icon(Icons.calendar_today), onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 1)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 30)));
            if (d != null) setState(() => _expiresAt = d);
          })),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (_question.text.trim().isEmpty) { showMessage(context, 'Enter question'); return; }
            if (_options.where((c) => c.text.trim().isNotEmpty).length < 2) { showMessage(context, 'At least 2 options'); return; }
            Navigator.pop(context, {'question': _question.text.trim(), 'options': _options.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList(), 'allowMultiple': _allowMultiple, 'allowAnonymous': _allowAnonymous, 'allowChange': _allowChange, 'expiresAt': _expiresAt});
          }, child: const Text('Create')),
        ],
      );
}
