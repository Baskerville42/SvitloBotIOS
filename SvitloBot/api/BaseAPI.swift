//
//  BaseAPI.swift
//  SvitloBot
//
//  Created by Alexander Tartmin on 10.09.2024.
//

import Foundation

class BaseAPI {
    
    func get(endpoint: String, params: [String: AnyHashable]? = nil) async throws -> (statusCode: Int, response: String) {
        let request = APIUtils.createURLRequest(method: "GET", url: endpoint, params: params)
        return try await executeRequest(request: request)
    }
    
    private func executeRequest(request: URLRequest) async throws -> (Int, String) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "BaseAPIError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            
            let statusCode = httpResponse.statusCode
            
            if !(200...299).contains(statusCode) {
                throw NSError(domain: "BaseAPIError", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Request failed with status code: \(statusCode)"])
            }
            
            if let stringResponse = String(data: data, encoding: .utf8) {
                return (statusCode, stringResponse)
            } else {
                throw NSError(domain: "BaseAPIError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to convert response to string"])
            }
        } catch {
            print("Request failed with error: \(error.localizedDescription)")
            throw error
        }
    }
}

