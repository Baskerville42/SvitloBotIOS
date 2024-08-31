//
//  String+Extra.swift
//  SvitloBot
//
//  Created by Alexander Tartmin on 12.09.2024.
//

import Foundation

extension String {
    var localized: String {
        return NSLocalizedString(self, comment: "")
    }
    
    func localizedWithParams(_ params: [String: String]) -> String {
        var localizedString = self.localized
        for (key, value) in params {
            localizedString = localizedString.replacingOccurrences(of: "%{\(key)}", with: value)
        }
        return localizedString
    }
}
