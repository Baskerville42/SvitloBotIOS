import Foundation
import Security

struct TelegramBotProfile: Decodable {
    let id: Int64
    let isBot: Bool
    let firstName: String
    let username: String?

    enum CodingKeys: String, CodingKey {
        case id
        case isBot = "is_bot"
        case firstName = "first_name"
        case username
    }
}

struct TelegramMember: Decodable {
    let status: String
    let canPostMessages: Bool?

    enum CodingKeys: String, CodingKey {
        case status
        case canPostMessages = "can_post_messages"
    }
}

struct TelegramChat: Decodable {
    let id: Int64
    let type: String
}

struct TelegramSentMessage: Decodable {
    let messageID: Int64

    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
    }
}

private struct TelegramEnvelope<Result: Decodable>: Decodable {
    let ok: Bool
    let result: Result?
    let description: String?
}

final class TelegramAPI {
    func getMe(token: String) async throws -> TelegramBotProfile {
        try await request(token: token, method: "getMe")
    }

    func getChat(token: String, chatID: String) async throws -> TelegramChat {
        try await request(token: token, method: "getChat", parameters: ["chat_id": Self.chatIdentifier(chatID)])
    }

    func getChatMember(token: String, chatID: String, userID: Int64) async throws -> TelegramMember {
        try await request(token: token, method: "getChatMember", parameters: [
            "chat_id": Self.chatIdentifier(chatID),
            "user_id": userID
        ])
    }

    func sendMessage(token: String, chatID: String, text: String) async throws -> TelegramSentMessage {
        try await request(token: token, method: "sendMessage", parameters: [
            "chat_id": Self.chatIdentifier(chatID),
            "text": text
        ])
    }

    private func request<Result: Decodable>(
        token: String,
        method: String,
        parameters: [String: Any]? = nil
    ) async throws -> Result {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/\(method)") else {
            throw TelegramAPIError.invalidToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        if let parameters {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: TelegramAPIError.requestFailed)
                }
            }.resume()
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TelegramAPIError.requestFailed
        }

        let envelope = try JSONDecoder().decode(TelegramEnvelope<Result>.self, from: data)
        guard envelope.ok, let result = envelope.result else {
            throw TelegramAPIError.apiFailure(envelope.description ?? "Telegram API error")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw TelegramAPIError.requestFailed
        }
        return result
    }

    private static func chatIdentifier(_ value: String) -> Any {
        if let numericID = Int64(value) { return numericID }
        return value
    }
}

enum TelegramTokenStore {
    private static let service = "in.svitlobot.ios.telegram-bot"
    private static let account = "bot-token"

    static func read() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { return "" }
        return token
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        guard !token.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }

        let data = Data(token.utf8)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            update.forEach { insert[$0.key] = $0.value }
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }
}

enum TelegramAPIError: LocalizedError {
    case invalidToken
    case requestFailed
    case apiFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "telegram.error.invalid_token".localized
        case .requestFailed:
            return "telegram.error.request_failed".localized
        case .apiFailure(let message):
            return message
        }
    }
}
