import SwiftData
import SwiftUI
import UIKit

struct RealEstateDetailSection: View {
    let account: Account
    let modelContext: ModelContext
    let refreshToken: UUID
    let onEdit: () -> Void

    @Query private var profiles: [RealEstateProfile]
    @Query private var attachments: [AccountAttachment]
    @State private var presentedPhoto: AccountAttachment?

    init(
        account: Account,
        modelContext: ModelContext,
        refreshToken: UUID,
        onEdit: @escaping () -> Void = {}
    ) {
        self.account = account
        self.modelContext = modelContext
        self.refreshToken = refreshToken
        self.onEdit = onEdit
        let accountID = account.id
        _profiles = Query(filter: #Predicate<RealEstateProfile> { $0.accountID == accountID })
        _attachments = Query(
            filter: #Predicate<AccountAttachment> { $0.accountID == accountID },
            sort: [SortDescriptor(\AccountAttachment.order), SortDescriptor(\AccountAttachment.createdAt)]
        )
    }

    private var photos: [AccountAttachment] { attachments.filter { $0.kind == .photo } }
    private var isReadOnly: Bool {
        RealEstateEditPolicy.isReadOnly(archivedAt: account.archivedAt, deletedAt: account.deletedAt)
    }
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
    private var presentation: RealEstateDetailPresentation {
        RealEstateDetailPresentation.make(summary: summary, currency: account.currency, equity: equity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            summarySection
                .padding(.top, AppSpacing.m)
            valuationChart
                .padding(.top, AppSpacing.l)
            gallery
                .padding(.top, AppSpacing.l)
            aboutCard
                .padding(.top, AppSpacing.l)
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
            .frame(height: 240)
            .clipped()

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.2), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 112)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            VStack {
                HStack {
                    Spacer()
                    if !isReadOnly {
                        Button(action: onEdit) {
                            Image(systemName: "gearshape.fill")
                                .font(.millioCalloutSemibold)
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("accounts_core.detail.action.edit"))
                    }
                }
                Spacer()
                HStack {
                    Label(propertyTypeTitle, systemImage: "building.2.fill")
                        .font(.millioCaption)
                        .padding(.horizontal, AppSpacing.s)
                        .padding(.vertical, AppSpacing.xs)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }
            }
            .padding(AppSpacing.s)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.l, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { if let cover { presentedPhoto = cover } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("real_estate.hero.accessibility"))
        .accessibilityAddTraits(cover == nil ? [] : .isButton)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(L("real_estate.valuation.title"))
                    .font(.millioCaption)
                    .foregroundStyle(AppColors.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                    Text(presentation.currentValue)
                        .font(.millioTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(presentation.currency)
                        .font(.millioBody)
                        .foregroundStyle(AppColors.textTertiary)
                }
                Text(presentation.lastValuationDate)
                    .font(.millioCalloutRegular)
                    .foregroundStyle(AppColors.textSecondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: AppSpacing.s) { summaryMetrics }
                VStack(alignment: .leading, spacing: AppSpacing.s) { summaryMetrics }
            }

            if let equity = presentation.equity {
                detailRow(L("real_estate.valuation.equity"), "\(equity) \(presentation.currency)")
            }
            if !account.includeInTotal {
                Label(L("accounts_core.detail.total.excluded"), systemImage: "sum")
                    .font(.millioCaptionRegular)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.s)
                    .padding(.vertical, AppSpacing.xs)
                    .background(Capsule().fill(AppColors.iconBackground))
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var summaryMetrics: some View {
        metric(L("real_estate.valuation.change"), value: presentation.delta, tone: summary.delta)
        metric(L("real_estate.valuation.percent"), value: presentation.percentDelta, tone: summary.percentDelta)
        metric(
            L("real_estate.valuation.age"),
            value: summary.ageInDays.map { String(format: L("real_estate.valuation.days"), $0) } ?? presentation.ageInDays
        )
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
            if photos.isEmpty {
                Label(L("real_estate.photo.empty"), systemImage: "photo")
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppSpacing.m)
                    .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(AppColors.iconBackground))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.s) {
                        ForEach(photos, id: \.id) { photo in photoTile(photo) }
                    }
                }
            }
        }
    }

    private func photoTile(_ photo: AccountAttachment) -> some View {
        Group {
            if let image = UIImage(data: photo.mediaData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo.badge.exclamationmark").foregroundStyle(AppColors.textTertiary)
            }
        }
        .frame(width: 132, height: 92)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.s))
        .contentShape(Rectangle())
        .onTapGesture { presentedPhoto = photo }
        .accessibilityLabel(L("real_estate.photo.preview"))
        .accessibilityAddTraits(.isButton)
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

    private func metric(_ title: String, value: String, tone: Decimal? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.millioCaptionRegular).foregroundStyle(AppColors.textTertiary)
            Text(value)
                .font(.millioCalloutSemibold)
                .foregroundStyle(metricColor(tone))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.s)
        .background(RoundedRectangle(cornerRadius: AppSpacing.s).fill(AppColors.iconBackground))
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).foregroundStyle(AppColors.textPrimary)
        }.font(.millioCalloutRegular)
    }

    private func metricColor(_ value: Decimal?) -> Color {
        guard let value else { return AppColors.textPrimary }
        if value > 0 { return AppColors.positiveColor }
        if value < 0 { return AppColors.negativeColor }
        return AppColors.textPrimary
    }
}
