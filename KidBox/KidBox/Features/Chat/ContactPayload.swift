import Foundation
import Contacts

struct ContactPayload: Codable, Equatable {
    let givenName: String
    let familyName: String
    let phoneNumbers: [LabeledValue<String>]
    let emailAddresses: [LabeledValue<String>]
    let avatarData: Data?
    
    var fullName: String {
        let full = "\(givenName) \(familyName)".trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? "Contatto" : full
    }
    
    var primaryPhone: String? {
        phoneNumbers.first?.value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

struct LabeledValue<T: Codable & Equatable>: Codable, Equatable {
    let label: String
    let value: T
}

extension ContactPayload {
    static func fromCNContact(_ contact: CNContact) -> ContactPayload {
        let phones = contact.phoneNumbers.map { item -> LabeledValue<String> in
            let label = CNLabeledValue<NSString>.localizedString(forLabel: item.label ?? CNLabelPhoneNumberMobile)
            let value = item.value.stringValue
            return LabeledValue(label: label, value: value)
        }
        let emails = contact.emailAddresses.map { item -> LabeledValue<String> in
            let label = CNLabeledValue<NSString>.localizedString(forLabel: item.label ?? CNLabelHome)
            let value = item.value as String
            return LabeledValue(label: label, value: value)
        }
        return ContactPayload(
            givenName: contact.givenName,
            familyName: contact.familyName,
            phoneNumbers: phones,
            emailAddresses: emails,
            avatarData: contact.imageDataAvailable ? contact.thumbnailImageData : nil,
        )
    }
}

extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
