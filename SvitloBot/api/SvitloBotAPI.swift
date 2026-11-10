//
//  SvitloBotAPI.swift
//  SvitloBot
//
//  Created by Alexander Tartmin on 10.09.2024.
//

import CryptoKit
import Foundation
import UIKit

class SvitloBotAPI: BaseAPI {

    func getChannelPing(_ channelKey: String) async throws -> (statusCode: Int, response: String) {
        let params = await Self.pingParameters(channelKey)
        return try await get(endpoint: "/channelPing", params: params)
    }

    func sendChannelPingOff(_ channelKey: String) async throws -> (statusCode: Int, response: String) {
        let params = await Self.pingParameters(channelKey)
        return try await get(endpoint: "/channelPingOff", params: params)
    }

    func getChannelStatus(_ channelKey: String) async throws -> (statusCode: Int, response: String) {
        var params = [String: String]()
        params["channel_key"] = channelKey
        return try await get(
            endpoint: "/status",
            params: params,
            headers: [
                "Accept": "text/html,*/*",
                "User-Agent": "Mozilla/5.0 SvitloBot-iOS/1.0",
            ]
        )
    }

    @MainActor
    private static func pingParameters(_ channelKey: String) -> [String: String] {
        let device = UIDevice.current
        let model = hardwareModelName ?? device.model
        var params = ["channel_key": channelKey, "model": String(model.prefix(64))]

        // The system may withhold IDFV until the first unlock after reboot.
        if let vendorID = device.identifierForVendor {
            let digest = SHA256.hash(data: Data(vendorID.uuidString.lowercased().utf8))
            let shortHash = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
            params["device"] = "ios-\(shortHash)"
        }

        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            !version.isEmpty
        {
            params["app"] = String(version.prefix(16))
        }
        return params
    }

    private static let hardwareModelName: String? = {
        #if targetEnvironment(simulator)
            guard let identifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] else {
                return nil
            }
        #else
            var systemInfo = utsname()
            guard uname(&systemInfo) == 0 else { return nil }
            let identifier = withUnsafeBytes(of: &systemInfo.machine) { machine in
                String(decoding: machine.prefix { $0 != 0 }, as: UTF8.self)
            }
        #endif

