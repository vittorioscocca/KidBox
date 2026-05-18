//
//  TravelDestinationImageView.swift
//  KidBox
//

import SwiftUI

struct TravelDestinationImageView: View {
    let destinationName: String
    var height: CGFloat = 200

    @State private var imageURL: URL?

    var body: some View {
        ZStack {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .task(id: destinationName) {
            imageURL = await TravelTripPlaceImageLoader.shared.imageURL(for: destinationName)
        }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [Color(red: 0.35, green: 0.45, blue: 0.62), Color(red: 0.22, green: 0.32, blue: 0.48)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
