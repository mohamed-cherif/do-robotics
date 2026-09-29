import 'package:flutter/material.dart';
import '../utils/execution_logger.dart';

class ExecutionLogViewer extends StatefulWidget {
  const ExecutionLogViewer({super.key});

  @override
  State<ExecutionLogViewer> createState() => _ExecutionLogViewerState();
}

class _ExecutionLogViewerState extends State<ExecutionLogViewer> {
  final ExecutionLogger _logger = ExecutionLogger();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1F2937),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: const Row(
          children: [
            Icon(Icons.bug_report, color: Color(0xFF10B981)),
            SizedBox(width: 8),
            Text(
              "Execution Log",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: () => setState(() => _logger.clear()),
            icon: const Icon(Icons.clear_all),
            tooltip: "Clear logs",
          ),
        ],
      ),
      body: StreamBuilder(
        stream: _logger.onChange,
        builder: (context, snapshot) {
          final logs = _logger.logs;
          if (logs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.terminal, size: 64, color: Color(0xFF4B5563)),
                  SizedBox(height: 16),
                  Text(
                    "No logs yet",
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Run a program to see output",
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: logs.length,
            reverse: true,
            itemBuilder: (context, index) {
              final log = logs[logs.length - 1 - index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  log,
                  style: const TextStyle(
                    color: Color(0xFFE5E7EB),
                    fontSize: 13,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
