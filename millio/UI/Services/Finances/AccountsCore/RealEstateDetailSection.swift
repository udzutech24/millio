import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct RealEstateDetailSection: View {
    let account: Account
    let modelContext: ModelContext
    let refreshToken: UUID

    @Query private var profiles: [RealEstateProfile]
    @Query private var attachments: [AccountAttachment]
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var presentedPhoto: AccountAttachment?
    @State private var deleteCandidate: AccountAttachment?
    @State private var errorMessage: String?

    init(account: Account, modelContext: ModelContext, refreshToken: UUID) {
        self.account = account
        self.modelContext = modelContext
        self.refreshToken = refreshToken
        let accountID = account.id
        _profiles = Query(filter: #Predicate<RealEstateProfile> { $0.accountID == accountID })
        _attachments = Query(
            filter: #Predicate<AccountAttachment> { $0.accountID == accountID },
            sort: [SortDescriptor(\AccountAttachment.order), SortDescriptor(\AccountAttachment.createdAt)]
        )
    }

    private var photos: [AccountAttachment] { attachments.filter { $0.kind == .photo } }
    private var isReadOnly: Bool { account.archivedAt != nil || account.deletedAt != nil }
    private var cover: AccountAttachment? { photos.first(where: \.isCover) ?? photos.first }
    private var summary: RealEstateValuationSummary {
        _ = refreshToken
        return RealEstateValuationCalculator.summary(events: account.events ?? [])
    }
    private var linkedLoan: Account? {
        guard let id = account.manualAssetMeta?.linkedLoanID else { return nil }
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })
        guard let loan = try? modelContext.fetch(descriptor).first,
              loan.kind == .loan,
              loan.currency == account.currency else { return nil }
        return loan
    }
    private var equity: Decimal? {
        guard let linkedLoan, let value = summary.currentValue else { return nil }
        let debt = AccountBalanceEngine.balanceAt(events: linkedLoan.events ?? [], kind: .loan, on: Date())
        return value - abs(debt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            hero
            valuationCard
            valuationChart
            gallery
            aboutCard
        }
        .sheet(item: $presentedPhoto) { photo in
            NavigationStack {
                Group {
                    if let image = UIImage(data: photo.mediaData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .accessibilityLabel(L("real_estate.photo.preview"))
                    } else {
                        ContentUnavailableView(
                            L("real_estate.photo.corrupt.title"),
                            systemImage: "photo.badge.exclamationmark",
                            description: Text(L("real_estate.photo.corrupt.message"))
                        )
                    }
                }
                .navigationTitle(account.name)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("accounts_core.detail.sheet.cancel")) { presentedPhoto = nil }
                    }
                }
            }
        }
        .alert(L("real_estate.photo.delete.title"), isPresented: Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        )) {
            Button(L("real_estate.photo.delete.action"), role: .destructive) {
                guard let deleteCandidate else { return }
                perform { try AccountAttachmentService(modelContext: modelContext).delete(deleteCandidate) }
            }
            Button(L("accounts_core.detail.sheet.cancel"), role: .cancel) {}
        }
        .alert(L("accounts_core.detail.error.title"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button(L("accounts_core.detail.sheet.cancel"), role: .cancel) {} } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let cover, let image = UIImage(data: cover.mediaData) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    LinearGradient(
                        colors: [AppColors.brandPrimary.opacity(0.85), AppColors.iconBackground],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "house.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipped()

            HStack {
                Label(propertyTypeTitle, systemImage: "building.2.fill")
                    .font(.millioCaption)
                    .padding(.horizontal, AppSpacing.s)
                    .padding(.vertical, AppSpacing.xs)
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
                if !isReadOnly && photos.count < AccountAttachmentPolicy.maximumPhotos {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(L("real_estate.photo.add"), systemImage: "photo.badge.plus")
                            .font(.millioCaption)
                            .padding(.horizontal, AppSpacing.s)
                            .padding(.vertical, AppSpacing.xs)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
            }
            .padding(AppSpacing.s)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.l, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { if let cover { presentedPhoto = cover } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("real_estate.hero.accessibility"))
    }

    private var valuationCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text(L("real_estate.valuation.title")).font(.millioCaption).foregroundStyle(AppColors.textTertiary)
            if let date = summary.lastValuationDate {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.millioCalloutRegular).foregroundStyle(AppColors.textSecondary)
            }
            HStack {
                metric(L("real_estate.valuation.change"), value: summary.delta.map(formattedSigned) ?? "—")
                metric(L("real_estate.valuation.percent"), value: summary.percentDelta.map { "\(formattedSigned($0))%" } ?? "—")
                metric(L("real_estate.valuation.age"), value: summary.ageInDays.map { String(format: L("real_estate.valuation.days"), $0) } ?? "—")
            }
            if let equity {
                detailRow(L("real_estate.valuation.equity"), "\(formattedSigned(equity)) \(account.currency)")
            }
        }
        .padding(AppSpacing.m)
        .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(AppColors.iconBackground))
    }

    private var valuationEvents: [AccountEvent] {
        (account.events ?? [])
            .filter { $0.type == .openingBalance || $0.type == .revaluation }
            .sorted { $0.date != $1.date ? $0.date < $1.date : $0.createdAt < $1.createdAt }
    }

    @ViewBuilder
    private var valuationChart: some View {
        if valuationEvents.count >= 2 {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Text(L("real_estate.valuation.history"))
                    .font(.millioCaption).foregroundStyle(AppColors.textTertiary)
                GeometryReader { proxy in
                    let values = valuationEvents.compactMap(\.amount)
                    let minimum = values.min() ?? 0
                    let maximum = values.max() ?? 0
                    let span = max(maximum - minimum, 1)
                    Path { path in
                        var previousY: CGFloat?
                        for (index, value) in values.enumerated() {
                            let x = proxy.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                            let normalized = NSDecimalNumber(decimal: (value - minimum) / span).doubleValue
                            let y = proxy.size.height * CGFloat(1 - normalized)
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else if let previousY {
                                path.addLine(to: CGPoint(x: x, y: previousY))
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                            previousY = y
                        }
                    }
                    .stroke(AppColors.brandPrimary, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                }
                .frame(height: 112)
                .accessibilityLabel(L("real_estate.valuation.chart.accessibility"))
            }
            .padding(AppSpacing.m)
            .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(AppColors.iconBackground))
        }
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack {
                Text(L("real_estate.gallery.title")).font(.millioCaption).foregroundStyle(AppColors.textTertiary)
                Spacer()
                Text("\(photos.count)/\(AccountAttachmentPolicy.maximumPhotos)")
                    .font(.millioCaptionRegular).foregroundStyle(AppColors.textTertiary)
            }
            if photos.isEmpty && !isReadOnly {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(L("real_estate.photo.empty"), systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity).padding(AppSpacing.m)
                        .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(AppColors.iconBackground))
                }
            } else if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.s) {
                        ForEach(photos, id: \.id) { photo in photoTile(photo) }
                    }
                }
            }
        }
    }

    private func photoTile(_ photo: AccountAttachment) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Group {
                if let image = UIImage(data: photo.mediaData) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo.badge.exclamationmark").foregroundStyle(AppColors.textTertiary)
                }
            }
            .frame(width: 116, height: 82).clipped()
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.s))
            .onTapGesture { presentedPhoto = photo }
            if !isReadOnly {
              HStack(spacing: AppSpacing.s) {
                Button { perform { try AccountAttachmentService(modelContext: modelContext).setCover(photo) } } label: {
                    Image(systemName: photo.isCover ? "star.fill" : "star")
                }.accessibilityLabel(L("real_estate.photo.cover"))
                Button { move(photo, offset: -1) } label: { Image(systemName: "chevron.left") }
                    .disabled(photo.order == 0)
                    .accessibilityLabel(L("real_estate.photo.move_left"))
                Button { move(photo, offset: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(photo.order >= photos.count - 1)
                    .accessibilityLabel(L("real_estate.photo.move_right"))
                Button(role: .destructive) { deleteCandidate = photo } label: { Image(systemName: "trash") }
                    .accessibilityLabel(L("real_estate.photo.delete.action"))
              }
              .font(.millioCaption)
            }
        }
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text(L("real_estate.about.title")).font(.millioCaption).foregroundStyle(AppColors.textTertiary)
            detailRow(L("real_estate.about.type"), propertyTypeTitle)
            detailRow(L("accounts_core.detail.sheet.edit.group"), account.group?.name ?? L("accounts_core.detail.sheet.edit.no_group"))
            detailRow(L("real_estate.about.currency"), account.currency)
            if let reminder = account.manualAssetMeta?.revalReminderMonths {
                detailRow(L("real_estate.about.reminder"), String(format: L("real_estate.about.reminder.months"), reminder))
            }
            if let linkedLoan { detailRow(L("real_estate.about.mortgage"), linkedLoan.name) }
            if let note = account.note, !note.isEmpty { detailRow(L("real_estate.about.note"), note) }
        }
        .padding(AppSpacing.m)
        .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(AppColors.iconBackground))
    }

    private var propertyTypeTitle: String {
        (profiles.first?.propertyType ?? .other).localizedTitle
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.millioCaptionRegular).foregroundStyle(AppColors.textTertiary)
            Text(value).font(.millioCalloutSemibold).foregroundStyle(AppColors.textPrimary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).foregroundStyle(AppColors.textPrimary)
        }.font(.millioCalloutRegular)
    }

    private func formattedSigned(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }

    private func move(_ photo: AccountAttachment, offset: Int) {
        var ids = photos.map(\.id)
        guard let index = ids.firstIndex(of: photo.id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset)
        perform { try AccountAttachmentService(modelContext: modelContext).reorder(accountID: account.id, orderedIDs: ids) }
    }

    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { errorMessage = error.localizedDescription }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw AccountPhotoProcessorError.invalidImage
            }
            let processed = try await AccountPhotoProcessor().process(data)
            try await MainActor.run {
                try AccountAttachmentService(modelContext: modelContext).addPhoto(accountID: account.id, processedData: processed)
                selectedPhoto = nil
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription; selectedPhoto = nil }
        }
    }
}
