import SwiftUI
import Observation

@Observable
final class ComicPagesSelectionModel {
    enum SelectionMode { case replace, union, toggle }

    // Selection state
    var selection: Set<UUID> = []
    var selectionAnchor: UUID?

    // Drag state
    var selectionRect: CGRect?
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var selectionBaseline: Set<UUID> = []

    // Geometry/state from the view
    private(set) var itemFrames: [UUID: CGRect] = [:]
    private(set) var gridGlobalOrigin: CGPoint = .zero
    private(set) var orderedIDs: [UUID] = []

    // Throttling
    private var lastDragTick: TimeInterval = 0

    // MARK: - Updates from the view

    func updateOrderedIDs(_ ids: [UUID]) { orderedIDs = ids }
    func updateItemFrames(_ frames: [UUID: CGRect]) { itemFrames = frames }
    func updateGridOrigin(_ origin: CGPoint) { gridGlobalOrigin = origin }

    // MARK: - Click selection

    func toggleSelection(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        selectionAnchor = id
    }

    func replaceSelection(with id: UUID) {
        selection = [id]
        selectionAnchor = id
    }

    func replaceWithRange(to id: UUID) {
        let anchor = ensureAnchor(for: id)
        selection = rangeIDs(from: anchor, to: id)
        selectionAnchor = id
    }

    func unionWithRange(to id: UUID) {
        let anchor = ensureAnchor(for: id)
        selection = selection.union(rangeIDs(from: anchor, to: id))
        selectionAnchor = id
    }

    // MARK: - Drag selection

    func beginDrag(at start: CGPoint, mode: SelectionMode) {
        dragStart = start
        dragCurrent = start
        switch mode {
        case .replace: selectionBaseline = []
        case .union, .toggle: selectionBaseline = selection
        }
        selectionRect = rectFromDrag()
        lastDragTick = 0
    }

    func updateDrag(to location: CGPoint, mode: SelectionMode) {
        dragCurrent = location
        let t = now()
        if t - lastDragTick < 0.01 { return }
        lastDragTick = t
        guard let rect = rectFromDrag() else { return }
        selectionRect = rect
        let current = selectionFor(rect: rect)
        let newSel = applySelection(baseline: selectionBaseline, current: current, mode: mode)
        if newSel != selection { selection = newSel }
    }

    func endDrag(at location: CGPoint) {
        if let rect = rectFromDrag() {
            let current = selectionFor(rect: rect)
            if let id = nearestID(to: location, in: current) { selectionAnchor = id }
        }
        dragStart = nil
        dragCurrent = nil
        selectionRect = nil
        lastDragTick = 0
        selectionBaseline.removeAll()
    }

    // MARK: - Internals

    private func applySelection(baseline: Set<UUID>, current: Set<UUID>, mode: SelectionMode) -> Set<UUID> {
        switch mode {
        case .replace: return current
        case .union: return baseline.union(current)
        case .toggle: return baseline.symmetricDifference(current)
        }
    }

    private func now() -> TimeInterval { Date().timeIntervalSinceReferenceDate }

    private func rectFromDrag() -> CGRect? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        let origin = CGPoint(x: min(start.x, current.x), y: min(start.y, current.y))
        let size = CGSize(width: abs(current.x - start.x), height: abs(current.y - start.y))
        return CGRect(origin: origin, size: size)
    }

    private func selectionFor(rect: CGRect) -> Set<UUID> {
        let globalRect = rect.offsetBy(dx: gridGlobalOrigin.x, dy: gridGlobalOrigin.y)
        var result: Set<UUID> = []
        result.reserveCapacity(itemFrames.count)
        for (id, frame) in itemFrames where frame.intersects(globalRect) { result.insert(id) }
        return result
    }

    private func indexOf(id: UUID) -> Int? { orderedIDs.firstIndex(of: id) }

    private func rangeIDs(from anchor: UUID, to id: UUID) -> Set<UUID> {
        guard let i1 = indexOf(id: anchor), let i2 = indexOf(id: id) else { return [id] }
        let lower = min(i1, i2)
        let upper = max(i1, i2)
        return Set(orderedIDs[lower...upper])
    }

    private func ensureAnchor(for targetID: UUID) -> UUID {
        if let existing = selectionAnchor { return existing }
        if selection.count == 1, let only = selection.first { selectionAnchor = only; return only }
        selectionAnchor = targetID
        return targetID
    }

    private func nearestID(to point: CGPoint, in candidates: Set<UUID>) -> UUID? {
        let pairs = candidates.compactMap { id -> (UUID, CGFloat)? in
            guard let frame = itemFrames[id] else { return nil }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let dx = center.x - point.x
            let dy = center.y - point.y
            return (id, dx*dx + dy*dy)
        }
        return pairs.min(by: { $0.1 < $1.1 })?.0
    }
}
