//
//  KBDeviceInfo.swift
//  KidBox
//
//  Identificativo hardware (sysctl hw.machine) + nome commerciale per crash report.
//

import Darwin
import Foundation
import UIKit

enum KBDeviceInfo {

    /// Codice Apple `hw.machine`, es. `iPhone17,1`
    static var machineIdentifier: String { hardwareMachine }

    /// Es. `iPhone 16 Pro (iPhone17,1)` · `iPad Air 11" (iPad14,8)` · `MacBook Pro (Mac15,3)`
    static var deviceDescription: String {
        let machine = hardwareMachine
        let name = marketingName(for: machine) ?? genericFamilyName(for: machine)
        var label = "\(name) (\(machine))"
        #if targetEnvironment(simulator)
        label += " [Simulator]"
        #endif
        if ProcessInfo.processInfo.isiOSAppOnMac {
            label += " [Mac Catalyst]"
        }
        return label
    }

    /// Es. `iOS 18.5` · `iPadOS 18.5` · `macOS 15.2` (Catalyst su Mac)
    static var osVersionDescription: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let semver = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        return "\(operatingSystemBrand) \(semver)"
    }

    /// `ios` | `ipados` | `mac` — per dedup in Cloud Functions
    static var platform: String {
        if ProcessInfo.processInfo.isiOSAppOnMac { return "mac" }
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: return "ipados"
        case .mac: return "mac"
        default: return "ios"
        }
    }

    // MARK: - Hardware

    private static var hardwareMachine: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: buffer)
    }

    private static var operatingSystemBrand: String {
        if ProcessInfo.processInfo.isiOSAppOnMac { return "macOS" }
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: return "iPadOS"
        case .mac: return "macOS"
        default: return "iOS"
        }
    }

    private static func genericFamilyName(for machine: String) -> String {
        if machine.hasPrefix("iPhone") { return "iPhone" }
        if machine.hasPrefix("iPad") { return "iPad" }
        if machine.hasPrefix("iPod") { return "iPod touch" }
        if machine.hasPrefix("Mac") || machine.hasPrefix("VirtualMac") { return "Mac" }
        if machine.hasPrefix("Watch") { return "Apple Watch" }
        if machine.hasPrefix("Reality") || machine.hasPrefix("AppleVision") { return "Apple Vision" }
        if machine == "arm64" || machine == "x86_64" || machine == "i386" {
            return UIDevice.current.model
        }
        return UIDevice.current.model
    }

    /// Mapping `hw.machine` → nome commerciale (aggiornabile con nuovi modelli).
    private static func marketingName(for machine: String) -> String? {
        marketingNames[machine]
    }

    private static let marketingNames: [String: String] = [
        // iPhone
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2ª gen.)",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,6": "iPhone SE (3ª gen.)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e",
        "iPhone18,1": "iPhone 17 Pro",
        "iPhone18,2": "iPhone 17 Pro Max",
        "iPhone18,3": "iPhone 17",
        "iPhone18,4": "iPhone 17 Air",
        // iPad
        "iPad13,1": "iPad Air (4ª gen.)",
        "iPad13,2": "iPad Air (4ª gen.)",
        "iPad13,16": "iPad Air (5ª gen.)",
        "iPad13,17": "iPad Air (5ª gen.)",
        "iPad13,18": "iPad (10ª gen.)",
        "iPad13,19": "iPad (10ª gen.)",
        "iPad14,1": "iPad mini (6ª gen.)",
        "iPad14,2": "iPad mini (6ª gen.)",
        "iPad14,3": "iPad Pro 11\" (4ª gen.)",
        "iPad14,4": "iPad Pro 11\" (4ª gen.)",
        "iPad14,5": "iPad Pro 12.9\" (6ª gen.)",
        "iPad14,6": "iPad Pro 12.9\" (6ª gen.)",
        "iPad14,8": "iPad Air 11\" (M2)",
        "iPad14,9": "iPad Air 11\" (M2)",
        "iPad14,10": "iPad Air 13\" (M2)",
        "iPad14,11": "iPad Air 13\" (M2)",
        "iPad16,3": "iPad Pro 11\" (M4)",
        "iPad16,4": "iPad Pro 11\" (M4)",
        "iPad16,5": "iPad Pro 13\" (M4)",
        "iPad16,6": "iPad Pro 13\" (M4)",
        // Mac (Catalyst / futuro target Mac)
        "Mac14,2": "MacBook Air (M2)",
        "Mac14,7": "MacBook Pro 13\" (M2)",
        "Mac14,9": "MacBook Pro 14\" (M3)",
        "Mac14,10": "MacBook Pro 16\" (M3)",
        "Mac15,3": "MacBook Pro 14\" (M3 Pro)",
        "Mac15,6": "MacBook Pro 16\" (M3 Pro)",
        "Mac15,7": "Mac Studio (M2 Max)",
        "Mac16,1": "MacBook Pro 14\" (M4)",
        "Mac16,5": "MacBook Pro 16\" (M4)",
        "VirtualMac2,1": "Mac (Virtualization)",
    ]
}
