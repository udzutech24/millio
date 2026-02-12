import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Currency + Crypto support (names, aliases, emoji)

public struct CurrencySelectionSupport {
    public static let ruLocale = Locale(identifier: "ru_RU")
    public static let enLocale = Locale(identifier: "en_US_POSIX")

    // MARK: Crypto meta

    public struct CryptoMeta {
        public let code: String
        public let ruName: String
        public let enName: String
        public let emoji: String
    }

    /// Список крипты (порядок можно менять — так будет в allCodes, если ты захочешь выводить крипту отдельно)
    public static let cryptoList: [CryptoMeta] = [
        .init(code: "BTC",  ruName: "Биткоин",              enName: "Bitcoin",            emoji: "₿"),
        .init(code: "ETH",  ruName: "Эфириум",             enName: "Ethereum",           emoji: "◇"),
        .init(code: "USDT", ruName: "Tether",              enName: "Tether",             emoji: "🪙"),
        .init(code: "USDC", ruName: "USD Coin",            enName: "USD Coin",           emoji: "🪙"),
        .init(code: "BNB",  ruName: "BNB",                 enName: "BNB",                emoji: "🟡"),
        .init(code: "SOL",  ruName: "Solana",              enName: "Solana",             emoji: "🟣"),
        .init(code: "XRP",  ruName: "XRP",                 enName: "XRP",                emoji: "⚪️"),
        .init(code: "ADA",  ruName: "Cardano",             enName: "Cardano",            emoji: "🔵"),
        .init(code: "DOGE", ruName: "Dogecoin",            enName: "Dogecoin",           emoji: "🐶"),
        .init(code: "TON",  ruName: "Toncoin",             enName: "Toncoin",            emoji: "💎"),
        .init(code: "TRX",  ruName: "TRON",                enName: "TRON",               emoji: "🔺"),
        .init(code: "DOT",  ruName: "Polkadot",            enName: "Polkadot",           emoji: "🟣"),
        .init(code: "MATIC",ruName: "Polygon",             enName: "Polygon",            emoji: "🟪"),
        .init(code: "AVAX", ruName: "Avalanche",           enName: "Avalanche",          emoji: "🔺"),
        .init(code: "SHIB", ruName: "Shiba Inu",           enName: "Shiba Inu",          emoji: "🐕"),
        .init(code: "LTC",  ruName: "Litecoin",            enName: "Litecoin",           emoji: "Ł"),
        .init(code: "BCH",  ruName: "Bitcoin Cash",        enName: "Bitcoin Cash",       emoji: "🟧"),
        .init(code: "ATOM", ruName: "Cosmos",              enName: "Cosmos",             emoji: "⚛️"),
        .init(code: "LINK", ruName: "Chainlink",           enName: "Chainlink",          emoji: "🔗"),
        .init(code: "XLM",  ruName: "Stellar",             enName: "Stellar",            emoji: "⭐️"),
        .init(code: "ETC",  ruName: "Ethereum Classic",    enName: "Ethereum Classic",   emoji: "⟠"),
        .init(code: "FIL",  ruName: "Filecoin",            enName: "Filecoin",           emoji: "🗄️"),
        .init(code: "NEAR", ruName: "NEAR",                enName: "NEAR",               emoji: "🖤"),
        .init(code: "HBAR", ruName: "Hedera",              enName: "Hedera",             emoji: "🧩"),
        .init(code: "APT",  ruName: "Aptos",               enName: "Aptos",              emoji: "🌊"),
        .init(code: "OP",   ruName: "Optimism",            enName: "Optimism",           emoji: "🟥"),
        .init(code: "ARB",  ruName: "Arbitrum",            enName: "Arbitrum",           emoji: "🌀"),
        .init(code: "ICP",  ruName: "Internet Computer",   enName: "Internet Computer",  emoji: "∞"),
        .init(code: "SUI",  ruName: "Sui",                 enName: "Sui",                emoji: "💧"),
        .init(code: "PEPE", ruName: "Pepe",                enName: "Pepe",               emoji: "🐸")
    ]

    private static let cryptoByCode: [String: CryptoMeta] = {
        Dictionary(uniqueKeysWithValues: cryptoList.map { ($0.code.uppercased(), $0) })
    }()

    public static func isCrypto(_ code: String) -> Bool {
        cryptoByCode[code.uppercased()] != nil
    }

    // MARK: Aliases (for search)

