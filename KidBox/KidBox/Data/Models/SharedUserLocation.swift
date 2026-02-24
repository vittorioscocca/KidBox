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
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum ShareMode: String {
    case realtime
    case temporary
}
