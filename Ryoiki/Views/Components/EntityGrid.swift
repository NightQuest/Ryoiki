//
//  EntityGrid.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-24.
//

import SwiftUI

/// A reusable, closure-driven grid that handles selection gestures and layout reporting.
/// - Parameters:
///   - items: Entities to display. Must be Identifiable with UUID IDs.
///   - selectionManager: Binding to selection/drag state manager.
///   - onLayoutUpdate: Reports tile frames and ordered IDs when layout changes.
///   - minWidth/maxWidth: Adaptive column sizing bounds.
///   - tile: Builder for the tile content, receives (entity, isSelected).
///   - contextMenu: Builder for the context menu, receives (entity, isSelected).
struct EntityGrid<Entity: Identifiable, Tile: View, Menu: View>: View where Entity.ID == UUID {
    let items: [Entity]
    @Binding var selectionManager: SelectionManager
    let onLayoutUpdate: (_ frames: [UUID: CGRect], _ origin: CGPoint, _ orderedIDs: [UUID]) -> Void
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let columns: [GridItem]?

    @ViewBuilder var tile: (Entity, Bool) -> Tile
    @ViewBuilder var contextMenu: (Entity, Bool) -> Menu

    init(items: [Entity],
         selectionManager: Binding<SelectionManager>,
         onLayoutUpdate: @escaping (_ frames: [UUID: CGRect], _ origin: CGPoint, _ orderedIDs: [UUID]) -> Void,
         minWidth: CGFloat,
         maxWidth: CGFloat,
         columns: [GridItem]? = nil,
         @ViewBuilder tile: @escaping (Entity, Bool) -> Tile,
         @ViewBuilder contextMenu: @escaping (Entity, Bool) -> Menu) {
        self.items = items
        self._selectionManager = selectionManager
        self.onLayoutUpdate = onLayoutUpdate
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.columns = columns
        self.tile = tile
        self.contextMenu = contextMenu
    }

    init(items: [Entity],
         selectionManager: Binding<SelectionManager>,
         onLayoutUpdate: @escaping (_ frames: [UUID: CGRect], _ origin: CGPoint, _ orderedIDs: [UUID]) -> Void,
         columns: [GridItem],
         @ViewBuilder tile: @escaping (Entity, Bool) -> Tile,
         @ViewBuilder contextMenu: @escaping (Entity, Bool) -> Menu) {
        self.items = items
        self._selectionManager = selectionManager
        self.onLayoutUpdate = onLayoutUpdate
        self.minWidth = 0
        self.maxWidth = 0
        self.columns = columns
        self.tile = tile
        self.contextMenu = contextMenu
    }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: columns ?? [GridItem(.adaptive(minimum: minWidth, maximum: maxWidth), spacing: Layout.gridSpacing, alignment: .top)],
                spacing: Layout.gridSpacing
            ) {
                ForEach(items, id: \.id) { entity in
                    let isSelected = selectionManager.selection.contains(entity.id)
                    tile(entity, isSelected)
                        .contentShape(Rectangle())
                        .modifier(TileTapGestures(entityID: entity.id, selectionManager: $selectionManager))
                        .anchorPreference(key: TileFramesPreferenceKey.self, value: .bounds) { anchor in
                            [entity.id: anchor]
                        }
                        .contextMenu { contextMenu(entity, isSelected) }
                }
            }
            .padding(Layout.gridPadding)
            .modifier(SelectionDragGestures(selectionManager: $selectionManager))
            .overlay(alignment: .topLeading) {
                SelectionOverlay(rect: selectionManager.selectionRect)
            }
            .backgroundPreferenceValue(TileFramesPreferenceKey.self) { anchors in
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            DispatchQueue.main.async {
                                reportLayout(anchors, proxy: proxy)
                            }
                        }
                        .onChange(of: anchors) { _, newValue in
                            DispatchQueue.main.async {
                                reportLayout(newValue, proxy: proxy)
                            }
                        }
                }
            }
        }
    }

    private func reportLayout(_ anchors: [UUID: Anchor<CGRect>], proxy: GeometryProxy) {
        let origin = CGPoint.zero
        var frames: [UUID: CGRect] = [:]
        frames.reserveCapacity(anchors.count)
        for (id, anchor) in anchors {
            frames[id] = proxy[anchor].offsetBy(dx: origin.x, dy: origin.y)
        }
        onLayoutUpdate(frames, origin, items.map(\.id))
    }
}

// MARK: - Shared helpers (generalized from PagesGrid)

struct SelectionOverlay: View {
    let rect: CGRect?
    var body: some View {
        Group {
            if let rect {
                ZStack {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: 1)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                .allowsHitTesting(false)
            }
        }
    }
}

struct TileTapGestures: ViewModifier {
    let entityID: UUID
    @Binding var selectionManager: SelectionManager

    func body(content: Content) -> some View {
        content
            .highPriorityGesture(
                TapGesture().modifiers([.command, .shift])
                    .onEnded { selectionManager.unionWithRange(to: entityID) }
            )
            .highPriorityGesture(
                TapGesture().modifiers(.command)
                    .onEnded { selectionManager.toggleSelection(entityID) }
            )
            .highPriorityGesture(
                TapGesture().modifiers(.shift)
                    .onEnded { selectionManager.replaceWithRange(to: entityID) }
            )
            .onTapGesture {
                if selectionManager.selection == [entityID] {
                    selectionManager.toggleSelection(entityID)
                } else {
                    selectionManager.replaceSelection(with: entityID)
                }
            }
    }
}

struct SelectionDragGestures: ViewModifier {
    @Binding var selectionManager: SelectionManager

    func body(content: Content) -> some View {
        content
            .highPriorityGesture(
                DragGesture(minimumDistance: 0).modifiers(.command)
                    .onChanged { value in
                        if selectionManager.selectionRect == nil {
                            selectionManager.beginDrag(at: value.startLocation, mode: .toggle)
                        }
                        selectionManager.updateDrag(to: value.location, mode: .toggle)
                    }
                    .onEnded { value in
                        selectionManager.endDrag(at: value.location)
                    }
            )
            .highPriorityGesture(
                DragGesture(minimumDistance: 0).modifiers(.shift)
                    .onChanged { value in
                        if selectionManager.selectionRect == nil {
                            selectionManager.beginDrag(at: value.startLocation, mode: .union)
                        }
                        selectionManager.updateDrag(to: value.location, mode: .union)
                    }
                    .onEnded { value in
                        selectionManager.endDrag(at: value.location)
                    }
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if selectionManager.selectionRect == nil {
                            selectionManager.beginDrag(at: value.startLocation, mode: .replace)
                        }
                        selectionManager.updateDrag(to: value.location, mode: .replace)
                    }
                    .onEnded { value in
                        selectionManager.endDrag(at: value.location)
                    }
            )
    }
}

struct TileFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: Anchor<CGRect>] = [:]
    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
