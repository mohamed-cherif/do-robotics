import 'package:flutter/material.dart';
import '../models/tutorial_data.dart';

class TutorialDetailPage extends StatelessWidget {
  final TutorialData tutorial;

  const TutorialDetailPage({super.key, required this.tutorial});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildHeaderInfo(),
                const SizedBox(height: 32),
                _buildSectionTitle("Hardware Needed", Icons.extension),
                const SizedBox(height: 12),
                _buildPartsList(),
                const SizedBox(height: 32),
                _buildSectionTitle("The Concept", Icons.lightbulb_outline),
                const SizedBox(height: 12),
                _buildConceptBox(),
                const SizedBox(height: 32),
                _buildSectionTitle(
                    "Block Coding Steps", Icons.account_tree_outlined),
                const SizedBox(height: 16),
                _buildStepsList(),
                const SizedBox(height: 48),
                _buildCodeNowButton(context),
                const SizedBox(height: 48),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── App bar ─────────────────────────────────────────────────────────────────

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: tutorial.cardColor,
      iconTheme: const IconThemeData(color: Colors.white),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          children: [
            Positioned(
              right: -30,
              bottom: -20,
              child: Opacity(
                opacity: 0.3,
                child: Text(
                  tutorial.emoji,
                  style: const TextStyle(fontSize: 150),
                ),
              ),
            ),
            Center(
              child: Text(
                tutorial.emoji,
                style: const TextStyle(fontSize: 80),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeaderInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                tutorial.title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2937),
                ),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: tutorial.difficultyColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                tutorial.difficultyLabel,
                style: TextStyle(
                  color: tutorial.difficultyColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          tutorial.shortDescription,
          style: TextStyle(
            fontSize: 18,
            color: Colors.grey[600],
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ── Section title ───────────────────────────────────────────────────────────

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF6366F1), size: 28),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
      ],
    );
  }

  // ── Parts list ──────────────────────────────────────────────────────────────

  Widget _buildPartsList() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: tutorial.requiredParts.map((part) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    part,
                    style: const TextStyle(
                        fontSize: 16, color: Color(0xFF4B5563)),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Concept box ─────────────────────────────────────────────────────────────

  Widget _buildConceptBox() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            tutorial.cardColor.withValues(alpha: 0.1),
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: tutorial.cardColor.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Text(
        tutorial.conceptDescription,
        style: const TextStyle(
          fontSize: 16,
          color: Color(0xFF374151),
          height: 1.6,
        ),
      ),
    );
  }

  // ── Steps list ──────────────────────────────────────────────────────────────

  Widget _buildStepsList() {
    return Column(
      children: tutorial.steps.asMap().entries.map((entry) {
        final int index = entry.key;
        final TutorialStep step = entry.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 28.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Step number bubble
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    "${index + 1}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Step content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    Text(
                      step.text,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF1F2937),
                        height: 1.5,
                      ),
                    ),
                    if (step.blockPreview != null &&
                        step.blockPreview!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _buildBlockPreviewContainer(step.blockPreview!),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Visual block preview ────────────────────────────────────────────────────

  /// Wraps the block nodes in a light card container.
  Widget _buildBlockPreviewContainer(List<VisualBlockNode> nodes) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // "Block Preview" label
          Row(
            children: [
              const Icon(Icons.extension, size: 14, color: Color(0xFF94A3B8)),
              const SizedBox(width: 6),
              const Text(
                "Block Preview",
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...nodes.map((node) => _buildVisualBlock(node)),
        ],
      ),
    );
  }

  /// Recursively renders a [VisualBlockNode] as a colorful block widget that
  /// closely resembles the actual drag-and-drop blocks in the editor.
  Widget _buildVisualBlock(VisualBlockNode node) {
    final Color blockColor = node.color;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: blockColor,
          borderRadius: BorderRadius.circular(9),
          boxShadow: [
            BoxShadow(
              color: blockColor.withValues(alpha: 0.40),
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Puzzle top notch ──────────────────────────────────────────
            _buildNotch(blockColor, isTop: true),

            // ── Block face row ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(node.emoji,
                      style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      node.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  // Inline condition chip (for If/While condition slot)
                  if (node.inlineCondition != null) ...[
                    const SizedBox(width: 10),
                    _buildConditionChip(
                        node.inlineCondition!, node.chipColor),
                  ],
                ],
              ),
            ),

            // ── Body (do / then slot) ─────────────────────────────────────
            if (node.bodyNodes.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(left: 20, right: 8, bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: node.bodyNodes
                      .map((child) => _buildVisualBlock(child))
                      .toList(),
                ),
              ),

            // ── Puzzle bottom notch ───────────────────────────────────────
            _buildNotch(blockColor, isTop: false),
          ],
        ),
      ),
    );
  }

  /// Renders a small hexagonal/pill-shaped condition chip that mimics the
  /// boolean sensor blocks used in the block editor.
  Widget _buildConditionChip(String text, Color chipColor) {
    return CustomPaint(
      painter: _HexChipPainter(color: chipColor),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Paints the small puzzle-piece notch at the top or bottom of a block.
  Widget _buildNotch(Color color, {required bool isTop}) {
    return Center(
      child: CustomPaint(
        size: const Size(32, 7),
        painter: _NotchPainter(color: color, isTop: isTop),
      ),
    );
  }

  // ── CTA button ──────────────────────────────────────────────────────────────

  Widget _buildCodeNowButton(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(24),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.4),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            "Go Build It! 🚀",
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom painters
// ─────────────────────────────────────────────────────────────────────────────

/// Paints the Scratch/Blockly-style interlocking puzzle notch on statement
/// blocks.
class _NotchPainter extends CustomPainter {
  final Color color;
  final bool isTop;

  _NotchPainter({required this.color, required this.isTop});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();

    if (isTop) {
      path.moveTo(0, size.height);
      path.lineTo(size.width * 0.2, size.height);
      path.lineTo(size.width * 0.3, 0);
      path.lineTo(size.width * 0.7, 0);
      path.lineTo(size.width * 0.8, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width * 0.2, 0);
      path.lineTo(size.width * 0.3, size.height);
      path.lineTo(size.width * 0.7, size.height);
      path.lineTo(size.width * 0.8, 0);
      path.lineTo(size.width, 0);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Paints the hexagonal/pill background for inline condition chips—matching
/// the boolean block shape in the editor.
class _HexChipPainter extends CustomPainter {
  final Color color;

  _HexChipPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const r = 8.0; // side-point radius
    final path = Path()
      ..moveTo(r, 0)
      ..lineTo(size.width - r, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width - r, size.height)
      ..lineTo(r, size.height)
      ..lineTo(0, size.height / 2)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HexChipPainter old) => old.color != color;
}
