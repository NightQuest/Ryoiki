//
//  PagesGrid.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-24.
//

import SwiftUI

struct PagesGrid: View {
    let downloadedPages: [ComicPage]
    @Binding var selectionManager: SelectionManager
    let onLayoutUpdate: (_ frames: [UUID: CGRect], _ origin: CGPoint, _ orderedIDs: [UUID]) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140, maximum: 260), spacing: Layout.gridSpacing, alignment: .top)],
                spacing: Layout.gridSpacing
            ) {
                ForEach(downloadedPages, id: \.id) { page in
                    PageTile(page: page, isSelected: selectionManager.selection.contains(page.id))
                        .contentShape(Rectangle())
                        .modifier(PageTileTapGestures(pageID: page.id, selectionManager: $selectionManager))
                        .anchorPreference(key: TileFramesPreferenceKey.self, value: .bounds) { anchor in
                            [page.id: anchor]
                        }
                        .contextMenu {
                            Button(selectionManager.selection.contains(page.id) ? "Deselect" : "Select") {
                                selectionManager.toggleSelection(page.id)
                            }
                        }
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
                            let containerOrigin = proxy.frame(in: .global).origin
                            let frames = resolveFrames(anchors, proxy: proxy, containerOrigin: containerOrigin)
                            let ids = downloadedPages.map { $0.id }
                            onLayoutUpdate(frames, containerOrigin, ids)
                        }
                        .onChange(of: anchors) { _, newValue in
                            let containerOrigin = proxy.frame(in: .global).origin
                            let frames = resolveFrames(newValue, proxy: proxy, containerOrigin: containerOrigin)
                            let ids = downloadedPages.map { $0.id }
                            onLayoutUpdate(frames, containerOrigin, ids)
                        }
                }
            }
        }
    }

    private func resolveFrames(_ anchors: [UUID: Anchor<CGRect>], proxy: GeometryProxy, containerOrigin: CGPoint) -> [UUID: CGRect] {
        var dict: [UUID: CGRect] = [:]
        dict.reserveCapacity(anchors.count)
        for (id, anchor) in anchors {
            let rect = proxy[anchor].offsetBy(dx: containerOrigin.x, dy: containerOrigin.y)
            dict[id] = rect
        }
        return dict
    }
}

private struct SelectionOverlay: View {
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

private struct PageTileTapGestures: ViewModifier {
    let pageID: UUID
    @Binding var selectionManager: SelectionManager

    func body(content: Content) -> some View {
        content
            .highPriorityGesture(
                TapGesture().modifiers([.command, .shift])
                    .onEnded { selectionManager.unionWithRange(to: pageID) }
            )
            .highPriorityGesture(
                TapGesture().modifiers(.command)
                    .onEnded { selectionManager.toggleSelection(pageID) }
            )
            .highPriorityGesture(
                TapGesture().modifiers(.shift)
                    .onEnded { selectionManager.replaceWithRange(to: pageID) }
            )
            .onTapGesture {
                if selectionManager.selection == [pageID] {
                    selectionManager.toggleSelection(pageID)
                } else {
                    selectionManager.replaceSelection(with: pageID)
                }
            }
    }
}

private struct SelectionDragGestures: ViewModifier {
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

private struct TileFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: Anchor<CGRect>] = [:]
    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
