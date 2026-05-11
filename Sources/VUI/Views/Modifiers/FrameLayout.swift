//
//  File: FrameLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _FrameLayout: ViewModifier, Animatable, Sendable {
    let width: CGFloat?
    let height: CGFloat?
    let alignment: Alignment

    @usableFromInline
    init(width: CGFloat?, height: CGFloat?, alignment: Alignment) {
        self.width = width
        self.height = height
        self.alignment = alignment
    }

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = Never
}

extension _FrameLayout: UnaryLayout {
    func modifyLayoutComputer(_ lc: LayoutComputer) -> LayoutComputer {
        let w = self.width
        let h = self.height
        let alignment = self.alignment
        return LayoutComputer(
            sizeThatFits: { proposal in
                let childProposal = ProposedViewSize(
                    width:  w != nil ? w : proposal.width,
                    height: h != nil ? h : proposal.height
                )
                let childSize = lc.sizeThatFits(childProposal)
                return CGSize(
                    width:  w ?? childSize.width,
                    height: h ?? childSize.height
                )
            },
            spacing: lc.spacing,
            place: { position, anchor, proposal in
                let childProposal = ProposedViewSize(
                    width:  w != nil ? w : proposal.width,
                    height: h != nil ? h : proposal.height
                )
                let childSize = lc.sizeThatFits(childProposal)
                let frameWidth  = w ?? childSize.width
                let frameHeight = h ?? childSize.height
                // top-left origin of the frame
                let ox = position.x - frameWidth  * anchor.x
                let oy = position.y - frameHeight * anchor.y
                // determine child position based on alignment
                let cx: CGFloat
                let ax: CGFloat
                switch alignment.horizontal {
                case .leading:   cx = ox;                    ax = 0
                case .center:    cx = ox + frameWidth * 0.5; ax = 0.5
                case .trailing:  cx = ox + frameWidth;       ax = 1
                default:         cx = ox + frameWidth * 0.5; ax = 0.5
                }
                let cy: CGFloat
                let ay: CGFloat
                switch alignment.vertical {
                case .top:       cy = oy;                     ay = 0
                case .center:    cy = oy + frameHeight * 0.5; ay = 0.5
                case .bottom:    cy = oy + frameHeight;       ay = 1
                default:         cy = oy + frameHeight * 0.5; ay = 0.5
                }
                lc.place(at: CGPoint(x: cx, y: cy),
                         anchor: UnitPoint(x: ax, y: ay),
                         proposal: childProposal)
            },
            explicitAlignment: { lc.explicitAlignment($0, at: $1) }
        )
    }
}

extension View {
    @inlinable nonisolated
    public func frame(width: CGFloat? = nil,
                      height: CGFloat? = nil,
                      alignment: Alignment = .center) -> some View {
        return modifier(
            _FrameLayout(width: width, height: height, alignment: alignment))
    }
}

public struct _FlexFrameLayout: ViewModifier, Animatable, Sendable {
    let minWidth: CGFloat?
    let idealWidth: CGFloat?
    let maxWidth: CGFloat?
    let minHeight: CGFloat?
    let idealHeight: CGFloat?
    let maxHeight: CGFloat?
    let alignment: Alignment

    @usableFromInline
    init(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil,
         maxWidth: CGFloat? = nil, minHeight: CGFloat? = nil,
         idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil, 
         alignment: Alignment) {
        self.minWidth = minWidth
        self.idealWidth = idealWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.idealHeight = idealHeight
        self.maxHeight = maxHeight
        self.alignment = alignment
    }
  
    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = Never
}

