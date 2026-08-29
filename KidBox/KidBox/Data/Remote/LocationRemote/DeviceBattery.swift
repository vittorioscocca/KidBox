//
//  DeviceBattery.swift
//  KidBox
//
//  La carica del dispositivo, letta al volo quando si spedisce una posizione.
//
//  Non è un servizio e non osserva niente: nessun timer, nessuna scrittura
//  propria. Viaggia dentro l'aggiornamento di coordinate che c'è già, così la
//  cadenza delle scritture di geolocalizzazione resta esattamente quella
//  decisa altrove.
//

import UIKit

struct DeviceBatterySnapshot {
    /// 0…100. `nil` quando il sistema non la espone (simulatore, o monitoraggio
    /// appena acceso: il primo valore arriva un istante dopo).
    let percentage: Int?
    let isCharging: Bool
}

enum DeviceBattery {
    @MainActor
    static func snapshot() -> DeviceBatterySnapshot {
        let device = UIDevice.current
        // Idempotente: acceso una volta resta acceso per tutta la vita del
        // processo, e senza non c'è alcun livello da leggere.
        if !device.isBatteryMonitoringEnabled {
            device.isBatteryMonitoringEnabled = true
        }
        let level = device.batteryLevel
        let charging = device.batteryState == .charging || device.batteryState == .full
        guard level >= 0 else {
            return DeviceBatterySnapshot(percentage: nil, isCharging: charging)
        }
        return DeviceBatterySnapshot(
            percentage: Int((level * 100).rounded()),
            isCharging: charging
        )
    }
}
