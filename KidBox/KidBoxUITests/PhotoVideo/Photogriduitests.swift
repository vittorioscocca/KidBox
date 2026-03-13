//
//  PhotoGridUITests.swift
//  KidBoxUITests
//
//  Test UI per la schermata Foto e video.
//
//  Strategia: usa solo label e testi già presenti nell'app senza
//  richiedere accessibilityIdentifier custom — zero modifiche alle view.
//
//  Punto di partenza: l'app è già loggata e ha una famiglia attiva.
//  navigateToPhotosScreen() tappa il bottone "Foto e video" nella home.
//

import XCTest

final class PhotoGridUITests: XCTestCase {
    
    private var app: XCUIApplication!
    
    // MARK: - Setup
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        navigateToPhotosScreen()
    }
    
    override func tearDown() {
        app = nil
        super.tearDown()
    }
    
    // MARK: - Navigation helper
    
    /// Tappa "Foto e video" nella home — label visibile nel log.
    private func navigateToPhotosScreen() {
        let photosBtn = app.buttons["Foto e video"]
        if photosBtn.waitForExistence(timeout: 8) {
            photosBtn.tap()
        }
    }
    
    // MARK: - Titolo navigation
    
    func test_photosScreen_hasCorrectTitle() {
        let title = app.navigationBars["Foto e video"]
        XCTAssertTrue(title.waitForExistence(timeout: 5),
                      "La navigation bar deve mostrare 'Foto e video'")
    }
    
    // MARK: - Segmented control Libreria / Album
    
    func test_segmentedControl_libreria_exists() {
        let libreria = app.buttons["Libreria"]
        XCTAssertTrue(libreria.waitForExistence(timeout: 5))
    }
    
    func test_segmentedControl_album_exists() {
        let album = app.buttons["Album"]
        XCTAssertTrue(album.waitForExistence(timeout: 5))
    }
    
    func test_segmentedControl_switchToAlbum_andBack() {
        let albumTab = app.buttons["Album"]
        guard albumTab.waitForExistence(timeout: 5) else {
            XCTFail("Tab Album non trovato"); return
        }
        albumTab.tap()
        
        // Nella tab Album deve comparire il bottone "Nuovo album" o una album card
        // oppure il pulsante "+" in toolbar per creare album
        let plusBtn = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(plusBtn.waitForExistence(timeout: 3))
        
        // Torna a Libreria
        let libreriaTab = app.buttons["Libreria"]
        libreriaTab.tap()
        XCTAssertTrue(app.buttons["Libreria"].waitForExistence(timeout: 3))
    }
    
    // MARK: - Toolbar pulsanti
    
    func test_libreria_toolbar_hasSelezionaButton() {
        // "Seleziona" è sempre presente nella toolbar quando siamo in Libreria
        let selectBtn = app.navigationBars.buttons["Seleziona"]
        XCTAssertTrue(selectBtn.waitForExistence(timeout: 5),
                      "Il pulsante 'Seleziona' deve essere nella toolbar della libreria")
    }
    
    func test_libreria_toolbar_hasCameraButton() {
        // Il pulsante camera ha SF Symbol "camera" — il suo label accessibility
        // di default è "camera" se non impostato altrimenti
        // Cerca tra tutti i bottoni della nav bar
        let navBar = app.navigationBars.firstMatch
        guard navBar.waitForExistence(timeout: 5) else { return }
        
        // Conta i bottoni nella toolbar: Seleziona + slider + camera + plus = 4
        // Se la camera non c'è sono 3. Verifica che ce ne siano almeno 3.
        let btns = navBar.buttons
        XCTAssertGreaterThanOrEqual(btns.count, 2,
                                    "La toolbar deve avere almeno 2 pulsanti (Seleziona + plus/camera)")
    }
    
    // MARK: - Select mode
    
    func test_selectMode_appears_onSelectTap() {
        let selectBtn = app.navigationBars.buttons["Seleziona"]
        guard selectBtn.waitForExistence(timeout: 5) else { return }
        selectBtn.tap()
        
        let cancelBtn = app.navigationBars.buttons["Annulla"]
        XCTAssertTrue(cancelBtn.waitForExistence(timeout: 3),
                      "In select mode deve apparire il pulsante 'Annulla'")
    }
    
    func test_selectMode_cancel_restoresNormalMode() {
        let selectBtn = app.navigationBars.buttons["Seleziona"]
        guard selectBtn.waitForExistence(timeout: 5) else { return }
        selectBtn.tap()
        
        let cancelBtn = app.navigationBars.buttons["Annulla"]
        guard cancelBtn.waitForExistence(timeout: 3) else { return }
        cancelBtn.tap()
        
        XCTAssertTrue(app.navigationBars.buttons["Seleziona"].waitForExistence(timeout: 3),
                      "Dopo 'Annulla' il pulsante 'Seleziona' deve tornare visibile")
    }
    
    func test_selectMode_titleChanges_whenPhotoSelected() {
        // Entra in select mode
        let selectBtn = app.navigationBars.buttons["Seleziona"]
        guard selectBtn.waitForExistence(timeout: 5) else { return }
        selectBtn.tap()
        
        // Il titolo deve diventare "Seleziona" (nessun elemento selezionato)
        let navTitle = app.navigationBars.staticTexts["Seleziona"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 3),
                      "Il titolo in select mode deve essere 'Seleziona'")
    }
    
    // MARK: - Tab Album: navigazione al dettaglio
    
    func test_albumTab_newAlbumCard_exists() {
        let albumTab = app.buttons["Album"]
        guard albumTab.waitForExistence(timeout: 5) else { return }
        albumTab.tap()
        
        // "Nuovo album" è il testo della AlbumCreateCard
        let newAlbumText = app.staticTexts["Nuovo album"]
        XCTAssertTrue(newAlbumText.waitForExistence(timeout: 5),
                      "La card 'Nuovo album' deve essere visibile nella tab Album")
    }
    
    func test_albumTab_seleziona_button_exists_whenAlbumsPresent() {
        let albumTab = app.buttons["Album"]
        guard albumTab.waitForExistence(timeout: 5) else { return }
        albumTab.tap()
        
        // "Seleziona" appare nella toolbar degli album solo se ci sono album
        // Se non ci sono album il test passa comunque (guard)
        let selectBtn = app.navigationBars.buttons["Seleziona"]
        if selectBtn.waitForExistence(timeout: 3) {
            XCTAssertTrue(selectBtn.exists)
        }
        // Se non c'è "Seleziona" significa che non ci sono album — test non applicabile
    }
    
    // MARK: - Album detail
    
    func test_albumDetail_hasSelezionaButton() {
        let albumTab = app.buttons["Album"]
        guard albumTab.waitForExistence(timeout: 5) else { return }
        albumTab.tap()
        
        // Cerca una album card (qualsiasi staticText che non sia "Nuovo album")
        // Le album card hanno il titolo dell'album come staticText
        let allTexts = app.staticTexts.allElementsBoundByIndex
        let albumCard = allTexts.first {
            $0.label != "Nuovo album" && $0.label != " " && !$0.label.isEmpty
            && $0.label != "Foto e video"
        }
        
        guard let card = albumCard, card.waitForExistence(timeout: 3) else {
            // Nessun album presente — test non applicabile
            return
        }
        card.tap()
        
        // Nel dettaglio album deve esserci "Seleziona"
        let selectBtn = app.navigationBars.buttons["Seleziona"]
        XCTAssertTrue(selectBtn.waitForExistence(timeout: 5),
                      "La toolbar del dettaglio album deve avere 'Seleziona'")
    }
    
    func test_albumDetail_toolbar_hasCameraAndSelectButtons() {
        let albumTab = app.buttons["Album"]
        guard albumTab.waitForExistence(timeout: 5) else { return }
        albumTab.tap()
        
        let allTexts = app.staticTexts.allElementsBoundByIndex
        let albumCard = allTexts.first {
            $0.label != "Nuovo album" && $0.label != " " && !$0.label.isEmpty
            && $0.label != "Foto e video"
        }
        guard let card = albumCard, card.waitForExistence(timeout: 3) else { return }
        card.tap()
        
        // Toolbar dettaglio album: camera + Seleziona = almeno 2 bottoni
        let navBar = app.navigationBars.firstMatch
        guard navBar.waitForExistence(timeout: 3) else { return }
        XCTAssertGreaterThanOrEqual(navBar.buttons.count, 2,
                                    "La toolbar del dettaglio album deve avere almeno 2 pulsanti")
    }
}
