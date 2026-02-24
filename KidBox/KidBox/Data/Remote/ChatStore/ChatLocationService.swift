//
//  ChatLocationService.swift
//  KidBox
//
//  Created by vscocca on 24/02/26.
//

import CoreLocation

final class ChatLocationService: NSObject, CLLocationManagerDelegate {
    
    static let shared = ChatLocationService()
    
    private let manager = CLLocationManager()
    private var completion: ((CLLocation?) -> Void)?
    
    private override init() {
        super.init()
        manager.delegate = self
    }
    
    func requestLocation(completion: @escaping (CLLocation?) -> Void) {
        self.completion = completion
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        completion?(locations.first)
        completion = nil
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completion?(nil)
        completion = nil
    }
}