extension _FlexFrameLayout: UnaryLayout {
    func modifyLayoutComputer(_ lc: LayoutComputer) -> LayoutComputer {
        let minW = minWidth,  idealW = idealWidth,  maxW = maxWidth
        let minH = minHeight, idealH = idealHeight, maxH = maxHeight

        func childProposal(for proposal: ProposedViewSize) -> ProposedViewSize {
            // Constrain each proposed axis before asking the child for size.
            let childW = constrainedProposal(axisProposal: proposal.width,
                                             min: minW,
                                             ideal: idealW,
                                             max: maxW)
            let childH = constrainedProposal(axisProposal: proposal.height,
                                             min: minH,
                                             ideal: idealH,
                                             max: maxH)

            return ProposedViewSize(width: childW, height: childH)
        }

        func computeSize(proposal: ProposedViewSize) -> CGSize {
            let childProposal = childProposal(for: proposal)
            let childSize = lc.sizeThatFits(childProposal)

            let w = resolvedDimension(axisProposal: proposal.width,
                                      childActual: childSize.width,
                                      min: minW,
                                      ideal: idealW,
                                      max: maxW)
            let h = resolvedDimension(axisProposal: proposal.height,
                                      childActual: childSize.height,
                                      min: minH,
                                      ideal: idealH,
                                      max: maxH)

            return CGSize(width: w, height: h)
        }

        func constrainedProposal(axisProposal: CGFloat?,
                                 min: CGFloat?,
                                 ideal: CGFloat?,
                                 max: CGFloat?) -> CGFloat? {
            guard var value = axisProposal ?? ideal else {
                return nil
            }
            if let min {
                value = Swift.max(value, min)
            }
            if let max {
                value = Swift.min(value, max)
            }
            return value
        }

        func resolvedDimension(axisProposal: CGFloat?,
                               childActual: CGFloat,
                               min: CGFloat?,
                               ideal: CGFloat?,
                               max: CGFloat?) -> CGFloat {
            // Resolve the final frame dimension from the proposal and child size.
            if let axisProposal {
                if let max {
                    return Swift.min(Swift.max(axisProposal, min ?? -.infinity), max)
                }
                return Swift.max(childActual, min ?? -.infinity)
            }

            var value = ideal ?? childActual
            if let min {
                value = Swift.max(value, min)
            }
            if let max {
                value = Swift.min(value, max)
            }
            return value
        }

        return LayoutComputer(
            sizeThatFits: { proposal in
                computeSize(proposal: proposal)
            },
            spacing: lc.spacing,
            place: { position, anchor, proposal in
                let frameSize = computeSize(proposal: proposal)
                let placementProposal = ProposedViewSize(frameSize)
                let frameOrigin = CGPoint(
                    x: position.x - frameSize.width * anchor.x,
                    y: position.y - frameSize.height * anchor.y
                )

                let x: CGFloat
                let childAnchorX: CGFloat
                switch alignment.horizontal {
                case .leading:
                    x = frameOrigin.x
                    childAnchorX = 0
                case .center:
                    x = frameOrigin.x + frameSize.width * 0.5
                    childAnchorX = 0.5
                case .trailing:
                    x = frameOrigin.x + frameSize.width
                    childAnchorX = 1
                default:
                    x = frameOrigin.x + frameSize.width * 0.5
                    childAnchorX = 0.5
                }

                let y: CGFloat
                let childAnchorY: CGFloat
                switch alignment.vertical {
                case .top:
                    y = frameOrigin.y
                    childAnchorY = 0
                case .center:
                    y = frameOrigin.y + frameSize.height * 0.5
                    childAnchorY = 0.5
                case .bottom:
                    y = frameOrigin.y + frameSize.height
                    childAnchorY = 1
                default:
                    y = frameOrigin.y + frameSize.height * 0.5
                    childAnchorY = 0.5
                }

                lc.place(at: CGPoint(x: x, y: y),
                         anchor: UnitPoint(x: childAnchorX, y: childAnchorY),
                         proposal: placementProposal)
            },
            explicitAlignment: { lc.explicitAlignment($0, at: $1) }
        )
    }
}

@usableFromInline
func log_error(_ message: String) {
    Log.error(message)
}

extension View {
    @inlinable nonisolated
    public func frame(minWidth: CGFloat? = nil,
                      idealWidth: CGFloat? = nil,
                      maxWidth: CGFloat? = nil,
                      minHeight: CGFloat? = nil, 
                      idealHeight: CGFloat? = nil,
                      maxHeight: CGFloat? = nil,
                      alignment: Alignment = .center) -> some View {
        func areInNondecreasingOrder(
            _ min: CGFloat?, _ ideal: CGFloat?, _ max: CGFloat?
        ) -> Bool {
            let min = min ?? -.infinity
            let ideal = ideal ?? min
            let max = max ?? ideal
            return min <= ideal && ideal <= max
        }

        if !areInNondecreasingOrder(minWidth, idealWidth, maxWidth)
            || !areInNondecreasingOrder(minHeight, idealHeight, maxHeight)
        {
            log_error("Contradictory frame constraints specified.")
        }

        return modifier(
            _FlexFrameLayout(
                minWidth: minWidth,
                idealWidth: idealWidth, maxWidth: maxWidth,
                minHeight: minHeight,
                idealHeight: idealHeight, maxHeight: maxHeight,
                alignment: alignment))
    }
}
