# Design QA

## Visual truth

- Reference: `docs/images/map-redesign-reference.png`
- Implementation captures:
  - `build/design-qa/implementation-final-collapsed.png`
  - `build/design-qa/implementation-final-expanded.png`
- Same-input comparison: `build/design-qa/source-vs-implementation.png`
- State compared: parent map, route panel expanded

## Normalization

- Reference image: 1024 x 1536 px, normalized to 780 x 1686 px.
- Emulator capture: 1080 x 2400 px. Android-owned status and navigation bars were excluded, then the app content was normalized to 780 x 1642 px.
- Combined comparison canvas: 1588 x 1750 px.
- The full-view comparison is high resolution and keeps the header, route, marker, recenter control, route sheet, cards, and date control legible. Separate focused crops were not required.

## Findings

- The selected warm ivory, peach, pink, and lavender visual direction is reproduced across the map header, route, marker, sheet, cards, and controls.
- The real map remains interactive and data-driven. Its tile detail is intentionally denser than the illustrative reference, but a light desaturated treatment keeps the visual hierarchy aligned.
- The child marker uses the approved app mascot asset rather than an approximation.
- The route uses a soft white halo, apricot-to-pink-to-lavender gradient, and waypoint beads. The entire route remains visible above the expanded sheet.
- The route sheet collapses and expands without changing the existing tracking behavior. Timeline cards remain horizontally scrollable; the partially visible next card is an intentional scroll affordance.
- Runtime-owned Android system bars and the existing production bottom navigation are outside the fragment-only deterministic preview. Production navigation remains unchanged.
- Remote child battery percentage is shown. Per-app battery consumption is not represented as remotely available because Android does not expose that information to a parent device.
- No clipped controls, overlapping text, broken wrapping, placeholder graphics, or high-impact visual mismatches remain.

## Comparison history

1. Initial capture exposed incorrect route bead colors, an inverted affordance arrow, a clipped recenter control, and route content hidden by the expanded sheet.
2. The route color composition, arrow state, map-safe margins, marker position, and timeline text wrapping were corrected.
3. Final full-view comparison confirmed the selected composition and visual hierarchy in both collapsed and expanded states.

## Result

passed
