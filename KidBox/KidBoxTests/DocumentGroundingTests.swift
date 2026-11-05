//
//  DocumentGroundingTests.swift
//  KidBoxTests
//
//  I riscontri che decidono se un documento letto sul telefono si tiene o va
//  a Claude: ogni errore visto nelle prove col modello ha un caso qui.
//

import XCTest
@testable import KidBox

@MainActor
final class DocumentGroundingTests: XCTestCase {

    private let bill = """
    ENERGIA ITALIA S.p.A.
    Fattura n. 4471829 del 12/10/2026
    Periodo 01/08/2026 - 30/09/2026
    TOTALE DA PAGARE 1.101,97 euro
    Scadenza pagamento 05/11/2026
    """

    func testAmountInAnyFormat() {
        XCTAssertTrue(DocumentGrounding.containsAmount(1101.97, in: bill))
        XCTAssertTrue(DocumentGrounding.containsAmount(1799.26, in: "NET 1 799,26"))
        XCTAssertTrue(DocumentGrounding.containsAmount(1799.26, in: "NET 1,799.26"))
        XCTAssertTrue(DocumentGrounding.containsAmount(412, in: "Premio 412,00 euro"))
        XCTAssertTrue(DocumentGrounding.containsAmount(412, in: "Premio 412 euro"))
    }

    func testInventedAmountIsRefused() {
        XCTAssertFalse(DocumentGrounding.containsAmount(10197, in: "TOTALE 101,97"))
        XCTAssertFalse(DocumentGrounding.containsAmount(13.9, in: "TOTALE 13,30"))
        XCTAssertFalse(DocumentGrounding.containsAmount(0, in: "TOTALE 0,00"))
    }

    func testDateMustBeInTheDocumentDayFirst() {
        XCTAssertTrue(DocumentGrounding.containsDate("2026-11-05", in: bill))
        XCTAssertTrue(DocumentGrounding.containsDate("2026-10-18", in: "18-10-2026 17:42"))
        XCTAssertTrue(DocumentGrounding.containsDate("2026-10-18", in: "18.10.26"))
        // Giorno e mese invertiti, e la data di oggi al posto di una assente.
        XCTAssertFalse(DocumentGrounding.containsDate("2026-12-10", in: "dated 12/10/2026 only"))
        XCTAssertFalse(DocumentGrounding.containsDate("2026-11-05", in: "Prelievo 02/10/2026"))
        XCTAssertFalse(DocumentGrounding.containsDate("", in: bill))
    }

    func testDueDateIsTheLastOfAtLeastTwo() {
        XCTAssertTrue(DocumentGrounding.isDueDate("2026-11-05", in: bill))
        XCTAssertFalse(DocumentGrounding.isDueDate("2026-10-12", in: bill))
        // Scontrino preso per bolletta: una data sola.
        XCTAssertFalse(DocumentGrounding.isDueDate("2026-10-18", in: "TOTAL 13,30\n18/10/2026 17:42"))
    }

    func testDueDateNextToItsWordEvenWithLaterDates() {
        let long = "Fattura del 12/10/2026\nOfferta valida fino al 31/12/2027\nScadenza 05/11/2026"
        XCTAssertTrue(DocumentGrounding.isDueDate("2026-11-05", in: long))
        XCTAssertFalse(DocumentGrounding.isDueDate("2026-10-12", in: long))
        // Parola e data su due righe, nelle quattro lingue e con gli accenti.
        XCTAssertTrue(DocumentGrounding.isDueDate("2026-11-05", in: "Échéance\n05/11/2026\n12/10/2026\n31/12/2027"))
        XCTAssertTrue(DocumentGrounding.isDueDate("2026-11-05", in: "Fecha límite de pago\n05/11/2026\n31/12/2027"))
        XCTAssertTrue(DocumentGrounding.isDueDate("2026-11-05", in: "Payment due 05/11/2026\n31/12/2027"))
        // Una data sola resta uno scontrino, anche con la parola.
        XCTAssertFalse(DocumentGrounding.isDueDate("2026-11-05", in: "Scadenza 05/11/2026"))
    }

