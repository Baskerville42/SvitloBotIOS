//
//  APIUtils.swift
//  SvitloBot
//
//  Created by Alexander Tartmin on 10.09.2024.
//

import Foundation

class APIUtils {
    
    static func createURLRequest(
        method: String,
        url: String,
        body: Data? = nil,
        params: [String: AnyHashable]? = nil
    ) -> URLRequest {
        let request = NSMutableURLRequest(url: createURL(path: url, params: params))
        request.httpMethod = method
        if let uBody = body {
            request.httpBody = uBody
        }
        request.allHTTPHeaderFields = commonHeaders()
        return request as URLRequest
    }
    
    private static func createURL(path: String, params: [String: AnyHashable]? = nil) -> URL {
        guard !path.contains("https") else {
            return URL(string: path)!
        }
        guard let baseURLString = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String else {
            fatalError("Base URL not found in Info.plist")
        }
        let url = URL(string: baseURLString)
        var comps = URLComponents()
        comps.scheme = url?.scheme
        comps.host = url?.host
        comps.path = "\(url?.path ?? "")\(path)"
        if let uParams = params {
            comps.queryItems = [URLQueryItem]()
            for (key, value) in uParams {
                let queryItem = URLQueryItem(name: key, value: "\(value)")
                comps.queryItems!.append(queryItem)
            }
        }
        return comps.url ?? URL(string: "")!
    }
    
    private static func commonHeaders() -> [String: String] {
        let headers = ["Accept": "*/*"]
        return headers
    }
}
