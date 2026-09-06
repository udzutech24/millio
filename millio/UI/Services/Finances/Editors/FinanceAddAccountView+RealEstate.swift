import SwiftUI
import SwiftData
import PhotosUI

/// Недвижимость: блок создания и обработка выбранных фотографий.
extension FinanceAddAccountView {
    var realEstateCreationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: L("real_estate.edit.object"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    Picker(L("real_estate.about.type"), selection: $realEstatePropertyType) {
                        ForEach(RealEstatePropertyType.allCases) { type in
                            Text(type.localizedTitle).tag(type)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    FinancesRowDivider(leadingPadding: 16)
                    PhotosPicker(
                        selection: $realEstatePhotoItems,
                        maxSelectionCount: AccountAttachmentPolicy.maximumPhotos,
                        matching: .images
                    ) {
                        HStack {
                            Label(L("real_estate.photo.add"), systemImage: "photo.badge.plus")
                            Spacer()
                            if isProcessingRealEstatePhotos { ProgressView() }
                            Text("\(realEstatePhotoData.count)/\(AccountAttachmentPolicy.maximumPhotos)")
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                    }
                    .disabled(isProcessingRealEstatePhotos)
                    if let realEstatePhotoError {
                        Text(realEstatePhotoError)
                            .font(.millioCaptionRegular)
                            .foregroundStyle(AppColors.error)
                            .padding(.horizontal, 16).padding(.bottom, 12)
                    }
                }
            }
        }
        .onChange(of: realEstatePhotoItems) { _, items in
            Task { await processRealEstateDraftPhotos(items) }
        }
    }

    func processRealEstateDraftPhotos(_ items: [PhotosPickerItem]) async {
        await MainActor.run { isProcessingRealEstatePhotos = true; realEstatePhotoError = nil }
        do {
            var processed: [Data] = []
            for item in items.prefix(AccountAttachmentPolicy.maximumPhotos) {
                guard let source = try await item.loadTransferable(type: Data.self) else {
                    throw AccountPhotoProcessorError.invalidImage
                }
                processed.append(try await AccountPhotoProcessor().process(source))
            }
            await MainActor.run { realEstatePhotoData = processed; isProcessingRealEstatePhotos = false }
        } catch {
            await MainActor.run {
                realEstatePhotoData = []
                realEstatePhotoError = error.localizedDescription
                isProcessingRealEstatePhotos = false
            }
        }
    }
}
