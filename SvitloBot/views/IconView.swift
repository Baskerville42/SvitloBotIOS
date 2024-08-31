//
//  IconView.swift
//  SvitloBot
//
//  Created by Alexander Tartmin on 31.08.2024.
//

import SwiftUI

struct IconView: View {
    let requestStatus: RequestStatus
    
    var body: some View {
        HStack {
            Group {
                switch requestStatus {
                case .idle:
                    ProgressView()
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .warning:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                case .error:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
            .font(.largeTitle)
        }
        .frame(height: 40)
    }
}
