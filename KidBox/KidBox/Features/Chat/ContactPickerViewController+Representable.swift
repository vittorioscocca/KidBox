import Contacts
import ContactsUI
import SwiftUI

struct ContactPickerRepresentable: UIViewControllerRepresentable {
    let onPick: (ContactPayload) -> Void
    let onCancel: () -> Void
    
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }
    
    final class Coordinator: NSObject, CNContactPickerDelegate {
        private let onPick: (ContactPayload) -> Void
        private let onCancel: () -> Void
        
        init(onPick: @escaping (ContactPayload) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }
        
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onPick(ContactPayload.fromCNContact(contact))
        }
        
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }
    }
}
