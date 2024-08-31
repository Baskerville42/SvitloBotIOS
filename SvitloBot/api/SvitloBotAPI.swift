//
//  SvitloBotAPI.swift
//  SvitloBot
//
//  Created by Alexander Tartmin on 10.09.2024.
//

import Foundation

class SvitloBotAPI: BaseAPI {
    
    func getChannelPing(_ channelKey: String) async throws -> (statusCode: Int, response: String) {
        var params = [String: String]()
        params["channel_key"] = channelKey
        return try await get(endpoint: "/channelPing", params: params)
    }
}
