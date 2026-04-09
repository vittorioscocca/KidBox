import SwiftUI

struct ContactPreviewSheet: View {
    let payload: ContactPayload
    let onSend: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ContactCard(payload: payload)
                Spacer()
                Button(action: onSend) {
                    Text("Invia")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .navigationTitle("Invia contatto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla", action: onCancel)
                }
            }
        }
    }
}

private struct ContactCard: View {
    let payload: ContactPayload
    
    var body: some View {
        VStack(spacing: 12) {
            avatar
                .frame(width: 76, height: 76)
            Text(payload.fullName)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text(payload.primaryPhone ?? "Nessun numero")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
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
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}
