import SwiftUI

/// Form for editing ComicInfo metadata. Fields are dynamically chosen based on selected properties.
struct BookInformationView: View {
    @ObservedObject var comicInfo: ComicInfoModel

    @State private var selectedProperties: [ComicInfoModel.EditableProperty] = []

    private func orderIndex(_ p: ComicInfoModel.EditableProperty) -> Int {
        ComicInfoModel.EditableProperty.allCases.firstIndex(of: p) ?? Int.max
    }

    private func hasNonDefaultValue(_ property: ComicInfoModel.EditableProperty) -> Bool {
        comicInfo.hasNonDefaultValue(property)
    }

    @ViewBuilder
    private func textFieldEditor(text: Binding<String>) -> some View {
        TextField("", text: text)
    }

    @ViewBuilder
    private func numberFieldEditor(value: Binding<Int?>) -> some View {
        TextField(value: value, format: .number) { EmptyView() }
            .labelsHidden()
    }

    @ViewBuilder
    private func numberFieldEditor(value: Binding<Int>) -> some View {
        // Bridge non-optional Int to optional for the TextField and back
        let optionalBinding = Binding<Int?>(
            get: { value.wrappedValue },
            set: { newValue in
                value.wrappedValue = newValue ?? 0
            }
        )
        TextField(value: optionalBinding, format: .number) { EmptyView() }
            .labelsHidden()
    }

    @ViewBuilder
    private func multilineEditor(text: Binding<String>) -> some View {
        TextField("", text: text, axis: .vertical)
            .lineLimit(1...)
            .submitLabel(.return)
            .submitScope(false)
    }

