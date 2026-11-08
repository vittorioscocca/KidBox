//
//  KidBoxControlsExtensionBundle.swift
//  KidBoxControlsExtension
//

import SwiftUI
import WidgetKit

@main
struct KidBoxControlsExtensionBundle: WidgetBundle {
    var body: some Widget {
        KidBoxFamilyPhotosCameraControl()
        KBCalendarWidget()
        KBTodoWidget()
        KBGroceryWidget()
        KBCareWidget()
        KBFitnessWidget()
    }
}
