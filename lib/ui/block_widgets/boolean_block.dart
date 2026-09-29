import 'package:flutter/material.dart';
import '../../models/block_models.dart';
import '../logic_page.dart';
import 'input_field_widget.dart';

class BooleanBlockWidget extends StatefulWidget {
  final BlockInstance block;
  final bool isExecuting;
  final bool isPreview;
  final VoidCallback? onTap;
  final VoidCallback? onDetach; // Called when this block is successfully dropped elsewhere
  final VoidCallback? onBlockDragStarted; // Disables InteractiveViewer pan
  final VoidCallback? onBlockDragEnd;     // Re-enables InteractiveViewer pan
  final Function(String fieldId, dynamic value)? onInputChanged;

  const BooleanBlockWidget({
    super.key,
    required this.block,
    this.isExecuting = false,
    this.isPreview = false,
    this.onTap,
    this.onDetach,
    this.onBlockDragStarted,
    this.onBlockDragEnd,
    this.onInputChanged,
  });

  @override
  State<BooleanBlockWidget> createState() => _BooleanBlockWidgetState();
}

class _BooleanBlockWidgetState extends State<BooleanBlockWidget> {
  @override
  Widget build(BuildContext context) {
    if (widget.isPreview) {
      return _buildContent();
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: LongPressDraggable<BlockInstance>(
        data: widget.block,
        feedback: Material(
          color: Colors.transparent,
          child: Transform.scale(
            scale: 1.1,
            child: BooleanBlockWidget(block: widget.block, isPreview: false),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.3,
          child: _buildContent(),
        ),
        onDragStarted: () {
          widget.onBlockDragStarted?.call();
        },
        onDragCompleted: () {
          widget.onDetach?.call();
          widget.onBlockDragEnd?.call();
        },
        onDraggableCanceled: (_, _) {
          widget.onBlockDragEnd?.call();
        },
        onDragEnd: (_) {
          widget.onBlockDragEnd?.call();
        },
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    return CustomPaint(
      painter: _BooleanShapePainter(
        color: widget.block.definition.color,
        isExecuting: widget.isExecuting,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.block.definition.emoji,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(width: 6),
            Text(
              widget.block.definition.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            if (!widget.isPreview && widget.block.definition.inputs.isNotEmpty) ...[
              const SizedBox(width: 8),
              ..._buildInputsAndHybridSockets(),
            ],
            // Show nested blocks for operators only if not preview
            if (!widget.isPreview && widget.block.definition.inputs.isNotEmpty)
              ..._buildNestedSockets(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildInputsAndHybridSockets() {
    return widget.block.definition.inputs
        .where((input) => input.type != InputFieldType.blockSocket)
        .map((input) {
      
      final bool hasNestedBlock = widget.block.nestedBlocks[input.id] != null;
      final bool acceptsBlocks = input.acceptedBlockShape != null;

      Widget content;
      if (hasNestedBlock && acceptsBlocks) {
        content = Padding(
          padding: const EdgeInsets.only(left: 4.0),
          child: BooleanBlockWidget(
            block: widget.block.nestedBlocks[input.id]!,
            onInputChanged: widget.onInputChanged,
            onBlockDragStarted: widget.onBlockDragStarted,
            onBlockDragEnd: widget.onBlockDragEnd,
            onDetach: () {
              setState(() {
                widget.block.nestedBlocks[input.id] = null;
              });
            },
          ),
        );
      } else {
        content = Padding(
          padding: const EdgeInsets.only(left: 4.0),
          child: InputFieldWidget(
            input: input,
            value: widget.block.inputValues[input.id],
            onChanged: (value) {
              setState(() {
                widget.block.inputValues[input.id] = value;
              });
              widget.onInputChanged?.call(input.id, value);
            },
          ),
        );
      }

      // If it accepts blocks AND it currently DOES NOT have a nested block, 
      // wrap it in a DragTarget. 
      if (acceptsBlocks && !hasNestedBlock && !widget.isPreview) {
        return DragTarget<BlockInstance>(
          hitTestBehavior: HitTestBehavior.opaque,
          onWillAcceptWithDetails: (details) {
            return details.data.definition.shape == input.acceptedBlockShape &&
                !details.data.containsInstance(widget.block);
          },
          onAcceptWithDetails: (details) {
            LogicPage.of(context)?.removeRoot(details.data);
            setState(() {
              widget.block.nestedBlocks[input.id] = details.data;
            });
          },
          builder: (context, candidateData, rejectedData) {
            return Container(
              width: 80, // Increased to provide a larger, more forgiving hit-box for nested targets
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 2.0),
              decoration: candidateData.isNotEmpty
                  ? BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.4), // Slightly More visible highlight
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white, width: 2),
                    )
                  : BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1), // Base color to indicate dropping slot
                      borderRadius: BorderRadius.circular(6),
                    ),
              child: content,
            );
          },
        );
      }

      return content;
    }).toList();
  }

  List<Widget> _buildNestedSockets() {
    return widget.block.definition.inputs
        .where((input) => input.type == InputFieldType.blockSocket)
        .map((input) {
      final nested = widget.block.nestedBlocks[input.id];
      // Use the input's acceptedBlockShape to determine what shape is accepted.
      // Falls back to boolean if not specified.
      final acceptedShape = input.acceptedBlockShape ?? BlockShape.boolean;
      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: nested != null
            ? BooleanBlockWidget(
                block: nested,
                isExecuting: widget.isExecuting,
                onInputChanged: widget.onInputChanged,
                onBlockDragStarted: widget.onBlockDragStarted,
                onBlockDragEnd: widget.onBlockDragEnd,
                onDetach: () {
                  setState(() {
                    widget.block.nestedBlocks[input.id] = null;
                  });
                },
              )
            : DragTarget<BlockInstance>(
                hitTestBehavior: HitTestBehavior.opaque,
                onWillAcceptWithDetails: (details) =>
                    details.data.definition.shape == acceptedShape &&
                    !details.data.containsInstance(widget.block),
                onAcceptWithDetails: (details) {
                  LogicPage.of(context)?.removeRoot(details.data);
                  setState(() {
                    widget.block.nestedBlocks[input.id] = details.data;
                  });
                },
                builder: (context, candidate, rejected) {
                    return Container(
                      width: 80,
                      height: 40,
                      decoration: BoxDecoration(
                        color: candidate.isNotEmpty 
                            ? Colors.white.withValues(alpha: 0.5) 
                            : Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: candidate.isNotEmpty ? Border.all(color: Colors.white) : null,
                      ),
                    );
                },
              ),
      );
    }).toList();
  }
}

class _BooleanShapePainter extends CustomPainter {
  final Color color;
  final bool isExecuting;

  _BooleanShapePainter({required this.color, required this.isExecuting});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;

    final path = Path();
    
    // Pointed hexagon shape (like Blockly boolean)
    path.moveTo(10, 0);
    path.lineTo(size.width - 10, 0);
    path.lineTo(size.width, size.height / 2);
    path.lineTo(size.width - 10, size.height);
    path.lineTo(10, size.height);
    path.lineTo(0, size.height / 2);
    path.close();

    canvas.drawPath(path, paint);

    if (isExecuting) {
      final glowPaint = Paint()
        ..color = Colors.white
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawPath(path, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
