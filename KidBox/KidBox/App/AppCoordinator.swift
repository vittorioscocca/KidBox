//
//  AppCoordinator.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import SwiftUI
import Combine
import OSLog

/// Central coordinator responsible for navigation and flow control.
///
/// `AppCoordinator` owns the navigation path and decides which screen should be
/// presented based on the current application state (authentication, family setup, etc.).
///
/// - Important: Views and ViewModels must not perform navigation directly.
///   All routing decisions go through the coordinator.
@MainActor
final class AppCoordinator: ObservableObject {
    
    /// Navigation path bound to the root `NavigationStack`.
    @Published var path: [Route] = []
    
    /// Returns the root view of the application.
    /// This is typically called once at app launch.
    func makeRootView() -> some View {
        HomeView()
    }
    
    /// Resolves a route into its destination view.
    @ViewBuilder
    func makeDestination(for route: Route) -> some View {
        switch route {
        case .home:
            HomeView()
        case .today:
            Text("Today")
        case .calendar:
            Text("Calendar")
        case .todo:
            Text("Todo")
        case .settings:
            Text("Settings")
        case .profile:
            Text("Profile")
        case .setupFamily:
            Text("Setup Family")
        }
    }
    
    /// Pushes a new route onto the navigation stack.
    func navigate(to route: Route) {
        KBLog.navigation.debug("Navigate to route: \(String(describing: route))")
        path.append(route)
    }
    
    /// Clears the navigation stack and returns to the root.
    func resetToRoot() {
        KBLog.navigation.debug("Reset navigation to root")
        path.removeAll()
    }
}

