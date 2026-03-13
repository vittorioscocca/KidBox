//
//  AppearanceModeTests.swift
//  KidBoxTests
//
//  Testa AppearanceMode in isolamento puro.
//
//  NON istanzia AppCoordinator nei test — il suo init tocca Firebase Auth
//  e altre dipendenze non disponibili nel test runner, causando un crash malloc.
//  La persistenza in UserDefaults viene testata direttamente sulla chiave.
//

import XCTest
import SwiftUI
@testable import KidBox

final class AppearanceModeTests: XCTestCase {
    
    private let udKey = "kb_appearanceMode"
    
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: udKey)
    }
    
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: udKey)
        super.tearDown()
    }
    
    // MARK: - colorScheme
    
    func test_colorScheme_light_returnsLight() {
        XCTAssertEqual(AppearanceMode.light.colorScheme, .light)
    }
    
    func test_colorScheme_dark_returnsDark() {
        XCTAssertEqual(AppearanceMode.dark.colorScheme, .dark)
    }
    
    func test_colorScheme_system_returnsNil() {
        XCTAssertNil(AppearanceMode.system.colorScheme)
    }
    
    // MARK: - rawValue round-trip
    
    func test_rawValue_light() {
        XCTAssertEqual(AppearanceMode(rawValue: "light"), .light)
    }
    
    func test_rawValue_dark() {
        XCTAssertEqual(AppearanceMode(rawValue: "dark"), .dark)
    }
    
    func test_rawValue_system() {
        XCTAssertEqual(AppearanceMode(rawValue: "system"), .system)
    }
    
    func test_rawValue_unknown_returnsNil() {
        XCTAssertNil(AppearanceMode(rawValue: "banana"))
    }
    
    func test_rawValue_empty_returnsNil() {
        XCTAssertNil(AppearanceMode(rawValue: ""))
    }
    
    // MARK: - CaseIterable
    
    func test_allCases_containsThreeModes() {
        XCTAssertEqual(AppearanceMode.allCases.count, 3)
    }
    
    func test_allCases_containsLightDarkSystem() {
        XCTAssertTrue(AppearanceMode.allCases.contains(.light))
        XCTAssertTrue(AppearanceMode.allCases.contains(.dark))
        XCTAssertTrue(AppearanceMode.allCases.contains(.system))
    }
    
    // MARK: - Labels e icone
    
    func test_labels_areNonEmpty() {
        AppearanceMode.allCases.forEach {
            XCTAssertFalse($0.label.isEmpty, "\($0.rawValue).label non deve essere vuoto")
        }
    }
    
    func test_icons_areNonEmpty() {
        AppearanceMode.allCases.forEach {
            XCTAssertFalse($0.icon.isEmpty, "\($0.rawValue).icon non deve essere vuoto")
        }
    }
    
    func test_labels_areDistinct() {
        let labels = AppearanceMode.allCases.map(\.label)
        XCTAssertEqual(labels.count, Set(labels).count, "Ogni mode deve avere un label distinto")
    }
    
    func test_icons_areDistinct() {
        let icons = AppearanceMode.allCases.map(\.icon)
        XCTAssertEqual(icons.count, Set(icons).count, "Ogni mode deve avere un'icona distinta")
    }
    
    // MARK: - UserDefaults persistence (senza AppCoordinator)
    
    func test_userDefaults_write_andRead_light() {
        UserDefaults.standard.set(AppearanceMode.light.rawValue, forKey: udKey)
        let raw = UserDefaults.standard.string(forKey: udKey)
        XCTAssertEqual(AppearanceMode(rawValue: raw ?? ""), .light)
    }
    
    func test_userDefaults_write_andRead_dark() {
        UserDefaults.standard.set(AppearanceMode.dark.rawValue, forKey: udKey)
        let raw = UserDefaults.standard.string(forKey: udKey)
        XCTAssertEqual(AppearanceMode(rawValue: raw ?? ""), .dark)
    }
    
    func test_userDefaults_missing_key_defaultsToSystem() {
        // Chiave non presente → il coordinator usa .system come default
        let raw = UserDefaults.standard.string(forKey: udKey) ?? AppearanceMode.system.rawValue
        XCTAssertEqual(AppearanceMode(rawValue: raw), .system)
    }
    
    func test_userDefaults_overwrite_updatesValue() {
        UserDefaults.standard.set(AppearanceMode.dark.rawValue, forKey: udKey)
        UserDefaults.standard.set(AppearanceMode.light.rawValue, forKey: udKey)
        let raw = UserDefaults.standard.string(forKey: udKey)
        XCTAssertEqual(AppearanceMode(rawValue: raw ?? ""), .light)
    }
}
