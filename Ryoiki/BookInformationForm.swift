import SwiftUI

/// Form for editing ComicInfo metadata. Fields are dynamically chosen based on selected properties.
struct BookInformationForm: View {
    @ObservedObject var comicInfo: ComicInfoModel
    @Binding var communityRatingValue: Int

    @State private var selectedProperties: [ComicInfoModel.EditableProperty] = []

    private func orderIndex(_ p: ComicInfoModel.EditableProperty) -> Int {
        ComicInfoModel.EditableProperty.allCases.firstIndex(of: p) ?? Int.max
    }

    private func hasNonDefaultValue(_ property: ComicInfoModel.EditableProperty) -> Bool {
        comicInfo.hasNonDefaultValue(property)
    }

    @ViewBuilder
    private func editor(for property: ComicInfoModel.EditableProperty) -> some View {
        switch property {
        case .Title: TextField("", text: $comicInfo.Title)
        case .Series: TextField("", text: $comicInfo.Series)
        case .Number: TextField("", text: $comicInfo.Number)
        case .Count:
            TextField(value: $comicInfo.Count, format: .number) { EmptyView() }.labelsHidden()
        case .Volume:
            TextField(value: $comicInfo.Volume, format: .number) { EmptyView() }.labelsHidden()
        case .AlternateSeries: TextField("", text: $comicInfo.AlternateSeries)
        case .AlternateNumber: TextField("", text: $comicInfo.AlternateNumber)
        case .AlternateCount:
            TextField(value: $comicInfo.AlternateCount, format: .number) { EmptyView() }.labelsHidden()
        case .Summary:
            TextField("", text: $comicInfo.Summary, axis: .vertical).lineLimit(1...).submitLabel(.return).submitScope(false)
        case .Notes:
            TextField("", text: $comicInfo.Notes, axis: .vertical).lineLimit(1...).submitLabel(.return).submitScope(false)
        case .Writer: TextField("", text: $comicInfo.Writer)
        case .Penciller: TextField("", text: $comicInfo.Penciller)
        case .Inker: TextField("", text: $comicInfo.Inker)
        case .Colorist: TextField("", text: $comicInfo.Colorist)
        case .Letterer: TextField("", text: $comicInfo.Letterer)
        case .CoverArtist: TextField("", text: $comicInfo.CoverArtist)
        case .Editor: TextField("", text: $comicInfo.Editor)
        case .Publisher: TextField("", text: $comicInfo.Publisher)
        case .Imprint: TextField("", text: $comicInfo.Imprint)
        case .Genre: TextField("", text: $comicInfo.Genre)
        case .Web: TextField("", text: $comicInfo.Web)
        case .LanguageISO:
            Picker("", selection: $comicInfo.LanguageISO) {
                ForEach(languageOptions) { option in
                    Text("\(option.nativeName) (\(option.code))").tag(option.code)
                }
            }.labelsHidden().pickerStyle(.menu)
        case .Format: TextField("", text: $comicInfo.Format)
        case .BlackAndWhite:
            Picker("", selection: $comicInfo.BlackAndWhite) {
                Text("Unknown").tag(YesNo.Unknown)
                Text("Yes").tag(YesNo.Yes)
                Text("No").tag(YesNo.No)
            }.labelsHidden().pickerStyle(.menu)
        case .Manga:
            Picker("", selection: $comicInfo.Manga) {
                ForEach(Manga.allCases) { option in
                    Text("\(option.rawValue)").tag(option)
                }
            }.labelsHidden().pickerStyle(.menu)
        case .Characters: TextField("", text: $comicInfo.Characters)
        case .Teams: TextField("", text: $comicInfo.Teams)
        case .Locations: TextField("", text: $comicInfo.Locations)
        case .ScanInformation: TextField("", text: $comicInfo.ScanInformation)
        case .StoryArc: TextField("", text: $comicInfo.StoryArc)
        case .SeriesGroup: TextField("", text: $comicInfo.SeriesGroup)
        case .AgeRating:
            Picker("", selection: $comicInfo.AgeRating) {
                ForEach(AgeRating.allCases, id: \.self) { rating in
                    Text(rating.rawValue).tag(rating)
                }
            }.labelsHidden().pickerStyle(.menu)
        case .CommunityRating:
            StarRatingView(value: $communityRatingValue, max: 5)
                .onChange(of: communityRatingValue) {
                    comicInfo.CommunityRating = communityRatingValue > 0 ? Rating(rawValue: communityRatingValue) : nil
                }
        case .MainCharacterOrTeam: TextField("", text: $comicInfo.MainCharacterOrTeam)
        case .Review:
            TextField("", text: $comicInfo.Review, axis: .vertical).lineLimit(1...).submitLabel(.return).submitScope(false)
        case .PublishDate:
            DatePicker("", selection: Binding(get: { comicInfo.publishDate }, set: { comicInfo.publishDate = $0 }), displayedComponents: .date).labelsHidden()
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GroupBox {
                    Form {
                        Section {
                            VStack(spacing: 8) {
                                ForEach(selectedProperties.sorted { a, b in orderIndex(a) < orderIndex(b) }, id: \.self) { prop in
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        Text(prop.displayName)
                                            .frame(width: UIConstants.labelColumnWidth, alignment: .leading)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .help(prop.displayName)
                                        editor(for: prop)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Button(role: .destructive) {
                                            if let idx = selectedProperties.firstIndex(of: prop) { selectedProperties.remove(at: idx) }
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Remove \(prop.displayName)")
                                    }
                                    .padding(.vertical, 4)
                                    .submitScope(false)
                                    Divider()
                                }
                            }
                            .padding(.top, 4)

                            HStack {
                                Spacer()
                                Menu {
                                    ForEach(ComicInfoModel.EditableProperty.allCases.filter { p in !selectedProperties.contains(p) }) { prop in
                                        Button(action: { selectedProperties.append(prop) }) {
                                            Text(prop.displayName)
                                        }
                                    }
                                } label: {
                                    Label("Add", systemImage: "plus")
                                }
                                .menuStyle(.borderedButton)
                                .accessibilityLabel("Add Property Type")
                                .help("Add Property Type")
                            }
                        }
                        .submitScope()
                    }
                    .onSubmit(of: .text) {
                        // Prevent Return from submitting by handling it as a no-op
                    }
                    .onAppear {
                        if selectedProperties.isEmpty {
                            let preselected = ComicInfoModel.EditableProperty.allCases.filter { hasNonDefaultValue($0) }
                            selectedProperties = preselected
                        }
                    }
                    .padding(.all)
                }
                .padding(.all)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
