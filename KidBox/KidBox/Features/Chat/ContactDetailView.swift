import Contacts
import ContactsUI
import SwiftUI

struct ContactDetailView: View {
    let payload: ContactPayload
    
    @Environment(\.dismiss) private var dismiss
    @State private var showAddToContacts = false
    @State private var isAlreadySaved = false
    
    var body: some View {
        NavigationStack {
            List {
                header
                
                if !payload.phoneNumbers.isEmpty {
                    Section("Numeri di telefono") {
                        ForEach(payload.phoneNumbers, id: \.value) { number in
                            Button {
                                call(number.value)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(number.value)
                                            .foregroundStyle(.primary)
                                        Text(number.label)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "phone.fill")
                                }
                            }
                        }
                    }
                }
                
                if !payload.emailAddresses.isEmpty {
                    Section("Email") {
                        ForEach(payload.emailAddresses, id: \.value) { email in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(email.value)
                                    Text(email.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "envelope.fill")
                            }
                        }
                    }
                }
                
                if !isAlreadySaved {
                    Section {
                        Button("Aggiungi ai Contatti") {
                            showAddToContacts = true
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle("Contatto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddToContacts) {
                AddToContactsViewControllerRepresentable(payload: payload)
            }
            .task {
                isAlreadySaved = await ContactStoreLookup.isSaved(payload: payload)
            }
        }
    }
    
    private var header: some View {
        Section {
            VStack(spacing: 12) {
                avatar
                    .frame(width: 92, height: 92)
                Text(payload.fullName)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .listRowBackground(Color.clear)
        }
    }
    
    @ViewBuilder
    private var avatar: some View {
        if let data = payload.avatarData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15))
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
    
    private func call(_ number: String) {
        let cleaned = number.filter { "0123456789+".contains($0) }
        guard let url = URL(string: "tel://\(cleaned)") else { return }
        UIApplication.shared.open(url)
    }
}

private enum ContactStoreLookup {
    static func isSaved(payload: ContactPayload) async -> Bool {
        let store = CNContactStore()
        let phones = payload.phoneNumbers.map { $0.value }
        let emails = payload.emailAddresses.map { $0.value }
        if phones.isEmpty && emails.isEmpty { return false }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                for phone in phones {
                    let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: phone))
                    if let found = try? store.unifiedContacts(matching: predicate, keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]), !found.isEmpty {
                        cont.resume(returning: true)
                        return
                    }
                }
                for email in emails {
                    let predicate = CNContact.predicateForContacts(matchingEmailAddress: (email as NSString) as String)
                    if let found = try? store.unifiedContacts(matching: predicate, keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]), !found.isEmpty {
                        cont.resume(returning: true)
                        return
                    }
                }
                cont.resume(returning: false)
            }
        }
    }
}

private struct AddToContactsViewControllerRepresentable: UIViewControllerRepresentable {
    let payload: ContactPayload
    
    func makeUIViewController(context: Context) -> UINavigationController {
        let contact = CNMutableContact()
        contact.givenName = payload.givenName
        contact.familyName = payload.familyName
        if let avatarData = payload.avatarData {
            contact.imageData = avatarData
        }
        contact.phoneNumbers = payload.phoneNumbers.map {
            CNLabeledValue(
                label: CNLabelPhoneNumberMobile,
                value: CNPhoneNumber(stringValue: $0.value),
            )
        }
        contact.emailAddresses = payload.emailAddresses.map {
            CNLabeledValue(label: CNLabelHome, value: NSString(string: $0.value))
        }
        let vc = CNContactViewController(forNewContact: contact)
        vc.contactStore = CNContactStore()
        vc.allowsEditing = true
        vc.allowsActions = true
        return UINavigationController(rootViewController: vc)
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
