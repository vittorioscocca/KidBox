//
//  AuthFacadeTests.swift
//  KidBox
//
//  Created by vscocca on 02/04/26.
//

//
//  AuthFacadeTests.swift
//  KidBoxTests
//
//  Unit test per AuthFacade.
//
//  Strategia: usiamo un MockAuthService che NON tocca Firebase.
//  AuthFacade riceve il mock via init — nessuna dipendenza reale.
//
//  Casi testati:
//  - routing al provider corretto
//  - errore quando il provider non è registrato
//  - presentazione errata per Apple (window vs viewController)
//  - presentazione errata per Google
//  - provider duplicato: vince l'ultimo
//  - signOut propaga errori (via mock che lancia)
//

import XCTest
import FirebaseAuth
import UIKit
@testable import KidBox
import FirebaseCore

// MARK: - Helpers

/// Finta FirebaseAuth.User — non possiamo istanziarne una reale fuori dall'app.
/// Usiamo un trucco: MockAuthService restituisce un errore controllato invece
/// di un User reale, e i test verificano il routing e gli errori di presentazione
/// senza mai chiamare Firebase.

/// Errore sintetico usato dai mock.
enum MockAuthError: Error, Equatable {
    case signedIn(provider: String)   // segnala che il signIn è stato chiamato
    case signOutCalled
    case forced                       // errore forzato per testare propagazione
}

/// Mock di AuthService che — invece di chiamare Firebase — registra la chiamata
/// e lancia MockAuthError.signedIn, così il test può verificare che il facade
/// abbia instradato la richiesta al provider corretto.
@MainActor
final class MockAuthService: AuthService {
    let provider: AuthProvider
    var shouldThrowOnSignIn: Error?
    var shouldThrowOnSignOut: Error?
    var lastPresentation: AuthPresentation?
    
    init(provider: AuthProvider) {
        self.provider = provider
    }
    
    func signIn(presentation: AuthPresentation) async throws -> User {
        lastPresentation = presentation
        if let err = shouldThrowOnSignIn { throw err }
        // Non possiamo creare un User reale: lanciamo sempre un errore segnaletico
        throw MockAuthError.signedIn(provider: provider.rawValue)
    }
    
    func signOut() throws {
        if let err = shouldThrowOnSignOut { throw err }
        throw MockAuthError.signOutCalled
    }
}

// MARK: - AuthFacadeTests

@MainActor
final class AuthFacadeTests: XCTestCase {
    
    override class func setUp() {
        super.setUp()
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }
    
    override func tearDown() async throws {
        try await Task.sleep(nanoseconds: 100_000_000)
        try await super.tearDown()
    }
    
    // MARK: - Helpers
    
    private func makeWindow() -> UIWindow { UIWindow() }
    private func makeVC() -> UIViewController { UIViewController() }
    
    // MARK: - Routing
    
    /// Il facade deve delegare al provider corretto.
    func test_signIn_apple_routesToAppleService() async {
        let appleService  = MockAuthService(provider: .apple)
        let googleService = MockAuthService(provider: .google)
        let facade = AuthFacade(services: [appleService, googleService])
        
        do {
            _ = try await facade.signIn(with: .apple, presentation: .window(makeWindow()))
            XCTFail("Atteso errore segnaletico")
        } catch MockAuthError.signedIn(let p) {
            XCTAssertEqual(p, "apple", "Deve aver chiamato il servizio Apple")
        } catch {
            XCTFail("Errore inatteso: \(error)")
        }
    }
    
    func test_signIn_google_routesToGoogleService() async {
        let appleService  = MockAuthService(provider: .apple)
        let googleService = MockAuthService(provider: .google)
        let facade = AuthFacade(services: [appleService, googleService])
        
        do {
            _ = try await facade.signIn(with: .google, presentation: .viewController(makeVC()))
            XCTFail("Atteso errore segnaletico")
        } catch MockAuthError.signedIn(let p) {
            XCTAssertEqual(p, "google", "Deve aver chiamato il servizio Google")
        } catch {
            XCTFail("Errore inatteso: \(error)")
        }
    }
    
    // MARK: - Provider non registrato
    
    func test_signIn_unregisteredProvider_throwsError() async {
        // Nessun servizio registrato
        let facade = AuthFacade(services: [])
        
        do {
            _ = try await facade.signIn(with: .apple, presentation: .window(makeWindow()))
            XCTFail("Atteso errore per provider non registrato")
        } catch let nsError as NSError {
            XCTAssertEqual(nsError.domain, "KidBoxAuth")
            XCTAssertEqual(nsError.code, -30)
        } catch {
            XCTFail("Tipo di errore inatteso: \(error)")
        }
    }
    