    public static let aliases: [String: [String]] = {
        var base: [String: [String]] = [
            "RUB": ["рубль","руб","рубли","россия","рф","деревянный"],
            "USD": ["доллар","доллары","бакс","баксы","доллар сша","сша","американский доллар"],
            "EUR": ["евро","еврозона"],
            "GBP": ["фунт","фунты","фунт стерлингов","стерлингов","британский фунт","великобритания","англия"],
            "JPY": ["иена","йена","японская иена","япония"],
            "CNY": ["юань","китайский юань","ренминби","китай"],
            "KZT": ["тенге","казахстан"],
            "TRY": ["лира","турецкая лира","турция"],
            "UAH": ["гривна","украина"],
            "BYN": ["белорусский рубль","беларусь"],
            "AUD": ["австралийский доллар","австралия"],
            "CAD": ["канадский доллар","канада"],
            "CHF": ["швейцарский франк","франк","швейцария"],
            "PLN": ["злотый","польша"],
            "SEK": ["шведская крона","швеция","крона"],
            "NOK": ["норвежская крона","норвегия","крона"],
            "DKK": ["датская крона","дания","крона"],
            "CZK": ["чешская крона","чехия","крона"],
            "HUF": ["форинт","венгрия"],
            "AED": ["дирхам","оаэ","эмираты"],
            "AMD": ["драм","армения"],
            "GEL": ["лари","грузия"],
            "KGS": ["сом","кыргызстан","кыргызия"],
            "UZS": ["сум","узбекистан"],
            "AZN": ["манат","азербайджан"]
        ]

        // Crypto aliases — чтобы находилось и по русскому, и по англ, и по тикеру
        func addCryptoAliases(_ code: String, _ words: [String]) {
            base[code] = (base[code] ?? []) + words
        }

        addCryptoAliases("BTC",  ["btc","bitcoin","биткоин","биткойн","биток"])
        addCryptoAliases("ETH",  ["eth","ethereum","эфир","эфириум"])
        addCryptoAliases("USDT", ["usdt","tether","тезер","стейбл","стейблкоин"])
        addCryptoAliases("USDC", ["usdc","usd coin","стейбл","стейблкоин"])
        addCryptoAliases("BNB",  ["bnb","binance","бинанс"])
        addCryptoAliases("SOL",  ["sol","solana","солана"])
        addCryptoAliases("XRP",  ["xrp","ripple","рипл"])
        addCryptoAliases("ADA",  ["ada","cardano","кардано"])
        addCryptoAliases("DOGE", ["doge","dogecoin","додж"])
        addCryptoAliases("TON",  ["ton","toncoin","тон","тонкоин","телеграм"])
        addCryptoAliases("TRX",  ["trx","tron","трон"])
        addCryptoAliases("DOT",  ["dot","polkadot","полкадот"])
        addCryptoAliases("MATIC",["matic","polygon","полигон"])
        addCryptoAliases("AVAX", ["avax","avalanche","аваланш"])
        addCryptoAliases("SHIB", ["shib","shiba","шиба","шиба-ину"])
        addCryptoAliases("LTC",  ["ltc","litecoin","лайткоин"])
        addCryptoAliases("BCH",  ["bch","bitcoin cash","биткоин кэш"])
        addCryptoAliases("ATOM", ["atom","cosmos","космос"])
        addCryptoAliases("LINK", ["link","chainlink","чейнлинк"])
        addCryptoAliases("XLM",  ["xlm","stellar","стеллар"])
        addCryptoAliases("ETC",  ["etc","ethereum classic","эфир классик"])
        addCryptoAliases("FIL",  ["fil","filecoin","файлкоин"])
        addCryptoAliases("NEAR", ["near","ниар"])
        addCryptoAliases("HBAR", ["hbar","hedera","хедера"])
        addCryptoAliases("APT",  ["apt","aptos","аптос"])
        addCryptoAliases("OP",   ["op","optimism","оптимизм"])
        addCryptoAliases("ARB",  ["arb","arbitrum","арбитрум"])
        addCryptoAliases("ICP",  ["icp","internet computer","интернет компьютер"])
        addCryptoAliases("SUI",  ["sui","суи"])
        addCryptoAliases("PEPE", ["pepe","пепе","лягушка"])

        return base
    }()

    // MARK: Codes list

    /// ВСЕ ISO 4217 валюты + крипта (если includeCrypto = true)
    public static func allCodes(includeCrypto: Bool = true) -> [String] {
        var set = Set(Locale.Currency.isoCurrencies.map { $0.identifier.uppercased() })
        if includeCrypto {
            cryptoByCode.keys.forEach { set.insert($0) }
        }
        return set.sorted()
    }

