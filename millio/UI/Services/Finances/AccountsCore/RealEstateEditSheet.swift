import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// Product editor with staged photos. Nothing reaches SwiftData until the user taps Save, so a
/// failed metadata/photo commit cannot leave Account, profile, and gallery out of sync.
struct RealEstateEditSheet: View {
    let account: Account
    let modelContext: ModelContext
    let onSave: (String, AccountGroup?, String?, Bool, RealEstatePropertyType, Int?, UUID?, [RealEstatePhotoDraft]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var note: String
    @State private var includeInTotal: Bool
    @State private var propertyType: RealEstatePropertyType
    @State private var reminder: RealEstateReminder
    @State private var selectedLoanID: UUID?
    @State private var selectedGroupID: UUID?
    @State private var photos: [RealEstatePhotoDraft]
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var isProcessingPhotos = false
    @State private var showsAdditional = false
    @State private var showsTypePicker = false
    @State private var showsReminderPicker = false
    @State private var showsMortgagePicker = false
    @State private var deleteCandidate: UUID?
    @State private var previewPhoto: RealEstatePhotoDraft?
    @State private var photoError: String?

    init(
        account: Account,
        modelContext: ModelContext,
        startsWithTypePicker: Bool = false,
        startsExpanded: Bool = false,
        startsWithReminderPicker: Bool = false,
        startsWithMortgagePicker: Bool = false,
        onSave: @escaping (String, AccountGroup?, String?, Bool, RealEstatePropertyType, Int?, UUID?, [RealEstatePhotoDraft]) -> Void
    ) {
        self.account = account
        self.modelContext = modelContext
        self.onSave = onSave
        let profile = try? RealEstateProfileService(modelContext: modelContext).profile(accountID: account.id)
        let stored = (try? AccountAttachmentService(modelContext: modelContext).photos(accountID: account.id)) ?? []
        _name = State(initialValue: account.name)
        _note = State(initialValue: account.note ?? "")
        _includeInTotal = State(initialValue: account.includeInTotal)
        _propertyType = State(initialValue: profile?.propertyType ?? .other)
        _reminder = State(initialValue: RealEstateReminder(persistedMonths: account.manualAssetMeta?.revalReminderMonths))
        _selectedLoanID = State(initialValue: account.manualAssetMeta?.linkedLoanID)
        _selectedGroupID = State(initialValue: account.group?.id)
        _photos = State(initialValue: stored.map { RealEstatePhotoDraft(id: $0.id, data: $0.mediaData, isCover: $0.isCover) })
        _showsTypePicker = State(initialValue: startsWithTypePicker)
        _showsAdditional = State(initialValue: startsExpanded)
        _showsReminderPicker = State(initialValue: startsWithReminderPicker)
        _showsMortgagePicker = State(initialValue: startsWithMortgagePicker)
    }

    private var groups: [AccountGroup] {
        (try? modelContext.fetch(FetchDescriptor<AccountGroup>(sortBy: [SortDescriptor(\.order)]))) ?? []
    }

    private var eligibleLoans: [Account] {
        let descriptor = FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)])
        return ((try? modelContext.fetch(descriptor)) ?? []).filter { RealEstateEditPolicy.eligibleMortgage($0, for: account) }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var selectedGroup: AccountGroup? { groups.first { $0.id == selectedGroupID } }
    private var selectedLoanTitle: String {
        eligibleLoans.first { $0.id == selectedLoanID }?.name ?? L("real_estate.mortgage.none")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    editorSection(L("real_estate.edit.main")) {
                        TextField(L("accounts_core.detail.sheet.edit.name"), text: $name)
                            .textInputAutocapitalization(.words)
                        Divider()
                        selectionRow(L("real_estate.about.type"), value: propertyType.localizedTitle, icon: propertyType.systemImage) {
                            showsTypePicker = true
                        }
                        Divider()
                        Picker(L("accounts_core.detail.sheet.edit.group"), selection: $selectedGroupID) {
                            Text(L("accounts_core.detail.sheet.edit.no_group")).tag(Optional<UUID>.none)
                            ForEach(groups, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }

                    editorSection(L("real_estate.edit.accounting")) {
                        Toggle(L("finances.add_account.total_impact.include"), isOn: $includeInTotal)
                            .tint(AppColors.toggleOnGreen)
                        Divider()
                        adaptiveValueRow(L("real_estate.about.currency"), value: account.currency)
                    }

                    editorSection(L("real_estate.gallery.title")) { gallery }

                    editorSection(nil) {
                        Button { withAnimation { showsAdditional.toggle() } } label: {
                            HStack {
                                Label(L("real_estate.edit.additional"), systemImage: "slider.horizontal.3")
                                Spacer()
                                Image(systemName: showsAdditional ? "chevron.up" : "chevron.down")
                            }
                        }
                        .buttonStyle(.plain)
                        if showsAdditional {
                            Divider()
                            TextField(L("accounts_core.detail.sheet.note_placeholder"), text: $note, axis: .vertical)
                                .lineLimit(2...6)
                            Divider()
                            selectionRow(L("real_estate.about.reminder"), value: reminder.localizedTitle, icon: "bell") {
                                showsReminderPicker = true
                            }
                            Divider()
                            selectionRow(L("real_estate.about.mortgage"), value: selectedLoanTitle, icon: "banknote") {
                                showsMortgagePicker = true
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(L("real_estate.edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L("accounts_core.detail.sheet.cancel"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel(L("accounts_core.detail.sheet.save"))
                        .disabled(trimmedName.isEmpty || isProcessingPhotos)
                }
            }
        }
        .sheet(isPresented: $showsTypePicker) { typePicker }
        .sheet(isPresented: $showsReminderPicker) { reminderPicker }
        .sheet(isPresented: $showsMortgagePicker) { mortgagePicker }
        .sheet(item: $previewPhoto) { photo in photoPreview(photo) }
        .alert(L("real_estate.photo.delete.title"), isPresented: Binding(
            get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }
        )) {
            Button(L("accounts_core.detail.sheet.cancel"), role: .cancel) { deleteCandidate = nil }
            Button(L("real_estate.photo.delete.action"), role: .destructive) { deletePhoto() }
        }
        .alert(L("real_estate.photo.error.title"), isPresented: Binding(
            get: { photoError != nil }, set: { if !$0 { photoError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(photoError ?? "") }
        .onChange(of: pickedItems) { _, items in Task { await process(items) } }
    }

    @ViewBuilder private func editorSection<Content: View>(_ title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.headline).foregroundStyle(AppColors.textSecondary) }
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.06)))
        }
    }

    private func selectionRow(_ title: String, value: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: icon).frame(width: 22).foregroundStyle(AppColors.brandPrimary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline).foregroundStyle(AppColors.textSecondary)
                    Text(value).foregroundStyle(AppColors.textPrimary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(AppColors.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("realEstate.selection.\(icon)")
        .accessibilityElement(children: .combine)
        .accessibilityHint(L("real_estate.selection.hint"))
    }

    private func adaptiveValueRow(_ title: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { Text(title); Spacer(); Text(value).foregroundStyle(AppColors.textSecondary) }
            VStack(alignment: .leading, spacing: 4) { Text(title); Text(value).foregroundStyle(AppColors.textSecondary) }
        }
    }

    @ViewBuilder private var gallery: some View {
        if photos.isEmpty { Text(L("real_estate.photo.empty")).foregroundStyle(AppColors.textSecondary) }
        else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        photoTile(photo, index: index)
                    }
                }
            }
        }
        PhotosPicker(
            selection: $pickedItems,
            maxSelectionCount: max(0, AccountAttachmentPolicy.maximumPhotos - photos.count),
            matching: .images
        ) {
            HStack {
                Label(L("real_estate.photo.add"), systemImage: "photo.badge.plus")
                Spacer()
                Text("\(photos.count)/\(AccountAttachmentPolicy.maximumPhotos)").foregroundStyle(AppColors.textTertiary)
                if isProcessingPhotos { ProgressView() }
            }
        }
        .disabled(photos.count >= AccountAttachmentPolicy.maximumPhotos || isProcessingPhotos)
    }

    private func photoTile(_ photo: RealEstatePhotoDraft, index: Int) -> some View {
        VStack(spacing: 6) {
            Button { previewPhoto = photo } label: {
                Group {
                    if let image = UIImage(data: photo.data) { Image(uiImage: image).resizable().scaledToFill() }
                    else { Image(systemName: "photo.badge.exclamationmark").font(.title) }
                }
                .frame(width: 112, height: 84).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    if photo.isCover { Image(systemName: "star.circle.fill").padding(5).foregroundStyle(.yellow) }
                }
            }
            HStack(spacing: 12) {
                Button { makeCover(photo.id) } label: { Image(systemName: "star") }
                    .accessibilityLabel(L("real_estate.photo.cover"))
                Button { move(index, by: -1) } label: { Image(systemName: "arrow.left") }.disabled(index == 0)
                    .accessibilityLabel(L("real_estate.photo.move_left"))
                Button { move(index, by: 1) } label: { Image(systemName: "arrow.right") }.disabled(index == photos.count - 1)
                    .accessibilityLabel(L("real_estate.photo.move_right"))
                Button(role: .destructive) { deleteCandidate = photo.id } label: { Image(systemName: "trash") }
                    .accessibilityLabel(L("real_estate.photo.delete.action"))
            }.font(.caption)
        }
    }

    private var typePicker: some View {
        compactPicker(title: L("real_estate.type.selection.title")) {
            ForEach(RealEstatePropertyType.allCases) { type in
                choiceRow(type.localizedTitle, icon: type.systemImage, selected: propertyType == type) {
                    propertyType = type; showsTypePicker = false
                }
            }
        }
    }

    private var reminderPicker: some View {
        compactPicker(title: L("real_estate.reminder.selection.title")) {
            ForEach(RealEstateReminder.allCases) { option in
                choiceRow(option.localizedTitle, icon: "bell", selected: reminder == option) {
                    reminder = option; showsReminderPicker = false
                }
            }
        }
    }

    private var mortgagePicker: some View {
        compactPicker(title: L("real_estate.mortgage.selection.title")) {
            choiceRow(L("real_estate.mortgage.none"), icon: "nosign", selected: selectedLoanID == nil) {
                selectedLoanID = nil; showsMortgagePicker = false
            }
            if eligibleLoans.isEmpty {
                ContentUnavailableView(L("real_estate.mortgage.empty.title"), systemImage: "banknote", description: Text(L("real_estate.mortgage.empty.message")))
                    .padding(.vertical, 24)
            } else {
                ForEach(eligibleLoans, id: \.id) { loan in
                    choiceRow(loan.name, icon: "banknote", selected: selectedLoanID == loan.id) {
                        selectedLoanID = loan.id; showsMortgagePicker = false
                    }
                }
            }
        }
    }

    private func compactPicker<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            ScrollView { LazyVStack(spacing: 0) { content() }.padding(16) }
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("accounts_core.detail.sheet.cancel")) { dismissPicker(title) } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func choiceRow(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).frame(width: 24).foregroundStyle(AppColors.brandPrimary)
                Text(title).foregroundStyle(AppColors.textPrimary)
                Spacer()
                if selected { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(AppColors.brandPrimary) }
            }.padding(.vertical, 14).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityIdentifier("realEstate.choice.\(title)")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dismissPicker(_ title: String) {
        if title == L("real_estate.type.selection.title") { showsTypePicker = false }
        else if title == L("real_estate.reminder.selection.title") { showsReminderPicker = false }
        else { showsMortgagePicker = false }
    }

    private func photoPreview(_ photo: RealEstatePhotoDraft) -> some View {
        NavigationStack {
            Group {
                if let image = UIImage(data: photo.data) { Image(uiImage: image).resizable().scaledToFit().padding() }
                else { ContentUnavailableView(L("real_estate.photo.corrupt.title"), systemImage: "photo.badge.exclamationmark") }
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("real_estate.photo.preview.close")) { previewPhoto = nil } } }
        }
    }

    private func process(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        await MainActor.run { isProcessingPhotos = true; photoError = nil }
        do {
            var processed: [RealEstatePhotoDraft] = []
            for item in items {
                guard let source = try await item.loadTransferable(type: Data.self) else { continue }
                processed.append(RealEstatePhotoDraft(data: try await AccountPhotoProcessor().process(source)))
            }
            await MainActor.run {
                if photos.isEmpty, !processed.isEmpty { processed[0].isCover = true }
                photos.append(contentsOf: processed.prefix(AccountAttachmentPolicy.maximumPhotos - photos.count))
                pickedItems = []; isProcessingPhotos = false
            }
        } catch {
            await MainActor.run { photoError = error.localizedDescription; pickedItems = []; isProcessingPhotos = false }
        }
    }

    private func makeCover(_ id: UUID) { for index in photos.indices { photos[index].isCover = photos[index].id == id } }
    private func move(_ index: Int, by offset: Int) { photos.swapAt(index, index + offset) }
    private func deletePhoto() {
        guard let id = deleteCandidate else { return }
        let wasCover = photos.first { $0.id == id }?.isCover == true
        photos.removeAll { $0.id == id }
        if wasCover, !photos.isEmpty { photos[0].isCover = true }
        deleteCandidate = nil
    }
    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(trimmedName, selectedGroup, trimmedNote.isEmpty ? nil : trimmedNote, includeInTotal, propertyType, reminder.persistedMonths, selectedLoanID, photos)
    }
}
