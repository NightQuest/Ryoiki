//
//  FileView.swift
//  MetaComic
//
//  Created by Stardust on 2025-10-04.
//

import SwiftUI
import ZIPFoundation
internal import UniformTypeIdentifiers

struct FileView: View {
    @Binding var comicInfoData: ComicInfoModel?
    @Binding var fileURL: URL?

    var body: some View {
        VStack {
            HStack {
                Text(comicInfoData?.Title ?? "")
            }
        }
    }
}

