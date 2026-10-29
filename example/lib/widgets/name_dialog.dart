import 'package:flutter/material.dart';

/// The key of the text field in [showNameDialog], for tests.
const Key nameFieldKey = ValueKey<String>('name-field');

/// Asks for a file or folder name; returns it trimmed, or `null` when the
/// user cancels.
///
/// The confirm button stays disabled while the name is empty or contains a
/// `/`.
Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initialName = '',
}) => showDialog<String>(
  context: context,
  builder: (context) => _NameDialog(
    title: title,
    confirmLabel: confirmLabel,
    initialName: initialName,
  ),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialName,
  });

  final String title;
  final String confirmLabel;
  final String initialName;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialName,
  );

  @override
  void initState() {
    super.initState();
    // Select the name without its extension, as file managers do.
    final dot = widget.initialName.lastIndexOf('.');
    _text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: dot > 0 ? dot : widget.initialName.length,
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _isValid {
    final name = _text.text.trim();
    return name.isNotEmpty &&
        !name.contains('/') &&
        name != '.' &&
        name != '..';
  }

  void _submit() {
    if (_isValid) Navigator.of(context).pop(_text.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: nameFieldKey,
        controller: _text,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _isValid ? _submit : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
