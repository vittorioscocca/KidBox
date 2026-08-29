//
//  SharedUserLocation.swift
//  KidBox
//
//  Created by vscocca on 24/02/26.
//

import Foundation
import CoreLocation

struct SharedUserLocation: Identifiable, Equatable {
    let id: String // uid
    let name: String
    let latitude: Double
    let longitude: Double
    let mode: ShareMode
    let expiresAt: Date?
    let avatarURL: String?      // URL Firebase Storage, nil se non ancora caricato
    /// Carica del dispositivo che sta condividendo, 0…100. `nil` finché quel
    /// dispositivo non ne ha ancora spedita una (versioni precedenti incluse).
    let batteryLevel: Int?
    let isCharging: Bool
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum ShareMode: String {
    case realtime
    case temporary
}
