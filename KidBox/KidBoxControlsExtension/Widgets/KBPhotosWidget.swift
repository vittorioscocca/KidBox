//
//  KBPhotosWidget.swift
//  KidBoxControlsExtension
//
//  Widget quadrato «Foto»: una foto della famiglia (o di un album) a tutto
//  riquadro, diversa ogni ora. Le miniature le prepara l'app (le foto sono
//  cifrate): vedi `KBWidgetPhotos` e `KBWidgetPhotoFiles`.
//

import SwiftUI
import WidgetKit
import UIKit

struct KBPhotosWidgetView: View {
    let date: Date
    let snapshot: KBWidgetSnapshot?
    let albumId: String?

    private var pool: [KBWidgetSnapshot.Photo] {
        let all = snapshot?.photos ?? []
        // Album cancellato dopo la scelta: ripiega su tutte.
        guard let albumId, snapshot?.albums?.contains(where: { $0.id == albumId }) == true else { return all }
        return all.filter { $0.albumIds.contains(albumId) }
    }

    private var albumTitle: String? {
        guard let albumId else { return nil }
        return snapshot?.albums?.first { $0.id == albumId }?.title
    }

    /// Una foto per ora, a giro: l'indice viene dalle ore passate dal 1970.
    private var current: (photo: KBWidgetSnapshot.Photo, image: UIImage)? {
        let photos = pool
        guard !photos.isEmpty else { return nil }
        let start = Int(date.timeIntervalSince1970 / 3600) % photos.count
        // Se una miniatura manca (appena tolta dall'app), prova le successive.
        for offset in 0..<min(photos.count, 5) {
            let p = photos[(start + offset) % photos.count]
            if let url = KBWidgetPhotoFiles.url(for: p.id),
               let img = UIImage(contentsOfFile: url.path) {
                return (p, img)
            }
        }
        return nil
    }

    var body: some View {
        if snapshot == nil {
            KBWidgetSignedOut()
                .containerBackground(.background, for: .widget)
        } else if let current {
            VStack {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        if let albumTitle {
                            Text(albumTitle)
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .lineLimit(1)
                        }
                        Text(current.photo.takenAt, format: .dateTime.day().month(.abbreviated).year())
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetURL(URL(string: "kidbox://widget/photos"))
            .containerBackground(for: .widget) {
                ZStack(alignment: .bottom) {
                    Image(uiImage: current.image)
                        .resizable()
                        .scaledToFill()
                    LinearGradient(colors: [.clear, .black.opacity(0.45)],
                                   startPoint: .center, endPoint: .bottom)
                }
            }
        } else {
            KBWidgetMessage(systemImage: "photo.on.rectangle",
                            text: (snapshot?.photos ?? []).isEmpty && albumId == nil
                                ? "Apri KidBox per preparare le foto"
                                : "Nessuna foto in questo album",
                            color: .kbPhotos)
                .widgetURL(URL(string: "kidbox://widget/photos"))
                .containerBackground(.background, for: .widget)
        }
    }
}