    private var languagePicker: some View {
        Picker("", selection: $comicInfo.LanguageISO) {
            ForEach(languageOptions) { option in
                Text("\(option.nativeName) (\(option.code))").tag(option.code)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private var yesNoPicker: some View {
        Picker("", selection: $comicInfo.BlackAndWhite) {
            ForEach(YesNo.allCases) { option in
                Text("\(option.rawValue)").tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private var mangaPicker: some View {
        Picker("", selection: $comicInfo.Manga) {
            ForEach(Manga.allCases) { option in
                Text("\(option.rawValue)").tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private var ageRatingPicker: some View {
        Picker("", selection: $comicInfo.AgeRating) {
            ForEach(AgeRating.allCases, id: \.self) { rating in
                Text(rating.rawValue).tag(rating)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private var communityRatingEditor: some View {
        StarRatingView(value: Binding(get: { comicInfo.communityRatingInt }, set: { comicInfo.communityRatingInt = $0 }), max: 5)
    }

    private var publishDatePicker: some View {
        DatePicker("", selection: Binding(
            get: { comicInfo.publishDate },
            set: { comicInfo.publishDate = $0 }
        ), displayedComponents: .date)
        .labelsHidden()
    }

    private struct PropertyEditor: View {
        @ObservedObject var comicInfo: ComicInfoModel
        let property: ComicInfoModel.EditableProperty

        @ViewBuilder
        private func textFieldEditor(text: Binding<String>) -> some View { TextField("", text: text) }

        @ViewBuilder
        private func numberFieldEditor(value: Binding<Int?>) -> some View {
            TextField(value: value, format: .number) { EmptyView() }.labelsHidden()
        }

        @ViewBuilder
        private func numberFieldEditor(value: Binding<Int>) -> some View {
            let optionalBinding = Binding<Int?>(get: { value.wrappedValue }, set: { value.wrappedValue = $0 ?? 0 })
            TextField(value: optionalBinding, format: .number) { EmptyView() }.labelsHidden()
        }

        @ViewBuilder
        private func multilineEditor(text: Binding<String>) -> some View {
            TextField("", text: text, axis: .vertical)
                .lineLimit(1...)
                .submitLabel(.return)
                .submitScope(false)
        }

        @ViewBuilder
        private var languagePicker: some View {
            Picker("", selection: $comicInfo.LanguageISO) {
                ForEach(languageOptions) { option in
                    Text("\(option.nativeName) (\(option.code))").tag(option.code)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }

        @ViewBuilder
        private var yesNoPicker: some View {
            Picker("", selection: $comicInfo.BlackAndWhite) {
                ForEach(YesNo.allCases) { option in
                    Text("\(option.rawValue)").tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }

        @ViewBuilder
        private var mangaPicker: some View {
            Picker("", selection: $comicInfo.Manga) {
                ForEach(Manga.allCases) { option in
                    Text("\(option.rawValue)").tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }

        @ViewBuilder
        private var ageRatingPicker: some View {
            Picker("", selection: $comicInfo.AgeRating) {
                ForEach(AgeRating.allCases, id: \.self) { rating in
                    Text(rating.rawValue).tag(rating)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }

        @ViewBuilder
        private var communityRatingEditor: some View {
            StarRatingView(value: Binding(get: { comicInfo.communityRatingInt }, set: { comicInfo.communityRatingInt = $0 }), max: 5)
        }

        @ViewBuilder
        private var publishDatePicker: some View {
            DatePicker("", selection: Binding(
                get: { comicInfo.publishDate },
                set: { comicInfo.publishDate = $0 }
            ), displayedComponents: .date)
            .labelsHidden()
        }

        private var editors: [ComicInfoModel.EditableProperty: AnyView] {
            [
                .Title: AnyView(textFieldEditor(text: $comicInfo.Title)),
                .Series: AnyView(textFieldEditor(text: $comicInfo.Series)),
                .Number: AnyView(textFieldEditor(text: $comicInfo.Number)),
                .Count: AnyView(numberFieldEditor(value: $comicInfo.Count)),
                .Volume: AnyView(numberFieldEditor(value: $comicInfo.Volume)),
                .AlternateSeries: AnyView(textFieldEditor(text: $comicInfo.AlternateSeries)),
                .AlternateNumber: AnyView(textFieldEditor(text: $comicInfo.AlternateNumber)),
                .AlternateCount: AnyView(numberFieldEditor(value: $comicInfo.AlternateCount)),
                .Summary: AnyView(multilineEditor(text: $comicInfo.Summary)),
                .Notes: AnyView(multilineEditor(text: $comicInfo.Notes)),
                .Writer: AnyView(textFieldEditor(text: $comicInfo.Writer)),
                .Penciller: AnyView(textFieldEditor(text: $comicInfo.Penciller)),
                .Inker: AnyView(textFieldEditor(text: $comicInfo.Inker)),
                .Colorist: AnyView(textFieldEditor(text: $comicInfo.Colorist)),
                .Letterer: AnyView(textFieldEditor(text: $comicInfo.Letterer)),
                .CoverArtist: AnyView(textFieldEditor(text: $comicInfo.CoverArtist)),
                .Editor: AnyView(textFieldEditor(text: $comicInfo.Editor)),
                .Publisher: AnyView(textFieldEditor(text: $comicInfo.Publisher)),
                .Imprint: AnyView(textFieldEditor(text: $comicInfo.Imprint)),
                .Genre: AnyView(textFieldEditor(text: $comicInfo.Genre)),
                .Web: AnyView(textFieldEditor(text: $comicInfo.Web)),
                .LanguageISO: AnyView(languagePicker),
                .Format: AnyView(textFieldEditor(text: $comicInfo.Format)),
                .BlackAndWhite: AnyView(yesNoPicker),
                .Manga: AnyView(mangaPicker),
                .Characters: AnyView(textFieldEditor(text: $comicInfo.Characters)),
                .Teams: AnyView(textFieldEditor(text: $comicInfo.Teams)),
                .Locations: AnyView(textFieldEditor(text: $comicInfo.Locations)),
                .ScanInformation: AnyView(textFieldEditor(text: $comicInfo.ScanInformation)),
                .StoryArc: AnyView(textFieldEditor(text: $comicInfo.StoryArc)),
                .SeriesGroup: AnyView(textFieldEditor(text: $comicInfo.SeriesGroup)),
                .AgeRating: AnyView(ageRatingPicker),
                .CommunityRating: AnyView(communityRatingEditor),
                .MainCharacterOrTeam: AnyView(textFieldEditor(text: $comicInfo.MainCharacterOrTeam)),
                .Review: AnyView(multilineEditor(text: $comicInfo.Review)),
                .PublishDate: AnyView(publishDatePicker)
            ]
        }

        @ViewBuilder
        var body: some View {
            if let view = editors[property] {
                view
            } else {
                EmptyView()
            }
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
                                            .frame(width: 120, alignment: .leading)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .help(prop.displayName)
                                        PropertyEditor(comicInfo: comicInfo, property: prop)
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
                                        Button {
                                            selectedProperties.append(prop)
                                        } label: {
                                            Text(prop.displayName)
                                        }
                                    }
                                } label: {
                                    Label("Add", systemImage: "plus")
                                }
#if os(macOS)
                                .menuStyle(.borderedButton)
#endif
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
