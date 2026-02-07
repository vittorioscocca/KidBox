//
//  AppDelegate.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import UIKit
import FirebaseCore

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        return true
    }
}
