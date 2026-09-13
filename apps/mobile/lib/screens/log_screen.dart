import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../logging/log_buffer.dart';

/// Shows everything captured in [logBuffer]: BLE scan/connect lifecycle
/// and protocol frames, GPS recording (fix accept/reject reasons,
/// permission checks), camera-proximity alerts, driving-behavior
/// detection, and uncaught errors. The "Share" button writes the full
/// log to a temp file and hands it to the OS share sheet — no computer
/// or adb needed for the common case.
///
/// This used to be a "Copy all" button putting the text straight on the
/// clipboard, but Android's clipboard IPC has a hard transaction size
/// limit (~1MB) — a real rider hit this directly: several thousand
/// lines of verbose BLE frame/GPS output blew past it, `Clipboard.setData`
/// threw, and with nothing catching it the button just silently did
/// nothing. Sharing a file has no such limit.
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

  Future<void> _shareAll() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/opentrip-debug-log.txt');
      await file.writeAsString(logBuffer.asText, flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn\'t share: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_outlined),
            tooltip: 'Share all logs',
            onPressed: logBuffer.isEmpty ? null : _shareAll,
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
                  'No logs yet. Connect a bike or record a trip — every '
                  'permission request, GPS fix, BLE frame, and camera alert '
                  'shows up here as it happens.',
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
              onPressed: _shareAll,
              icon: const Icon(Icons.ios_share_outlined),
              label: const Text('Share log'),
            ),
    );
  }
}
