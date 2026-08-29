//
//  SettingsFamilyCard.swift
//  KidBox
//
//  La card Famiglia in cima a Impostazioni: il nome della famiglia, chi sei tu
//  dentro, e la via d'uscita.
//
//  Sta qui e non solo dentro la schermata Famiglia perché sono le due cose che
//  si vengono a cercare in Impostazioni — di che famiglia faccio parte, e come
//  ne esco — e non meritano un passaggio in più. Il resto (figli, membri,
//  inviti) resta nella schermata, a un tap dal titolo.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct SettingsFamilyCard: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext

    @Query private var families: [KBFamily]
    @Query private var members: [KBFamilyMember]

    @StateObject private var leaveFlow = FamilyLeaveFlow()
    @StateObject private var photoLoader = HeroImageLoader()

    private var family: KBFamily? {
        if let activeId = coordinator.activeFamilyId {
            return families.first(where: { $0.id == activeId }) ?? families.first
        }
        return families.first
    }

    private var currentUid: String { Auth.auth().currentUser?.uid ?? "" }

    /// Un membro per utente, i cancellati fuori: la stessa lista che decide se
    /// puoi uscire o devi prima trasferire la ownership.
    private var activeMembers: [KBFamilyMember] {
        guard let fid = family?.id else { return [] }
        var seen = Set<String>()
        return members
            .filter { $0.familyId == fid && !$0.isDeleted }
            .filter { seen.insert($0.userId).inserted }
    }

    private var me: KBFamilyMember? {
        activeMembers.first(where: { $0.userId == currentUid })
    }

    private var isOwner: Bool {
        guard let family else { return false }
        return family.createdBy == currentUid
            || activeMembers.contains { $0.userId == currentUid && $0.role.lowercased() == "owner" }
    }

    private var heroPhotoURL: URL? {
        guard let raw = family?.heroPhotoURL, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Famiglia")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Senza famiglia la card resta: è l'unico posto da cui
                    // crearne una o entrare con un codice.
                    Text(kbTrimmedNonEmpty(family?.name) ?? String(localized: "Nessuna famiglia configurata"))
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    Button {
                        KBLog.navigation.kbDebug("Settings -> Family settings tap (card)")
                        coordinator.navigate(to: .familySettings)
                    } label: {
                        Text("Impostazioni famiglia")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KBTheme.bubbleTint)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }

                Spacer(minLength: 0)

                photo
            }

            if family != nil {
                memberRow
            }
        }
        .padding(.vertical, 6)
        .onAppear { photoLoader.load(url: heroPhotoURL, updatedAt: family?.heroPhotoUpdatedAt) }
        .onChange(of: family?.heroPhotoUpdatedAt) { _, _ in
            photoLoader.load(url: heroPhotoURL, updatedAt: family?.heroPhotoUpdatedAt)
        }
        .familyLeaveAlerts(
            leaveFlow,
            familyId: family?.id,
            modelContext: modelContext,
            coordinator: coordinator
        )
    }

    /// La foto scelta in Home. Quando non ce n'è una, la prima immagine del
    /// carosello: un riquadro vuoto direbbe che manca qualcosa, mentre la foto
    /// è facoltativa.
    private var photo: some View {
        Group {
            if let image = photoLoader.image {
                Image(uiImage: image).resizable()
            } else {
                Image("HomePromoInvite").resizable()
            }
        }
        .scaledToFill()
        .frame(width: 84, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Chi sei tu in questa famiglia, e come ne esci.
    private var memberRow: some View {
        // Il nome viene dalla riga membro, ma se quella non è ancora arrivata
        // resta quello dell'account: qui deve comparire chi sei, non un'etichetta
        // di ruolo.
        let authUser = Auth.auth().currentUser
        let name = kbTrimmedNonEmpty(me?.displayName)
            ?? kbTrimmedNonEmpty(authUser?.displayName)
            ?? kbTrimmedNonEmpty(me?.email)
            ?? kbTrimmedNonEmpty(authUser?.email)
            ?? String(localized: "Utente")
        let email = kbTrimmedNonEmpty(me?.email) ?? kbTrimmedNonEmpty(authUser?.email)
        // `LocalizedStringKey` esplicito: un ternario di stringhe darebbe a
        // `Text` una String già formata, che non passa dal catalogo.
        let roleLabel: LocalizedStringKey = isOwner ? "Owner" : "Membro"

        return HStack(spacing: 12) {
            Text(name.prefix(1).uppercased())
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(Color(.tertiarySystemFill))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                // L'email si ripete solo quando il nome non è già l'email.
                if let email, email != name {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                // Il ruolo si vede sempre, owner o membro che sia: dice cosa puoi
                // fare in questa famiglia, e sta sopra il tasto che la lascia.
                Text(roleLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isOwner ? KBTheme.bubbleTint : Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isOwner ? KBTheme.bubbleTint.opacity(0.12) : Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Su due righe di proposito: in una sola si mangiava la
                // larghezza che serve a nome ed email per non finire in puntini.
                Button {
                    KBLog.navigation.kbInfo("Settings: tap leave family from card")
                    leaveFlow.requestLeave(
                        activeMembers: activeMembers,
                        isOwner: isOwner,
                        currentUid: currentUid
                    )
                } label: {
                    Text("Abbandona famiglia")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80, alignment: .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemFill).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
