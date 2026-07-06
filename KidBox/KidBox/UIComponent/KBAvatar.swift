//
//  KBAvatar.swift
//  KidBox
//

import SwiftUI

/// Circular profile avatar with a hairline ring. Shows a photo, else initials, else a person glyph.
/// Mirrors the KidBox design system's `Avatar` component (design-system/components/core/Avatar.jsx)
/// and replaces the ad-hoc `ProfileAvatarView` previously nested in HomeView.
struct KBAvatar: View {
    var imageData: Data? = nil
    var name: String = ""
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let initials {
                Text(initials)
                    .font(.system(size: max(11, size * 0.4), weight: .bold))
                    .foregroundStyle(KBTheme.bubbleTint)
                    .frame(width: size, height: size)
                    .background(KBTheme.bubbleTint.opacity(0.16))
            } else {
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .scaledToFill()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.quaternary, lineWidth: 1))
    }

    private var initials: String? {
        let words = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .prefix(2)
        guard !words.isEmpty else { return nil }
        return words.compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

#Preview {
    HStack(spacing: 12) {
        KBAvatar(name: "Vittorio Scocca")
        KBAvatar(name: "Anna", size: 48)
        KBAvatar()
    }
    .padding()
}
