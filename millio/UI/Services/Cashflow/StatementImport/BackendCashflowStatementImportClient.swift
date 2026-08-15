import Foundation

final class BackendCashflowStatementImportClient: CashflowStatementImportClient, @unchecked Sendable {
    let availability: CashflowStatementImportAvailability = .available
    private let authService: any AuthServiceProtocol
    private let configurationProvider: @Sendable () throws -> AuthConfiguration
    private let session: URLSession
    private let maxUploadBytes: Int

    init(
        authService: any AuthServiceProtocol,
        configurationProvider: @escaping @Sendable () throws -> AuthConfiguration,
        session: URLSession = .shared,
        maxUploadBytes: Int = 10 * 1_024 * 1_024
    ) {
        self.authService = authService
        self.configurationProvider = configurationProvider
        self.session = session
        self.maxUploadBytes = maxUploadBytes
    }

    func preview(fileURL: URL) async throws -> CashflowStatementPreviewDTO {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maxUploadBytes else {
            throw CashflowStatementImportError.invalidContract
        }
        let bytes = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        guard bytes.count <= maxUploadBytes else { throw CashflowStatementImportError.invalidContract }
        do {
            return try await request(bytes: bytes, filename: fileURL.lastPathComponent, forceRefresh: false)
        } catch CashflowStatementImportTransportError.unauthorized {
            return try await request(bytes: bytes, filename: fileURL.lastPathComponent, forceRefresh: true)
        }
    }

    private func request(bytes: Data, filename: String, forceRefresh: Bool) async throws -> CashflowStatementPreviewDTO {
        let configuration = try configurationProvider()
        let url = configuration.baseURL.appending(path: "bank-statements/preview")
        let token = try await authService.accessToken(forceRefresh: forceRefresh)
        let boundary = "MillioStatementBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(bytes: bytes, filename: filename, boundary: boundary)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CashflowStatementImportError.backendUnavailable }
        switch http.statusCode {
        case 200:
            guard data.count <= 2 * 1_024 * 1_024 else { throw CashflowStatementImportError.invalidContract }
            return try JSONDecoder().decode(CashflowStatementPreviewDTO.self, from: data)
        case 401: throw CashflowStatementImportTransportError.unauthorized
        case 415, 422: throw CashflowStatementImportError.unsupported
        default: throw CashflowStatementImportError.backendUnavailable
        }
    }

    private static func multipartBody(bytes: Data, filename: String, boundary: String) -> Data {
        let safeFilename = filename.replacingOccurrences(of: "\"", with: "_").replacingOccurrences(of: "\r", with: "_").replacingOccurrences(of: "\n", with: "_")
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(bytes)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}

private enum CashflowStatementImportTransportError: Error { case unauthorized }
