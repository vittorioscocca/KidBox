//
//  KBShareSheet.swift
//  KidBoxShareExtension
//
//  Created by vscocca on 10/03/26.
//

import SwiftUI

struct KBShareSheet: View {
    let payload: KBSharePayload
    let onDismiss: () -> Void
    weak var extensionContext: NSExtensionContext?
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                contentPreview
                    .padding()
                
                Divider()
                
                Text("Invia a…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 16)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(payload.availableDestinations) { dest in
                        NavigationLink {
                            KBShareEditView(
                                destination: dest,
                                payload: payload,
                                onDone: onDismiss,
                                extensionContext: extensionContext
                            )
                        } label: {
                            destinationCard(dest)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                
                Spacer()
            }
            .navigationTitle("Condividi su KidBox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { onDismiss() }
                }
            }
        }
    }
    
    @ViewBuilder
    private var contentPreview: some View {
        switch payload.type {
        case .image(let url):
            if let url, let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(height: 120).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        case .text(let t):
            Text(t)
                .font(.subheadline)
                .lineLimit(3)
                .padding(12)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        case .url(let u):
            Text(u)
                .font(.caption)
                .foregroundStyle(.blue)
                .lineLimit(2)
        default:
            EmptyView()
        }
    }
    
    private func destinationCard(_ dest: KBShareDestination) -> some View {
        HStack(spacing: 12) {
            Image(systemName: dest.icon)
                .font(.title3)
                .foregroundStyle(dest.color)
                .frame(width: 36, height: 36)
                .background(dest.color.opacity(0.12), in: Circle())
            
            Text(dest.label)
                .font(.subheadline.weight(.medium))
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
