//
//  WalletDocumentNotifyToggle.swift
//  KidBox
//
//  Interruttore «Avvisami una settimana prima della scadenza» dei documenti
//  Wallet, con il cancello del permesso notifiche dentro: usato dai fogli
//  Aggiungi, Modifica e Collega, così il comportamento è uno solo. Speculare
//  a `NotifyRow` su Android.
//

import SwiftUI

struct WalletDocumentNotifyToggle: View {
    @Binding var isOn: Bool
    @State private var denied = false

    var body: some View {
        Toggle("Avvisami una settimana prima della scadenza", isOn: $isOn)
            .reminderPermissionGate(isOn: $isOn, denied: $denied)
        if denied {
            KBNotificationsDisabledCard()
        }
    }
}
