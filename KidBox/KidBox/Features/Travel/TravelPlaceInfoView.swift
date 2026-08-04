//
//  TravelPlaceInfoView.swift
//  KidBox
//
//  Scheda "Storia e territorio" della destinazione: foto grande + testo
//  storico/descrittivo da Wikipedia.
//

import SwiftUI

struct TravelPlaceInfoView: View {

    let placeName: String
    let familyId: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var info: TravelPlaceInfo?
    @State private var loadFailed = false

    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    private var cardBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.18, green: 0.18, blue: 0.18)
        : Color(.systemBackground)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let info {
                    // Galleria orizzontale: una sola foto raccontava poco di
                    // un posto, ed è quello che rendeva la scheda povera.
                    if !info.imageURLs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(info.imageURLs, id: \.self) { url in
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable().scaledToFill()
                                        default:
                                            Color.gray.opacity(0.15)
                                        }
                                    }
                                    .frame(width: 260, height: 190)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(info.title).font(.title2.bold())
                        if !info.subtitle.isEmpty {
                            Text(info.subtitle.capitalizedFirstLetter)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // ── Google: presente, indirizzo e voto ──────────────
                    if let g = info.googleDetails {
                        VStack(alignment: .leading, spacing: 8) {
                            if let rating = g.rating, rating > 0 {
                                HStack(spacing: 6) {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
                                    Text(String(format: "%.1f", rating))
                                        .font(.subheadline.weight(.semibold))
                                    if g.reviewCount > 0 {
                                        Text("· \(g.reviewCount) recensioni su Google")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            if !g.address.isEmpty {
                                Label(g.address, systemImage: "mappin.and.ellipse")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !g.about.isEmpty {
                                Text(g.about)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let maps = g.googleMapsURI {
                                Link(destination: maps) {
                                    Label("Apri in Google Maps", systemImage: "map")
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(cardBackground)
                        )
                    }

                    // ── Storia e territorio ─────────────────────────────
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(info.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(cardBackground)
                    )

                    // ── Cosa dicono i visitatori ────────────────────────
                    if let reviews = info.googleDetails?.reviews, !reviews.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Cosa dicono i visitatori")
                                .font(.headline)
                            ForEach(reviews.prefix(3)) { review in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(review.authorName)
                                            .font(.subheadline.weight(.semibold))
                                        if review.rating > 0 {
                                            HStack(spacing: 2) {
                                                Image(systemName: "star.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.yellow)
                                                Text("\(review.rating)")
                                                    .font(.caption)
                                            }
                                        }
                                        Spacer()
                                        Text(review.relativeTime)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(review.text)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(5)
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(cardBackground)
                        )
                    }

                    if let wikiURL = info.wikipediaURL {
                        Link(destination: wikiURL) {
                            Label("Continua su Wikipedia", systemImage: "arrow.up.right.square")
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    Text("Fonti: Wikipedia e Google")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                } else if loadFailed {
                    VStack(spacing: 8) {
                        Image(systemName: "book.closed")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Nessuna scheda disponibile per questa località.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .padding(16)
        }
        .background(backgroundColor)
        .navigationTitle("Storia e territorio")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: placeName) {
            do {
                info = try await TravelPlaceInfoService.shared.info(for: placeName, familyId: familyId)
            } catch {
                loadFailed = true
            }
        }
    }
}

private extension String {
    /// Wikipedia restituisce la description in minuscolo ("comune italiano").
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
