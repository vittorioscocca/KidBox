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
        KBHomeWidget()
        KBTodoHomeWidget()
        KBGroceryHomeWidget()
        KBCareHomeWidget()
        KBFitnessHomeWidget()
        KBPhotosHomeWidget()
    }
}
