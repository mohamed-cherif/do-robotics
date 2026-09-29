import 'package:flutter/material.dart';
import '../services/vision_preferences.dart';

/// Which objects the camera should look for, how the phone is mounted, and
/// how strict detection should be. Everything persists via VisionPreferences.
class VisionSettingsPage extends StatefulWidget {
  const VisionSettingsPage({super.key});

  @override
  State<VisionSettingsPage> createState() => _VisionSettingsPageState();
}

class _VisionSettingsPageState extends State<VisionSettingsPage> {
  Set<String> _selectedLabels = {};
  bool _upsideDown = false;
  double _confidence = VisionPreferences.defaultConfidence;
  VisionPerformance _performance = VisionPerformance.fast;
  bool _isLoading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final labels = await VisionPreferences.getEnabledLabels();
    final upsideDown = await VisionPreferences.getUpsideDown();
    final confidence = await VisionPreferences.getConfidenceThreshold();
    final performance = await VisionPreferences.getPerformance();
    if (!mounted) return;
    setState(() {
      _selectedLabels = labels;
      _upsideDown = upsideDown;
      _confidence = confidence;
      _performance = performance;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    await VisionPreferences.setEnabledLabels(_selectedLabels);
    await VisionPreferences.setUpsideDown(_upsideDown);
    await VisionPreferences.setConfidenceThreshold(_confidence);
    await VisionPreferences.setPerformance(_performance);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Vision settings saved'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = VisionPreferences.availableLabels
        .where((l) => l.contains(_search.toLowerCase()))
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        title: const Text('Vision Settings'),
        backgroundColor: const Color(0xFF1E1E2E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _card(
                        title: 'Phone mounting',
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _upsideDown,
                          onChanged: (v) => setState(() => _upsideDown = v),
                          activeTrackColor: Colors.greenAccent,
                          title: const Text('Mounted upside down',
                              style: TextStyle(color: Colors.white)),
                          subtitle: const Text(
                            'Turn on if the phone is fixed to the robot with the '
                            'top of the screen pointing at the floor, so the AI '
                            'sees the picture the right way up. If the robot then '
                            'turns the wrong way, set Smart Follow\'s steering to '
                            'REVERSED (or flip the sign in your program).',
                            style: TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _card(
                        title: 'Performance',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RadioGroup<VisionPerformance>(
                              groupValue: _performance,
                              onChanged: (v) => setState(() => _performance = v ?? _performance),
                              child: Column(
                                children: [
                                  for (final p in VisionPerformance.values)
                                    RadioListTile<VisionPerformance>(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      value: p,
                                      activeColor: Colors.greenAccent,
                                      title: Text(p.label, style: const TextStyle(color: Colors.white)),
                                      subtitle: Text(p.description,
                                          style: const TextStyle(color: Colors.white60, fontSize: 12)),
                                    ),
                                ],
                              ),
                            ),
                            const Text(
                              'Slower settings keep older or cheaper phones cool and save '
                              'battery; the robot reacts a little later.',
                              style: TextStyle(color: Colors.white60, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _card(
                        title: 'Detection sensitivity',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Minimum confidence: ${(_confidence * 100).round()}%',
                              style: const TextStyle(color: Colors.white),
                            ),
                            Slider(
                              value: _confidence,
                              min: 0.15,
                              max: 0.8,
                              divisions: 13,
                              activeColor: Colors.greenAccent,
                              onChanged: (v) => setState(() => _confidence = v),
                            ),
                            const Text(
                              'Lower = sees more (and more ghosts). Higher = only confident hits.',
                              style: TextStyle(color: Colors.white60, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _card(
                        title: 'Objects to detect',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedLabels.isEmpty
                                  ? 'Nothing selected = detect everything.'
                                  : '${_selectedLabels.length} selected. Only these will be reported.',
                              style: const TextStyle(color: Colors.white60, fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Search…',
                                hintStyle: const TextStyle(color: Colors.white38),
                                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                                isDense: true,
                                filled: true,
                                fillColor: Colors.white10,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none),
                              ),
                              onChanged: (v) => setState(() => _search = v),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: labels.map((label) {
                                final selected = _selectedLabels.contains(label);
                                return FilterChip(
                                  label: Text(label),
                                  selected: selected,
                                  selectedColor: Colors.greenAccent,
                                  checkmarkColor: Colors.black,
                                  labelStyle: TextStyle(
                                      color: selected ? Colors.black : Colors.white),
                                  backgroundColor: Colors.white10,
                                  onSelected: (v) => setState(() {
                                    if (v) {
                                      _selectedLabels.add(label);
                                    } else {
                                      _selectedLabels.remove(label);
                                    }
                                  }),
                                );
                              }).toList(),
                            ),
                            if (_selectedLabels.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: () => setState(() => _selectedLabels.clear()),
                                icon: const Icon(Icons.clear, color: Colors.redAccent, size: 18),
                                label: const Text('Clear selection',
                                    style: TextStyle(color: Colors.redAccent)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xFF1E1E2E),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Save Settings',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Card(
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
