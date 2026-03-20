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
            dimensions: { proposal in
                let childProposal = ProposedViewSize(
                    width:  w != nil ? w : proposal.width,
                    height: h != nil ? h : proposal.height
                )
                let childSize = lc.sizeThatFits(childProposal)
                return ViewDimensions(
                    width:  w ?? childSize.width,
                    height: h ?? childSize.height
                )
            },
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
            }
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

        func computeSize(proposal: ProposedViewSize) -> CGSize {
            // Propose to child: use ideal if provided, else expand to fill when max==∞
            let childW: CGFloat?
            if let ideal = idealW {
                childW = ideal
            } else if maxW == .infinity, let available = proposal.width {
                childW = available
            } else {
                childW = proposal.width
            }
            let childH: CGFloat?
            if let ideal = idealH {
                childH = ideal
            } else if maxH == .infinity, let available = proposal.height {
                childH = available
            } else {
                childH = proposal.height
            }

            let childSize = lc.sizeThatFits(ProposedViewSize(width: childW, height: childH))

            // Clamp result to [min, max]; fill when max==∞
            var w = childSize.width
            if maxW == .infinity, let available = proposal.width { w = available }
            else if let max = maxW { w = min(w, max) }
            if let min = minW { w = Swift.max(w, min) }

            var h = childSize.height
            if maxH == .infinity, let available = proposal.height { h = available }
            else if let max = maxH { h = min(h, max) }
            if let min = minH { h = Swift.max(h, min) }

            return CGSize(width: w, height: h)
        }

        return LayoutComputer(
            sizeThatFits: { proposal in
                computeSize(proposal: proposal)
            },
            spacing: lc.spacing,
            dimensions: { proposal in
                let size = computeSize(proposal: proposal)
                return ViewDimensions(width: size.width, height: size.height)
            },
            place: { position, anchor, proposal in
                lc.place(at: position, anchor: anchor, proposal: proposal)
            }
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