        // Hardware identifier reference: https://github.com/devicekit/DeviceKit/blob/5.9.0/Source/Device.swift.gyb
        let models: [(identifiers: [String], name: String)] = [
            (["iPod9,1"], "iPod touch (7th generation)"),
            (["iPhone8,1"], "iPhone 6s"),
            (["iPhone8,2"], "iPhone 6s Plus"),
            (["iPhone9,1", "iPhone9,3"], "iPhone 7"),
            (["iPhone9,2", "iPhone9,4"], "iPhone 7 Plus"),
            (["iPhone8,4"], "iPhone SE (1st generation)"),
            (["iPhone10,1", "iPhone10,4"], "iPhone 8"),
            (["iPhone10,2", "iPhone10,5"], "iPhone 8 Plus"),
            (["iPhone10,3", "iPhone10,6"], "iPhone X"),
            (["iPhone11,2"], "iPhone XS"),
            (["iPhone11,4", "iPhone11,6"], "iPhone XS Max"),
            (["iPhone11,8"], "iPhone XR"),
            (["iPhone12,1"], "iPhone 11"),
            (["iPhone12,3"], "iPhone 11 Pro"),
            (["iPhone12,5"], "iPhone 11 Pro Max"),
            (["iPhone12,8"], "iPhone SE (2nd generation)"),
            (["iPhone13,2"], "iPhone 12"),
            (["iPhone13,1"], "iPhone 12 mini"),
            (["iPhone13,3"], "iPhone 12 Pro"),
            (["iPhone13,4"], "iPhone 12 Pro Max"),
            (["iPhone14,5"], "iPhone 13"),
            (["iPhone14,4"], "iPhone 13 mini"),
            (["iPhone14,2"], "iPhone 13 Pro"),
            (["iPhone14,3"], "iPhone 13 Pro Max"),
            (["iPhone14,6"], "iPhone SE (3rd generation)"),
            (["iPhone14,7"], "iPhone 14"),
            (["iPhone14,8"], "iPhone 14 Plus"),
            (["iPhone15,2"], "iPhone 14 Pro"),
            (["iPhone15,3"], "iPhone 14 Pro Max"),
            (["iPhone15,4"], "iPhone 15"),
            (["iPhone15,5"], "iPhone 15 Plus"),
            (["iPhone16,1"], "iPhone 15 Pro"),
            (["iPhone16,2"], "iPhone 15 Pro Max"),
            (["iPhone17,3"], "iPhone 16"),
            (["iPhone17,4"], "iPhone 16 Plus"),
            (["iPhone17,1"], "iPhone 16 Pro"),
            (["iPhone17,2"], "iPhone 16 Pro Max"),
            (["iPhone17,5"], "iPhone 16e"),
            (["iPhone18,3"], "iPhone 17"),
            (["iPhone18,1"], "iPhone 17 Pro"),
            (["iPhone18,2"], "iPhone 17 Pro Max"),
            (["iPhone18,4"], "iPhone Air"),
            (["iPhone18,5"], "iPhone 17e"),
            (["iPhone19,2"], "iPhone 18 Pro"),
            (["iPhone19,3", "iPhone19,7"], "iPhone 18 Pro Max"),
            (["iPad5,3", "iPad5,4"], "iPad Air 2"),
            (["iPad6,11", "iPad6,12"], "iPad (5th generation)"),
            (["iPad7,5", "iPad7,6"], "iPad (6th generation)"),
            (["iPad11,3", "iPad11,4"], "iPad Air (3rd generation)"),
            (["iPad7,11", "iPad7,12"], "iPad (7th generation)"),
            (["iPad11,6", "iPad11,7"], "iPad (8th generation)"),
            (["iPad12,1", "iPad12,2"], "iPad (9th generation)"),
            (["iPad13,18", "iPad13,19"], "iPad (10th generation)"),
            (["iPad15,7", "iPad15,8"], "iPad (A16)"),
            (["iPad13,1", "iPad13,2"], "iPad Air (4th generation)"),
            (["iPad13,16", "iPad13,17"], "iPad Air (5th generation)"),
            (["iPad14,8", "iPad14,9"], "iPad Air (11-inch) (M2)"),
            (["iPad14,10", "iPad14,11"], "iPad Air (13-inch) (M2)"),
            (["iPad15,3", "iPad15,4"], "iPad Air (11-inch) (M3)"),
            (["iPad15,5", "iPad15,6"], "iPad Air (13-inch) (M3)"),
            (["iPad16,8", "iPad16,9"], "iPad Air (11-inch) (M4)"),
            (["iPad16,10", "iPad16,11"], "iPad Air (13-inch) (M4)"),
            (["iPad5,1", "iPad5,2"], "iPad mini 4"),
            (["iPad11,1", "iPad11,2"], "iPad mini (5th generation)"),
            (["iPad14,1", "iPad14,2"], "iPad mini (6th generation)"),
            (["iPad16,1", "iPad16,2"], "iPad mini (A17 Pro)"),
            (["iPad6,3", "iPad6,4"], "iPad Pro (9.7-inch)"),
            (["iPad6,7", "iPad6,8"], "iPad Pro (12.9-inch)"),
            (["iPad7,1", "iPad7,2"], "iPad Pro (12.9-inch) (2nd generation)"),
            (["iPad7,3", "iPad7,4"], "iPad Pro (10.5-inch)"),
            (["iPad8,1", "iPad8,2", "iPad8,3", "iPad8,4"], "iPad Pro (11-inch)"),
            (["iPad8,5", "iPad8,6", "iPad8,7", "iPad8,8"], "iPad Pro (12.9-inch) (3rd generation)"),
            (["iPad8,9", "iPad8,10"], "iPad Pro (11-inch) (2nd generation)"),
            (["iPad8,11", "iPad8,12"], "iPad Pro (12.9-inch) (4th generation)"),
            (["iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7"], "iPad Pro (11-inch) (3rd generation)"),
            (["iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11"], "iPad Pro (12.9-inch) (5th generation)"),
            (["iPad14,3", "iPad14,4"], "iPad Pro (11-inch) (4th generation)"),
            (["iPad14,5", "iPad14,6"], "iPad Pro (12.9-inch) (6th generation)"),
            (["iPad16,3", "iPad16,4"], "iPad Pro (11-inch) (M4)"),
            (["iPad16,5", "iPad16,6"], "iPad Pro (13-inch) (M4)"),
            (["iPad17,1", "iPad17,2"], "iPad Pro (11-inch) (M5)"),
            (["iPad17,3", "iPad17,4"], "iPad Pro (13-inch) (M5)"),
        ]
        return models.first { $0.identifiers.contains(identifier) }?.name
    }()
}