    // MARK: Names / Emoji

    public static func nameRu(for code: String) -> String? {
        let c = code.uppercased()
        if let meta = cryptoByCode[c] { return meta.ruName }
        return ruLocale.localizedString(forCurrencyCode: c)
    }

    public static func nameEn(for code: String) -> String? {
        let c = code.uppercased()
        if let meta = cryptoByCode[c] { return meta.enName }
        return enLocale.localizedString(forCurrencyCode: c)
    }

    public static func emoji(for code: String) -> String {
        let c = code.uppercased()
        if let meta = cryptoByCode[c] { return meta.emoji }
        // Флаги эмодзи больше не используются, используется кастомная иконка "flag"
        return ""
    }

    // MARK: Flags for fiat (deprecated - используйте Image("flag") вместо этого)

    private static func flagEmoji(forCurrencyCode code: String) -> String {
        // Deprecated - флаги эмодзи больше не используются
        return ""
    }
    
    static func currencyToRegion(for currencyCode: String) -> String? {
        return currencyToRegionMap[currencyCode.uppercased()]
    }

    private static let currencyToRegionMap: [String: String] = {
        var map: [String: String] = [:]
        for id in Locale.availableIdentifiers {
            let loc = Locale(identifier: id)
            guard let c = loc.currency?.identifier.uppercased(),
                  let region = loc.region?.identifier.uppercased(),
                  map[c] == nil
            else { continue }
            map[c] = region
        }
        return map
    }()

    /// Полный список кодов валют для UI-пикеров.
    /// Собирается из локалей системы, чтобы не зависеть от загруженных курсов и наличия интернета.
    static let allCurrencyCodesForPicker: [String] = {
        var set = Set<String>()
        
        for id in Locale.availableIdentifiers {
            let loc = Locale(identifier: id)
            if let code = loc.currency?.identifier.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !code.isEmpty {
                set.insert(code)
            }
        }
        
        if #available(iOS 16.0, *) {
            for code in Locale.commonISOCurrencyCodes {
                let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if !normalized.isEmpty {
                    set.insert(normalized)
                }
            }
        }
        
        set.insert("USD")
        return Array(set).sorted()
    }()
    
    static func pinnedCurrencyCodes(for current: String) -> [String] {
        let base = ["RUB", "USD", "EUR"]
        let normalizedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalizedCurrent.isEmpty {
            return base
        }
        if base.contains(normalizedCurrent) {
            return base
        }
        return [normalizedCurrent] + base
    }
}

// MARK: - Picker with pinned favorites on top + RU/EN search

public struct CurrencyPickerView: View {
    public let allCodes: [String]
    @Binding public var searchText: String
    public let selectedCodes: [String]   // закрепленные сверху (контекстно: избранные / выбранные)
    public let favoriteCodes: Set<String>
    public let currentSelection: String?
    public let onToggleFavorite: ((String) -> Void)?
    public let onSelect: (String) -> Void

    public init(
        allCodes: [String],
        searchText: Binding<String>,
        selectedCodes: [String],
        favoriteCodes: Set<String> = [],
        currentSelection: String? = nil,
        onToggleFavorite: ((String) -> Void)? = nil,
        onSelect: @escaping (String) -> Void
    ) {
        self.allCodes = allCodes.map { $0.uppercased() }
        self._searchText = searchText
        self.selectedCodes = selectedCodes.map { $0.uppercased() }
        self.favoriteCodes = Set(favoriteCodes.map { $0.uppercased() })
        self.currentSelection = currentSelection?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.onToggleFavorite = onToggleFavorite
        self.onSelect = onSelect
    }

    private var q: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func matches(_ code: String) -> Bool {
        let c = code.uppercased()
        guard !q.isEmpty else { return true }

        let codeL = c.lowercased()
        let ru = (CurrencySelectionSupport.nameRu(for: c) ?? "").lowercased()
        let en = (CurrencySelectionSupport.nameEn(for: c) ?? "").lowercased()
        let aliases = CurrencySelectionSupport.aliases[c]?.map { $0.lowercased() } ?? []

        if codeL.contains(q) { return true }
        if ru.contains(q) { return true }
        if en.contains(q) { return true }
        if aliases.contains(where: { $0.contains(q) }) { return true }

        return false
    }

