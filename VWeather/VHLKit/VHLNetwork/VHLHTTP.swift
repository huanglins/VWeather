//
//  VHLHTTP.swift
//  VWeather
//
//  最小 HTTP 客户端。仅 GET + JSON 解码，够用即可，不引第三方依赖。
//

import Foundation

enum VHLHTTPError: LocalizedError {
    case badURL
    case status(Int)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .badURL:            return "URL 构造失败"
        case .status(let code):  return "HTTP \(code)"
        case .decoding(let e):   return "解码失败：\(e)"
        case .transport(let e):  return "网络错误：\(e.localizedDescription)"
        }
    }
}

struct VHLHTTP {
    static let shared = VHLHTTP()

    private let session: URLSession

    init(timeout: TimeInterval = 10) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        // 缓存由服务端 Redis 与本地 SQLite 快照负责，URLSession 不再自行缓存，避免拿到过期预警
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    /// GET 并解码为 T。
    func get<T: Decodable>(_ url: URL, query: [String: String] = [:]) async throws -> T {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw VHLHTTPError.badURL
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let finalURL = components.url else { throw VHLHTTPError.badURL }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: finalURL)
        } catch {
            throw VHLHTTPError.transport(error)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw VHLHTTPError.status(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw VHLHTTPError.decoding(error)
        }
    }
}
