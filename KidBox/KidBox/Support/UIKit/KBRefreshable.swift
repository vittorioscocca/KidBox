//
//  KBRefreshable.swift
//  KidBox
//

import SwiftUI
import UIKit

extension View {

    /// Pull-to-refresh standard di KidBox: un feedback aptico leggero all'inizio
    /// del gesto, poi il refresh vero e proprio.
    ///
    /// Va applicato allo scrollable (`List` / `ScrollView`) della sezione oppure
    /// a un suo antenato: `List` legge l'azione dall'environment, quindi anche le
    /// view che alternano lista ed empty state possono metterlo una volta sola
    /// sul contenitore esterno.
    func kbRefreshable(_ action: @escaping @MainActor () async -> Void) -> some View {
        refreshable {
            await MainActor.run {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            await action()
        }
    }
}
