import 'package:flutter/material.dart';
import '../../models/block_models.dart';
import 'input_field_widget.dart';
import 'boolean_block.dart';
import '../logic_page.dart'; // To access removeRoot

class StatementBlockWidget extends StatefulWidget {
  final BlockInstance block;
  final bool isExecuting;
  final bool isPreview;
  final VoidCallback? onTap;
  final Function(String fieldId, dynamic value)? onInputChanged;
  final VoidCallback? onDetach; // Called when this block is successfully dropped elsewhere
  final VoidCallback? onBlockDragStarted; // Disables InteractiveViewer pan
  final VoidCallback? onBlockDragEnd;     // Re-enables InteractiveViewer pan

  const StatementBlockWidget({
    super.key,
    required this.block,
    this.isExecuting = false,
    this.isPreview = false,
    this.onTap,
    this.onInputChanged,
    this.onDetach,
    this.onBlockDragStarted,
    this.onBlockDragEnd,
  });

  @override
  State<StatementBlockWidget> createState() => _StatementBlockWidgetState();
}

class _StatementBlockWidgetState extends State<StatementBlockWidget> {
  @override
  Widget build(BuildContext context) {
    if (widget.isPreview) {
      return _buildBlockContent();
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LongPressDraggable<BlockInstance>(
            data: widget.block,
            feedback: Material(
              color: Colors.transparent,
              child: Transform.scale(
                scale: 1.1,
                child: StatementBlockWidget(block: widget.block, isPreview: false),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.3,
              child: _buildBlockBody(),
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
            child: _buildBlockContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockContent() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBlockBody(),
          if (!widget.isPreview)
              // Recursive chain
              if (widget.block.nextBlock != null)
                StatementBlockWidget(
                  block: widget.block.nextBlock!,
                  isExecuting: widget.isExecuting,
                  onInputChanged: widget.onInputChanged,
                  onBlockDragStarted: widget.onBlockDragStarted,
                  onBlockDragEnd: widget.onBlockDragEnd,
                  onDetach: () {
                    setState(() {
                      widget.block.nextBlock = null;
                    });
                  },
                )
              else
                // Drop zone for next block
                DragTarget<BlockInstance>(
                  onWillAcceptWithDetails: (details) =>
                      details.data.definition.shape == BlockShape.statement &&
                      !details.data.containsInstance(widget.block),
                  onAcceptWithDetails: (details) {
                    // Remove from roots if it was a root
                    LogicPage.of(context)?.removeRoot(details.data);
                    
                    setState(() {
                      widget.block.nextBlock = details.data;
                    });
                  },
                  builder: (context, candidates, _) {
                     return Container(
                       height: candidates.isNotEmpty ? 60 : 40, // Increased hit zone
                       width: 150, // Increased width
                       margin: const EdgeInsets.only(left: 20),
                       decoration: candidates.isNotEmpty ? BoxDecoration(
                         color: Colors.green.withValues(alpha: 0.3),
                         borderRadius: BorderRadius.circular(8)
                       ) : BoxDecoration(
                         color: Colors.transparent, // Transparent hit zone
                       ),
                     );
                  },
                ),
        ],
      );
  }

  Widget _buildBlockBody() {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      decoration: BoxDecoration(
        color: widget.block.definition.color,
        borderRadius: BorderRadius.circular(8),
        border: widget.isExecuting ? Border.all(color: Colors.white, width: 3) : null,
        boxShadow: [
          BoxShadow(
            color: widget.block.definition.color.withValues(alpha: 0.3),
            blurRadius: widget.isExecuting ? 16 : 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top notch
          Center(child: _buildTopNotch()),
          
          // Block content
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  widget.block.definition.emoji,
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.block.definition.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        if (!widget.isPreview && widget.block.definition.inputs.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          ..._buildInputsAndHybridSockets(),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (!widget.isPreview) ..._buildNestedBlocks(),

          // Bottom notch
          Center(child: _buildBottomNotch()),
        ],
      ),
    );
  }
  
  // Keep _buildTopNotch, _buildBottomNotch, _buildInputs as is...
  // I need to include them in the replace call if I replaced everything.

  Widget _buildTopNotch() {
    return CustomPaint(
      size: const Size(30, 6),
      painter: _NotchPainter(
        color: widget.block.definition.color.withValues(alpha: 0.5),
        isTop: true,
      ),
    );
  }

  Widget _buildBottomNotch() {
    return CustomPaint(
      size: const Size(30, 6),
      painter: _NotchPainter(
        color: widget.block.definition.color,
        isTop: false,
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
        // If there's a nested block, hide the text input and show the block
        content = Padding(
          padding: const EdgeInsets.only(left: 4.0),
          child: _buildNestedBlockWidget(input.id, widget.block.nestedBlocks[input.id]!),
        );
      } else {
        // Render standard input
        content = InputFieldWidget(
          input: input,
          value: widget.block.inputValues[input.id],
          onChanged: (value) {
            setState(() {
              widget.block.inputValues[input.id] = value;
            });
            widget.onInputChanged?.call(input.id, value);
          },
        );
      }

      // If it accepts blocks AND it currently DOES NOT have a nested block, 
      // wrap it in a DragTarget. If it already has a nested block, the nested 
      // block itself handles the drag targets for its own inner sockets.
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

      // Otherwise just return the input
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0),
        child: content,
      );
    }).toList();
  }