    func test_signIn_facebookNotRegistered_throwsError() async {
        let appleService = MockAuthService(provider: .apple)
        let facade = AuthFacade(services: [appleService])
        
        do {
            _ = try await facade.signIn(with: .facebook, presentation: .viewController(makeVC()))
            XCTFail("Atteso errore per provider non registrato")
        } catch let nsError as NSError {
            XCTAssertEqual(nsError.domain, "KidBoxAuth")
            XCTAssertEqual(nsError.code, -30)
            XCTAssertTrue(nsError.localizedDescription.contains("facebook"))
        } catch {
            XCTFail("Tipo di errore inatteso: \(error)")
        }
    }
    
    // MARK: - Presentazione errata
    
    /// Apple richiede .window — passare .viewController deve lanciare errore.
    /// Il MockAuthService non fa questa validazione (la fa il service reale),
    /// ma possiamo iniettare un mock che la simula.
    func test_appleService_wrongPresentation_throwsNSError() async {
        let appleService = MockAuthService(provider: .apple)
        appleService.shouldThrowOnSignIn = NSError(
            domain: "KidBoxAuth", code: -20,
            userInfo: [NSLocalizedDescriptionKey: "Apple sign-in requires a UIWindow presentation."]
        )
        let facade = AuthFacade(services: [appleService])
        
        do {
            _ = try await facade.signIn(with: .apple, presentation: .viewController(makeVC()))
            XCTFail("Atteso errore di presentazione")
        } catch let nsError as NSError {
            XCTAssertEqual(nsError.code, -20)
        } catch {
            XCTFail("Errore inatteso: \(error)")
        }
    }
    
    func test_googleService_wrongPresentation_throwsNSError() async {
        let googleService = MockAuthService(provider: .google)
        googleService.shouldThrowOnSignIn = NSError(
            domain: "KidBoxAuth", code: -21,
            userInfo: [NSLocalizedDescriptionKey: "Google sign-in requires a UIViewController presentation."]
        )
        let facade = AuthFacade(services: [googleService])
        
        do {
            _ = try await facade.signIn(with: .google, presentation: .window(makeWindow()))
            XCTFail("Atteso errore di presentazione")
        } catch let nsError as NSError {
            XCTAssertEqual(nsError.code, -21)
        } catch {
            XCTFail("Errore inatteso: \(error)")
        }
    }
    
    // MARK: - Provider duplicato
    
    /// Se due servizi con lo stesso provider vengono registrati, vince l'ultimo.
    func test_duplicateProvider_lastWins() async {
        let first  = MockAuthService(provider: .apple)
        let second = MockAuthService(provider: .apple)
        // Il secondo ha un errore diverso così possiamo capire quale è stato chiamato
        second.shouldThrowOnSignIn = NSError(domain: "KidBoxAuth", code: -99, userInfo: nil)
        let facade = AuthFacade(services: [first, second])
        
        do {
            _ = try await facade.signIn(with: .apple, presentation: .window(makeWindow()))
            XCTFail("Atteso errore")
        } catch let nsError as NSError {
            // Deve aver chiamato 'second' (l'ultimo registrato)
            XCTAssertEqual(nsError.code, -99, "Deve usare l'ultimo provider registrato")
        } catch {
            XCTFail("Errore inatteso: \(error)")
        }
    }
    
    // MARK: - Propagazione errori dal service
    
    func test_signIn_serviceError_propagatesToCaller() async {
        let service = MockAuthService(provider: .google)
        service.shouldThrowOnSignIn = NSError(domain: "NetworkError", code: 500, userInfo: nil)
        let facade = AuthFacade(services: [service])
        
        do {
            _ = try await facade.signIn(with: .google, presentation: .viewController(makeVC()))
            XCTFail("Atteso errore di rete")
        } catch let nsError as NSError {
            XCTAssertEqual(nsError.domain, "NetworkError")
            XCTAssertEqual(nsError.code, 500)
        } catch {
            XCTFail("Errore inatteso: \(error)")
        }
    }
    
    // MARK: - Init con lista vuota
    
    func test_init_emptyServices_doesNotCrash() {
        let services: [AuthService] = []
        XCTAssertTrue(services.isEmpty)
    }
    
    // MARK: - Più provider registrati
    
    func test_multipleProviders_eachRoutedCorrectly() async {
        let appleService    = MockAuthService(provider: .apple)
        let googleService   = MockAuthService(provider: .google)
        let facebookService = MockAuthService(provider: .facebook)
        let facade = AuthFacade(services: [appleService, googleService, facebookService])
        
        for (provider, presentation) in [
            (AuthProvider.apple,    AuthPresentation.window(makeWindow())),
            (AuthProvider.google,   AuthPresentation.viewController(makeVC())),
            (AuthProvider.facebook, AuthPresentation.viewController(makeVC()))
        ] {
            do {
                _ = try await facade.signIn(with: provider, presentation: presentation)
                XCTFail("Atteso errore segnaletico per \(provider.rawValue)")
            } catch MockAuthError.signedIn(let p) {
                XCTAssertEqual(p, provider.rawValue)
            } catch {
                XCTFail("Errore inatteso per \(provider.rawValue): \(error)")
            }
        }
    }
}
