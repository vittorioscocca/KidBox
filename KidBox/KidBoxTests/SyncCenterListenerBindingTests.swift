//
//  SyncCenterListenerBindingTests.swift
//  KidBoxTests
//
//  Le proprietà di sicurezza del guard `isListenerBound`, da cui dipendono i
//  nove listener che lo usano (todo, members, expenses, homeItems,
//  housePayments, pets, petEvents, vehicles, vehicleEvents).
//
//  Il guard evita di ricreare un listener già agganciato, perché le view di
//  quelle sezioni chiamano `start…Realtime` a ogni `onAppear` mentre
//  `RootHostView` l'ha già chiamato all'avvio. Ma saltare un re-attach che
//  invece serviva è un guasto silenzioso: i dati restano fermi e nessuno se ne
//  accorge. Questi test fissano i casi in cui il guard NON deve scattare.
//
//  NOTA misurata il 10/09/2026 su device (iPhone 16, iOS 26.6.1): un re-attach
//  a cache calda NON rilegge la collection dal server. Il pull-to-refresh della
//  Home, che ristacca e riaggancia tutti e venti i listener, è costato 19
//  letture Firestore, e i listener strumentati hanno riportato `changes=0` con
//  `fromCache=false`. Il commento in SyncCenter+ForceRefresh.swift che dice il
//  contrario descrive il caso a cache fredda, non quello normale.
//

import XCTest
@testable import KidBox

@MainActor
final class SyncCenterListenerBindingTests: XCTestCase {

    private let key = "notes"
    private let familyA = "family-A"
    private let familyB = "family-B"

    override func setUp() async throws {
        try await super.setUp()
        SyncCenter.shared.invalidateListenerBindings()
    }

    override func tearDown() async throws {
        SyncCenter.shared.invalidateListenerBindings()
        try await super.tearDown()
    }

    /// Un listener mai agganciato non è "bound": il primo start deve passare.
    func testNonBoundQuandoNessunoHaAncoraAgganciato() {
        XCTAssertFalse(
            SyncCenter.shared.isListenerBound(key, to: familyA, attached: true),
            "Senza bind precedente il guard non deve mai scattare"
        )
    }

    /// Il caso per cui il guard esiste: root ha già agganciato, la sezione
    /// richiama lo start, e il re-attach va saltato.
    func testBoundSaltaIlReAttachSuStessaFamiglia() {
        SyncCenter.shared.bindListener(key, to: familyA)
        XCTAssertTrue(
            SyncCenter.shared.isListenerBound(key, to: familyA, attached: true),
            "Stesso scope e listener vivo: il re-attach è puro spreco e va saltato"
        )
    }

    /// SICUREZZA 1 — il pull-to-refresh.
    ///
    /// Il blocco di reattach fa `stop…Realtime()` prima dello start, quindi
    /// arriva qui con `attached: false`. Se il guard scattasse lo stesso, il
    /// gesto non rileggerebbe più nulla e il pull morirebbe in silenzio.
    func testListenerSpentoRiagganciaAncheSeLoScopeCoincide() {
        SyncCenter.shared.bindListener(key, to: familyA)
        XCTAssertFalse(
            SyncCenter.shared.isListenerBound(key, to: familyA, attached: false),
            "Listener spento: va ricreato anche a parità di scope, o il pull-to-refresh diventa muto"
        )
    }

    /// SICUREZZA 2 — il cambio famiglia.
    ///
    /// Uno switch non deve mai essere saltato, o la nuova famiglia resterebbe
    /// agganciata ai dati della precedente.
    func testCambioFamigliaNonVieneMaiSaltato() {
        SyncCenter.shared.bindListener(key, to: familyA)
        XCTAssertFalse(
            SyncCenter.shared.isListenerBound(key, to: familyB, attached: true),
            "Scope diverso: il re-attach deve avvenire sempre"
        )
    }

    /// SICUREZZA 3 — `listenerKeys` del pull-to-refresh e il rebind forzato.
    ///
    /// `unbindListeners` è la cintura che il pull passa a `forceRefresh`;
    /// `invalidateListenerBindings` è quella dei deep link e del recupero dopo
    /// PERMISSION_DENIED. Entrambe devono far cadere il guard.
    func testUnbindEInvalidateFannoCadereIlGuard() {
        SyncCenter.shared.bindListener(key, to: familyA)
        SyncCenter.shared.unbindListeners([key])
        XCTAssertFalse(
            SyncCenter.shared.isListenerBound(key, to: familyA, attached: true),
            "Dopo unbindListeners il prossimo start deve ricreare davvero il listener"
        )

        SyncCenter.shared.bindListener(key, to: familyA)
        SyncCenter.shared.invalidateListenerBindings()
        XCTAssertFalse(
            SyncCenter.shared.isListenerBound(key, to: familyA, attached: true),
            "Dopo invalidateListenerBindings il rebind forzato deve passare"
        )
    }

    /// `unbindListeners` deve toccare solo le chiavi indicate: il pull di una
    /// sezione non deve far rileggere tutte le altre.
    func testUnbindNonTraboccaSulleAltreChiavi() {
        SyncCenter.shared.bindListener("notes", to: familyA)
        SyncCenter.shared.bindListener("passwords", to: familyA)
        SyncCenter.shared.unbindListeners(["notes"])
        XCTAssertTrue(
            SyncCenter.shared.isListenerBound("passwords", to: familyA, attached: true),
            "Il pull di Note non deve invalidare il binding di Password"
        )
    }
}