  Widget _buildNestedBlockWidget(String inputId, BlockInstance nestedBlock) {
    return BooleanBlockWidget(
      block: nestedBlock,
      onInputChanged: widget.onInputChanged,
      onBlockDragStarted: widget.onBlockDragStarted,
      onBlockDragEnd: widget.onBlockDragEnd,
      onDetach: () {
        setState(() {
          widget.block.nestedBlocks[inputId] = null;
        });
      },
    );
  }

  List<Widget> _buildNestedBlocks() {
    final socketInputs = widget.block.definition.inputs
        .where((input) => input.type == InputFieldType.blockSocket)
        .toList();

    if (socketInputs.isEmpty) return [];

    return socketInputs.map((input) {
      final nestedBlock = widget.block.nestedBlocks[input.id];
      return Container(
        margin: const EdgeInsets.only(left: 16, bottom: 8, right: 8, top: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (input.label.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  input.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (nestedBlock != null)
              (nestedBlock.definition.shape == BlockShape.boolean
                  ? BooleanBlockWidget(
                      block: nestedBlock,
                      onInputChanged: widget.onInputChanged,
                      onBlockDragStarted: widget.onBlockDragStarted,
                      onBlockDragEnd: widget.onBlockDragEnd,
                      onDetach: () {
                         setState(() {
                           widget.block.nestedBlocks[input.id] = null;
                         });
                      })
                  : StatementBlockWidget(
                      block: nestedBlock,
                      onInputChanged: widget.onInputChanged,
                      onBlockDragStarted: widget.onBlockDragStarted,
                      onBlockDragEnd: widget.onBlockDragEnd,
                      onDetach: () {
                         setState(() {
                           widget.block.nestedBlocks[input.id] = null;
                         });
                      },
                    ))
            else
              DragTarget<BlockInstance>(
                hitTestBehavior: HitTestBehavior.opaque,
                onWillAcceptWithDetails: (details) {
                  if (details.data.containsInstance(widget.block)) return false;
                  return input.acceptedBlockShape == null ||
                      details.data.definition.shape == input.acceptedBlockShape;
                },
                onAcceptWithDetails: (details) {
                   LogicPage.of(context)?.removeRoot(details.data);
                  setState(() {
                    widget.block.nestedBlocks[input.id] = details.data;
                  });
                },
                builder: (context, candidateData, rejectedData) {
                  return Container(
                    height: 50, // Increased height
                    width: candidateData.isNotEmpty ? 150 : 120, // Increased width
                    decoration: BoxDecoration(
                      color: candidateData.isNotEmpty
                          ? Colors.white.withValues(alpha: 0.3)
                          : Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 
                          candidateData.isNotEmpty ? 0.6 : 0.3,
                        ),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        candidateData.isNotEmpty ? "Drop here" : "Drag...",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      );
    }).toList();
  }
}

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
