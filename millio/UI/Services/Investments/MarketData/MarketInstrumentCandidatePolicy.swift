import Foundation

enum MarketInstrumentCandidatePolicy {
    static func rankBulkImportCandidates(
        _ candidates: [StockBulkImportCandidate],
        query: String,
        preferredMarket: String?
    ) -> [StockBulkImportCandidate] {
        let normalizedQuery = MarketSymbolSearchEngine.normalize(query)
        let normalizedPreferredMarket = StockBulkImportMarketNormalizer.normalize(preferredMarket)

        return candidates.sorted { lhs, rhs in
            let lhsScore = bulkImportScore(lhs, query: normalizedQuery, preferredMarket: normalizedPreferredMarket)
            let rhsScore = bulkImportScore(rhs, query: normalizedQuery, preferredMarket: normalizedPreferredMarket)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }

            let leftMarket = lhs.normalizedMarket ?? "ZZZ"
            let rightMarket = rhs.normalizedMarket ?? "ZZZ"
            if leftMarket != rightMarket {
                return leftMarket < rightMarket
            }

            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func bulkImportScore(
        _ candidate: StockBulkImportCandidate,
        query: String,
        preferredMarket: String?
    ) -> Int {
        let normalizedSymbol = MarketSymbolSearchEngine.normalize(candidate.symbol)
        let normalizedName = MarketSymbolSearchEngine.normalize(candidate.displayName)
        let normalizedMarket = candidate.normalizedMarket

        var score = 0

        if normalizedSymbol == query { score += 10_000 }
        else if normalizedSymbol.hasPrefix(query) { score += 8_500 }
        else if normalizedName == query { score += 8_300 }
        else if normalizedName.hasPrefix(query) { score += 8_000 }
        else if normalizedName.contains(query) { score += 7_600 }

        if let preferredMarket {
            if preferredMarket == "US" {
                if let normalizedMarket,
                   ["NASDAQ", "NYSE", "AMEX", "BATS", "IEX", "US"].contains(normalizedMarket) {
                    score += 500
                }
            } else if normalizedMarket == preferredMarket {
                score += 600
            }
        }

        switch normalizedMarket {
        case "NASDAQ":
            score += 120
        case "NYSE":
            score += 110
        case "AMEX":
            score += 100
        case "US":
            score += 90
        default:
            break
        }

        return score
    }
}
