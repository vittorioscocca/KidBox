//
//  KidBoxFamilyPhotosCameraControl.swift
//  KidBoxControlsExtension
//

import AppIntents
import SwiftUI
import WidgetKit

/// Controllo aggiungibile da *Centro controllo* o *schermata di blocco* (iOS 18+).
struct KidBoxFamilyPhotosCameraControl: ControlWidget {
    static let kind: String = "it.vittorioscocca.KidBox.familyPhotosCamera"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenKidBoxFamilyPhotosCameraIntent()) {
                Label("Foto KidBox", systemImage: "camera.fill")
            }
        }
        .displayName("KidBox — Foto")
        .description("Apre Foto e video con la fotocamera.")
    }
}
