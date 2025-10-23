import Foundation
import SwiftUI
import Observation

/// Mode used when performing a drag selection.
public enum SelectionDragMode: Sendable {
    case replace
    case union
    case toggle
}

/// A platform-agnostic selection controller for grid/list UIs.
///
/// - Uses @Observable for SwiftUI binding on iOS 18+/macOS 15+.
/// - Main-actor isolated: safe to bind directly to views.
@MainActor
@Observable
public final class SelectionManager {
    /// The current set of selected item identifiers.
    public private(set) var selection: Set<UUID> = []
    /// The current drag selection rectangle in global coordinates (if active).
    public private(set) var selectionRect: CGRect?
    /// A mapping of item IDs to their frames in global coordinates.
    public private(set) var itemFrames: [UUID: CGRect] = [:]
    /// The origin (in global coordinates) of the scrollable grid hosting the items.
    public private(set) var gridOrigin: CGPoint = .zero
    /// The current ordering of item identifiers as presented in the grid.
    public private(set) var orderedIDs: [UUID] = []
    private var idIndex: [UUID: Int] = [:]

    // Callback storage
    private var onSelectionChange: ((Set<UUID>) -> Void)?
    private var onBeginDrag: ((CGPoint, SelectionDragMode) -> Void)?
    private var onUpdateDrag: ((CGPoint, SelectionDragMode) -> Void)?
    private var onEndDrag: ((CGPoint) -> Void)?

    // Fluent callback configuration
    @discardableResult
    public func onSelectionChange(_ handler: @escaping (Set<UUID>) -> Void) -> Self {
        self.onSelectionChange = handler
        return self
    }

    @discardableResult
    public func onBeginDrag(_ handler: @escaping (CGPoint, SelectionDragMode) -> Void) -> Self {
        self.onBeginDrag = handler
        return self
    }

    @discardableResult
    public func onUpdateDrag(_ handler: @escaping (CGPoint, SelectionDragMode) -> Void) -> Self {
        self.onUpdateDrag = handler
        return self
    }

    @discardableResult
    public func onEndDrag(_ handler: @escaping (CGPoint) -> Void) -> Self {
        self.onEndDrag = handler
        return self
    }

    private var anchorID: UUID?
    private var dragStart: CGPoint?
    private var baseSelection: Set<UUID> = []

    public init() {}

    /// Toggle inclusion of a single item in the selection and update the range anchor.
    public func toggleSelection(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
        anchorID = id
        onSelectionChange?(selection)
    }

    /// Replace selection with a single item and update the range anchor.
    public func replaceSelection(with id: UUID) {
        selection = [id]
        anchorID = id
        onSelectionChange?(selection)
    }

    /// Replace selection with the contiguous range from the anchor to the target.
    public func replaceWithRange(to id: UUID) {
        guard let anchor = anchorID,
              let anchorIndex = idIndex[anchor],
              let targetIndex = idIndex[id] else {
            replaceSelection(with: id)
            anchorID = id
            return
        }
        let range: ClosedRange<Int> = anchorIndex < targetIndex ? anchorIndex...targetIndex : targetIndex...anchorIndex
        selection = Set(orderedIDs[range])
        onSelectionChange?(selection)
    }

    /// Union the selection with the contiguous range from the anchor to the target.
    public func unionWithRange(to id: UUID) {
        guard let anchor = anchorID,
              let anchorIndex = idIndex[anchor],
              let targetIndex = idIndex[id] else {
            selection.insert(id)
            onSelectionChange?(selection)
            return
        }
        let range: ClosedRange<Int> = anchorIndex < targetIndex ? anchorIndex...targetIndex : targetIndex...anchorIndex
        selection.formUnion(orderedIDs[range])
        onSelectionChange?(selection)
    }

    /// Begin a drag selection. Points are provided in the grid's local coordinate space.
    public func beginDrag(at point: CGPoint, mode: SelectionDragMode) {
        let globalPoint = CGPoint(x: point.x + gridOrigin.x, y: point.y + gridOrigin.y)
        baseSelection = selection
        dragStart = globalPoint
        selectionRect = CGRect(origin: globalPoint, size: .zero)
        onBeginDrag?(point, mode)
    }

    /// Update a drag selection. Points are provided in the grid's local coordinate space.
    public func updateDrag(to point: CGPoint, mode: SelectionDragMode) {
        guard let start = dragStart else { return }
        let globalPoint = CGPoint(x: point.x + gridOrigin.x, y: point.y + gridOrigin.y)
        selectionRect = CGRect(
            x: min(start.x, globalPoint.x),
            y: min(start.y, globalPoint.y),
            width: abs(globalPoint.x - start.x),
            height: abs(globalPoint.y - start.y)
        )

        guard let rect = selectionRect else { return }

        let intersectingIDs: [UUID] = itemFrames.keys.filter { key in
            if let frame = itemFrames[key] {
                return frame.intersects(rect)
            }
            return false
        }

        switch mode {
        case .replace:
            selection = Set(intersectingIDs)
        case .union:
            selection = baseSelection.union(intersectingIDs)
        case .toggle:
            // Symmetric difference relative to baseSelection
            var newSelection = baseSelection
            for id in intersectingIDs {
                if newSelection.contains(id) {
                    newSelection.remove(id)
                } else {
                    newSelection.insert(id)
                }
            }
            selection = newSelection
        }

        onSelectionChange?(selection)
        onUpdateDrag?(point, mode)
    }

    /// End a drag selection. Point is provided in the grid's local coordinate space.
    public func endDrag(at point: CGPoint) {
        selectionRect = nil
        dragStart = nil
        baseSelection = []
        onEndDrag?(point)
    }

    /// Update the global frames for items.
    public func updateItemFrames(_ frames: [UUID: CGRect]) {
        itemFrames = frames
    }

    /// Update the grid origin used to convert local drag points to global coordinates.
    public func updateGridOrigin(_ origin: CGPoint) {
        gridOrigin = origin
    }

    /// Update the ordered item identifiers and rebuild the index cache.
    public func updateOrderedIDs(_ ids: [UUID]) {
        orderedIDs = ids
        idIndex = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
    }

    /// Programmatically set the selection.
    public func setSelection(_ newSelection: Set<UUID>) {
        selection = newSelection
        onSelectionChange?(selection)
    }

    /// Clear all selections.
    public func clearSelection() {
        selection.removeAll()
        onSelectionChange?(selection)
    }
}
