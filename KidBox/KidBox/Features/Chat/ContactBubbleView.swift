import SwiftUI

struct ContactBubbleView: View {
    let payload: ContactPayload
    let isOwn: Bool
    let onView: () -> Void
    let timeAndChecks: AnyView
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                avatar
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(payload.fullName)
                        .font(.subheadline.bold())
                        .foregroundStyle(isOwn ? .white : .primary)
                        .lineLimit(2)
                    Text(payload.primaryPhone ?? "Contatto")
                        .font(.caption)
                        .foregroundStyle(isOwn ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            
            Divider()
                .overlay(isOwn ? Color.white.opacity(0.25) : Color.primary.opacity(0.12))
            
            Button(action: onView) {
                HStack {
                    Text("Visualizza")
                        .font(.caption.bold())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                }
                .foregroundStyle(isOwn ? .white.opacity(0.95) : Color.accentColor)
            }
            .buttonStyle(.plain)
            
            HStack {
                Spacer(minLength: 0)
                timeAndChecks
            }
        }
        .frame(maxWidth: 250, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onView)
    }
    
    @ViewBuilder
    private var avatar: some View {
        if let data = payload.avatarData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            ZStack {
                Circle().fill((isOwn ? Color.white : Color.accentColor).opacity(isOwn ? 0.2 : 0.12))
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(isOwn ? Color.white : Color.accentColor)
            }
        }
    }
}
