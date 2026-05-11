//
//  OpenKidBoxFamilyPhotosCameraIntent.swift
//  KidBox + KidBoxControlsExtension
//
//  Il file deve essere nel target **KidBox** e **KidBoxControlsExtension** (vedi eccezione nel progetto Xcode).
//  Senza il target app, `openAppWhenRun` dal Control Center spesso non apre il container.
//

import AppIntents
import Foundation

/// Tap sul controllo → porta in primo piano KidBox e apre **Foto e video** con fotocamera.
///
/// **Perché non `OpenURLIntent(kidbox://…)`:** `OpenURLIntent` accetta solo universal link, non URL scheme personalizzati.
/// Handoff tramite App Group + `openAppWhenRun`.
struct OpenKidBoxFamilyPhotosCameraIntent: AppIntent {
    static var title: LocalizedStringResource = "Foto KidBox"
    static var description = IntentDescription("Apre Foto e video con la fotocamera.")
    static var isDiscoverable: Bool = true

    /// Porta in foreground il container app prima di `perform()`.
    static var openAppWhenRun: Bool = true

    private static let appGroupSuite = "group.it.vittorioscocca.kidbox"
    private static let pendingRouteKey = "kidbox.controlWidget.pendingRoute"
    private static let pendingRouteFamilyPhotosCamera = "openFamilyPhotosCamera"

    init() {}

    func perform() async throws -> some IntentResult {
        let defs = UserDefaults(suiteName: Self.appGroupSuite)
        defs?.set(Self.pendingRouteFamilyPhotosCamera, forKey: Self.pendingRouteKey)
        defs?.synchronize()
        return .result()
    }
}