    /// Все совпадения (кроме избранных, они будут отдельной секцией сверху)
    private var filteredOthers: [String] {
        let setSelected = Set(selectedCodes)
        return allCodes
            .filter { matches($0) }
            .filter { !setSelected.contains($0.uppercased()) }
            .sorted()
    }

    /// Избранные сверху (закреплены). Можно: показывать только те, что совпадают с поиском.
    private var pinnedFavorites: [String] {
        // Вариант A: показывать избранные всегда
        // return selectedCodes

        // Вариант B (лучше): избранные сверху, но только если подходят под поиск
        if q.isEmpty { return selectedCodes }
        return selectedCodes.filter { matches($0) }
    }

    public var body: some View {
        ZStack {
            GradientBackground()
            
            VStack(spacing: 0) {
                InlineSearchBar(text: $searchText, placeholder: "Код или название (RU/EN)")
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if !pinnedFavorites.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Избранные")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 8)

                                SelectionSectionCard {
                                    ForEach(Array(pinnedFavorites.enumerated()), id: \.element) { index, code in
                                        currencyRow(
                                            code: code,
                                            isSelected: currentSelection == code.uppercased(),
                                            isFavorite: true,
                                            showDivider: index != pinnedFavorites.count - 1,
                                            dividerColor: AppColors.textPrimary.opacity(0.08)
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        if !filteredOthers.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                // Если есть избранные, отступаем больше
                                // Если избранных нет (например, поиск всё отфильтровал), то отступ меньше
                                let topPadding: CGFloat = pinnedFavorites.isEmpty ? 8 : 16
                                
                                // Заголовок секции, если нужно (в дизайне "Все валюты" может не быть, но оставим для ясности)
                                // На скрине "Избранные" есть. А для списка ниже заголовка не видно, но лучше оставить или убрать?
                                // Оставим как было, но с более мелким шрифтом как "Избранные"
                                
                                // Но на скрине после "Избранные" идет просто список.
                                // Если избранных нет, то список просто идет.
                                // Оставим заголовок, чтобы разделять.
                                
                                Text("Все валюты")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .padding(.horizontal, 20)
                                    .padding(.top, topPadding)

                                SelectionSectionCard {
                                    ForEach(Array(filteredOthers.enumerated()), id: \.element) { index, code in
                                        let uppercasedCode = code.uppercased()
                                        currencyRow(
                                            code: uppercasedCode,
                                            isSelected: currentSelection == uppercasedCode,
                                            isFavorite: favoriteCodes.contains(uppercasedCode),
                                            showDivider: index != filteredOthers.count - 1,
                                            dividerColor: AppColors.textPrimary.opacity(0.08)
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        // Важно: это помогает вводить и тикеры (BTC), и англ. слова — без автозамены
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
        .keyboardType(.asciiCapable)
    }

    @ViewBuilder
    private func currencyIcon(for code: String) -> some View {
        let c = code.uppercased()
        
        if CurrencySelectionSupport.isCrypto(c) {
            // Для криптовалют используем эмодзи через Text
            let emoji = CurrencySelectionSupport.emoji(for: c)
            if !emoji.isEmpty {
                Text(emoji)
                    .frame(width: 16, height: 16)
            } else {
                Image("flag")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 16, height: 16)
            }
        } else {
            // Для фиатных валют пытаемся загрузить флаг по коду
            let flagName = "flag_\(c.lowercased())"
            #if os(iOS)
            if UIImage(named: flagName) != nil {
                Image(flagName)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 16, height: 16)
            } else {
                Image("flag")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 16, height: 16)
            }
            #else
            Image("flag")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: 16, height: 16)
            #endif
        }
    }

    @ViewBuilder
    private func currencyRow(
        code: String,
        isSelected: Bool,
        isFavorite: Bool,
        showDivider: Bool,
        dividerColor: Color
    ) -> some View {
        let c = code.uppercased()
        let ruName = CurrencySelectionSupport.nameRu(for: c) ?? ""

        SelectionItemRow(
            title: c,
            subtitle: ruName.isEmpty ? nil : ruName,
            isSelected: isSelected,
            dividerColor: dividerColor,
            showDivider: showDivider,
            onTap: { onSelect(c) },
            leading: {
                currencyIcon(for: c)
            },
            trailing: {
                if let onToggleFavorite {
                    Button {
                        onToggleFavorite(c)
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.coursesGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .opacity(isFavorite ? 1 : 0.55)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("currencyPicker.favorite.\(c)")
                } else {
                    EmptyView()
                }
            }
        )
    }
}
