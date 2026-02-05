//
//  LogoutCardView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//
import SwiftUI

struct LogoutCardView: View {
    let action: () -> Void
    
    init(action: @escaping () -> Void) {
        self.action = action
    }
    
    var body: some View {
        Button(role: .destructive, action: action) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.title3)
                Text("Logout")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.thinMaterial)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Logout")
        .accessibilityHint("Esce dall'account")
    }
}
