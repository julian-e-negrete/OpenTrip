import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logging/log_buffer.dart';

/// Shows everything captured in [logBuffer]: BLE scan/connect lifecycle,
/// every protocol frame sent/received (hex + decoded name), handshake
/// progress, and uncaught errors. The "Copy all" button puts the full log
/// on the clipboard so it can be pasted straight into a chat/issue from
/// the phone — no computer or adb needed for the common case.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    logBuffer.addListener(_onLogsChanged);
  }

  @override
  void dispose() {
    logBuffer.removeListener(_onLogsChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onLogsChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: logBuffer.asText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logs copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: 'Copy all logs',
            onPressed: logBuffer.isEmpty ? null : _copyAll,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear logs',
            onPressed: logBuffer.isEmpty ? null : () => setState(logBuffer.clear),
          ),
        ],
      ),
      body: logBuffer.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No logs yet. Go back and tap "Scan & connect" — every '
                  'permission request, scan result, and BLE frame sent or '
                  'received will show up here as it happens.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              child: SelectableText(
                logBuffer.asText,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.4),
              ),
            ),
      floatingActionButton: logBuffer.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _copyAll,
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('Copy all'),
            ),
    );
  }
}