    func testDirectDebitBillIsDueOnTheDebitDate() {
        let text = "Bolletta del 10/09/2026\nPeriodo dal 01/07/2026 al 31/08/2026\nAddebito sul conto\n29/09/2026\nOfferta: scade il 31/12/2026"
        XCTAssertTrue(DocumentGrounding.isDueDate("2026-09-29", in: text))
        XCTAssertFalse(DocumentGrounding.isDueDate("2026-08-31", in: text))
        XCTAssertFalse(DocumentGrounding.isDueDate("2026-09-30", in: text))
    }

    func testMonthNamesInTheFourLanguages() {
        let text = "Offerta valida fino al 31/12/2027\nDa pagare entro il 29 settembre 2026"
        XCTAssertTrue(DocumentGrounding.containsDate("2026-09-29", in: text))
        XCTAssertTrue(DocumentGrounding.isDueDate("2026-09-29", in: text))
        XCTAssertTrue(DocumentGrounding.containsDate("2026-09-29", in: "Pay by 29 September 2026"))
        XCTAssertTrue(DocumentGrounding.containsDate("2026-08-01", in: "Échéance le 1er août 2026"))
        XCTAssertTrue(DocumentGrounding.containsDate("2026-09-29", in: "Vence el 29 de septiembre de 2026"))
        XCTAssertFalse(DocumentGrounding.containsDate("2026-09-29", in: "29 bollette 2026"))
    }

    func testGroundingIgnoresCaseAndAccentsButNotNewFacts() {
        let text = "Diagnostic : otite moyenne aiguë gauche"
        XCTAssertTrue(DocumentGrounding.isGrounded("OTITE MOYENNE AIGUE", in: text))
        XCTAssertFalse(DocumentGrounding.isGrounded("pneumonie bilatérale sévère", in: text))
        XCTAssertFalse(DocumentGrounding.isGrounded("", in: text))
    }

    func testReferenceRangesCountOnlyRanges() {
        let lab = """
        Paziente: Sofia Rinaldi  Data prelievo: 02-10-2026
        Emoglobina 11,2 g/dL (12,0-16,0) *
        Globuli bianchi 7,8 10^3/uL (4,0-10,0)
        Piastrine 310 10^3/uL (150-400)
        """
        XCTAssertEqual(DocumentGrounding.referenceRangeCount(in: lab), 3)
        XCTAssertEqual(DocumentGrounding.referenceRangeCount(in: bill), 0)
    }

    func testPersonOnlyWhenExactlyOneMatches() {
        let persons: [OnDeviceDocumentAnalyzer.Person] = [
            .init(id: "1", name: "Luca Rinaldi"), .init(id: "2", name: "Sofía"), .init(id: "3", name: "Marta"),
        ]
        XCTAssertEqual(DocumentGrounding.personId(in: "Paziente: RINALDI LUCA", persons: persons), "1")
        XCTAssertEqual(DocumentGrounding.personId(in: "Paciente: Sofia Núñez", persons: persons), "2")
        XCTAssertNil(DocumentGrounding.personId(in: "Marta e Sofia", persons: persons))
        XCTAssertNil(DocumentGrounding.personId(in: "Paziente: Giulia", persons: persons))
    }

    func testLabLineDoesNotRepeatTheUnit() {
        let doubled = LabValue(name: "Emoglobina", value: "11,2 g/dL", unit: "g/dL", range: "12,0-16,0", outOfRange: true)
        XCTAssertEqual(doubled.line, "Emoglobina: 11,2 g/dL (12,0-16,0) *")
        let plain = LabValue(name: "TSH", value: "2,1", unit: "mUI/L", range: "", outOfRange: false)
        XCTAssertEqual(plain.line, "TSH: 2,1 mUI/L")
    }

    func testResultDecodedFromClaudeStaysCloud() throws {
        let json = #"{"category":"bill","suggestedTitle":"Luce","actions":[{"type":"house_payment","amount":10}]}"#
        let result = try JSONDecoder().decode(DocIntelResult.self, from: Data(json.utf8))
        XCTAssertFalse(result.onDevice)
        XCTAssertEqual(result.actions.first?.type, "house_payment")
    }
}
