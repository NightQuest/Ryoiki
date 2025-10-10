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
        StarRatingView(value: $communityRatingValue, max: 5)
            .onChange(of: communityRatingValue) {
                comicInfo.CommunityRating = communityRatingValue > 0 ? Rating(rawValue: communityRatingValue) : nil
            }
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
        @Binding var communityRatingValue: Int
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
            StarRatingView(value: $communityRatingValue, max: 5)
                .onChange(of: communityRatingValue) {
                    comicInfo.CommunityRating = communityRatingValue > 0 ? Rating(rawValue: communityRatingValue) : nil
                }
        }

        private var publishDatePicker: some View {
            DatePicker("", selection: Binding(
                get: { comicInfo.publishDate },
                set: { comicInfo.publishDate = $0 }
            ), displayedComponents: .date)
            .labelsHidden()
        }

        @ViewBuilder
        var body: some View {
            switch property {
            case .Title: textFieldEditor(text: $comicInfo.Title)
            case .Series: textFieldEditor(text: $comicInfo.Series)
            case .Number: textFieldEditor(text: $comicInfo.Number)
            case .Count: numberFieldEditor(value: $comicInfo.Count)
            case .Volume: numberFieldEditor(value: $comicInfo.Volume)
            case .AlternateSeries: textFieldEditor(text: $comicInfo.AlternateSeries)
            case .AlternateNumber: textFieldEditor(text: $comicInfo.AlternateNumber)
            case .AlternateCount: numberFieldEditor(value: $comicInfo.AlternateCount)
            case .Summary: multilineEditor(text: $comicInfo.Summary)
            case .Notes: multilineEditor(text: $comicInfo.Notes)
            case .Writer: textFieldEditor(text: $comicInfo.Writer)
            case .Penciller: textFieldEditor(text: $comicInfo.Penciller)
            case .Inker: textFieldEditor(text: $comicInfo.Inker)
            case .Colorist: textFieldEditor(text: $comicInfo.Colorist)
            case .Letterer: textFieldEditor(text: $comicInfo.Letterer)
            case .CoverArtist: textFieldEditor(text: $comicInfo.CoverArtist)
            case .Editor: textFieldEditor(text: $comicInfo.Editor)
            case .Publisher: textFieldEditor(text: $comicInfo.Publisher)
            case .Imprint: textFieldEditor(text: $comicInfo.Imprint)
            case .Genre: textFieldEditor(text: $comicInfo.Genre)
            case .Web: textFieldEditor(text: $comicInfo.Web)
            case .LanguageISO: languagePicker
            case .Format: textFieldEditor(text: $comicInfo.Format)
            case .BlackAndWhite: yesNoPicker
            case .Manga: mangaPicker
            case .Characters: textFieldEditor(text: $comicInfo.Characters)
            case .Teams: textFieldEditor(text: $comicInfo.Teams)
            case .Locations: textFieldEditor(text: $comicInfo.Locations)
            case .ScanInformation: textFieldEditor(text: $comicInfo.ScanInformation)
            case .StoryArc: textFieldEditor(text: $comicInfo.StoryArc)
            case .SeriesGroup: textFieldEditor(text: $comicInfo.SeriesGroup)
            case .AgeRating: ageRatingPicker
            case .CommunityRating: communityRatingEditor
            case .MainCharacterOrTeam: textFieldEditor(text: $comicInfo.MainCharacterOrTeam)
            case .Review: multilineEditor(text: $comicInfo.Review)
            case .PublishDate: publishDatePicker
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
                                        PropertyEditor(comicInfo: comicInfo, communityRatingValue: $communityRatingValue, property: prop)
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
