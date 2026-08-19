//
//  OnboardingWalkthroughView.swift
//  KidBox
//
//  Walkthrough di benvenuto: 5–6 schermate animate.
//
//  Pagina 0 — Benvenuto
//  Pagina 1 — Foto condivise
//  Pagina 2 — Salute e spese
//  Pagina 3 — Scelta percorso: crea famiglia vs entra con link/QR
//  Pagina 4 — Crea famiglia (percorso .create) oppure Join (percorso .join)
//  Pagina 5 — Invita partner (solo percorso .create; QR da InviteCodeViewModel)
//
//  Integrazione in RootGateView:
//    } else if !coordinator.hasSeenOnboarding {
//        OnboardingWalkthroughView {
//            coordinator.completeOnboarding()
//        }
//    } else {
//        HomeView()
//    }
//

import SwiftUI
import SwiftData
import FirebaseAuth
import CryptoKit

// MARK: - Page model

private struct OnboardingPage: Identifiable {
    let id:          Int
    let icon:        String
    let iconColor:   Color
    let accentColor: Color
    let title:       String
    let subtitle:    String
}

// MARK: - OnboardingWalkthroughView

struct OnboardingWalkthroughView: View {
    
    private enum FamilyOnboardingPath: Equatable {
        case create
        case join
        /// Impostato in automatico quando c'è un `PendingFamilyInvite` da
        /// link: sostituisce la scelta percorso con la conferma d'invito.
        case linkJoin
    }
    
    let onFinish: () -> Void
    
    private let infoPages: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            icon:        "heart.fill",
            iconColor:   Color(red: 1.00, green: 0.75, blue: 0.25),
            accentColor: Color(red: 0.95, green: 0.38, blue: 0.10),
            title:       "La tua famiglia,\nin un'unica app.",
            subtitle:    "Tutto quello che riguarda i tuoi figli — organizzato, condiviso e sempre a portata di mano."
        ),
        OnboardingPage(
            id: 1,
            icon:        "photo.stack.fill",
            iconColor:   Color(red: 0.60, green: 0.45, blue: 0.85),
            accentColor: Color(red: 0.50, green: 0.35, blue: 0.80),
            title:       "Ricordi condivisi\ncon il tuo partner.",
            subtitle:    "Foto, video e momenti speciali in una galleria privata, cifrata e sincronizzata in tempo reale."
        ),
        OnboardingPage(
            id: 2,
            icon:        "stethoscope",
            iconColor:   Color(red: 0.30, green: 0.65, blue: 0.45),
            accentColor: Color(red: 0.20, green: 0.55, blue: 0.38),
            title:       "Salute, spese\ne molto altro.",
            subtitle:    "Visite mediche, vaccini, spese di famiglia, password sicure di famiglia e lista della spesa. Tutto aggiornato tra voi due."
        )
    ]
    
    // MARK: State
    
    @State private var currentPage     = 0
    @State private var iconScale:      CGFloat = 0.4
    @State private var iconOpacity:    Double  = 0
    @State private var textOpacity:    Double  = 0
    @State private var textOffset:     CGFloat = 24
    @State private var bgOpacity:      Double  = 0
    @State private var ctaScale:       CGFloat = 0.92
    @State private var isTransitioning = false
    
    // Famiglia creata nel flusso "crea", usata dalla pagina invito
    @State private var createdFamilyId: String? = nil

    @State private var familyPath: FamilyOnboardingPath? = nil

    // Invito da link, se il wizard è partito da un Universal Link.
    @State private var pendingLinkInvite: PendingFamilyInvite? = nil
    @State private var linkInvitePreview: InviteRemoteStore.InvitePreview? = nil

    // Anagrafica raccolta a pagina 4, salvata dal CTA prima di proseguire.
    @State private var profileFirstName   = ""
    @State private var profileLastName    = ""
    @State private var isSavingProfile    = false
    @State private var profileSaveError: String? = nil
    
    @Environment(\.colorScheme)  private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    
    // MARK: Helpers
    
    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.10, green: 0.10, blue: 0.10)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    private var cardBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.16, green: 0.16, blue: 0.16)
        : .white
    }
    
    // Pagine: 0-2 info · 3 scelta percorso (o conferma invito da link) ·
    // 4 nome e cognome · 5 crea famiglia / entra con link o QR ·
    // 6 invita (solo percorso "crea").
    //
    // Percorso `.linkJoin`: solo 4 pagine (0-2 info + 3), perché la 3 chiede
    // già nome e cognome e fa il join — non serve altro.
    private var totalPages: Int {
        switch familyPath {
        case .linkJoin: return 4
        case .join: return 6
        default: return 7
        }
    }

    private var isInfoPage: Bool { currentPage < 3 }
    private var isLinkJoinPage: Bool { currentPage == 3 && familyPath == .linkJoin }
    private var isPathPickerPage: Bool { currentPage == 3 && familyPath != .linkJoin }
    private var isNamePage: Bool { currentPage == 4 }
    private var isCreatePage: Bool { currentPage == 5 && familyPath == .create }
    private var isJoinPage: Bool { currentPage == 5 && familyPath == .join }
    private var isInvitePage: Bool { currentPage == 6 && familyPath == .create }
    private var isLastPage: Bool { currentPage == totalPages - 1 }
    
    private var infoPage: OnboardingPage { infoPages[min(currentPage, infoPages.count - 1)] }
    
    private var currentAccent: Color {
        switch currentPage {
        case 0: return Color(red: 0.95, green: 0.38, blue: 0.10)
        case 1: return Color(red: 0.50, green: 0.35, blue: 0.80)
        case 2: return Color(red: 0.20, green: 0.55, blue: 0.38)
        case 3: return Color(red: 0.95, green: 0.38, blue: 0.10)
        // 4 = nome e cognome: resta sull'arancio del percorso, il colore del
        // ramo join entra in gioco solo dalla pagina successiva.
        case 4: return Color(red: 0.95, green: 0.38, blue: 0.10)
        case 5:
            if familyPath == .join {
                return Color(red: 0.55, green: 0.35, blue: 0.9)
            }
            return Color(red: 0.95, green: 0.38, blue: 0.10)
        case 6: return Color(red: 0.95, green: 0.38, blue: 0.10)
        default: return Color(red: 0.95, green: 0.38, blue: 0.10)
        }
    }
    private var currentIconColor: Color {
        switch currentPage {
        case 0: return Color(red: 1.00, green: 0.75, blue: 0.25)
        case 1: return Color(red: 0.60, green: 0.45, blue: 0.85)
        case 2: return Color(red: 0.30, green: 0.65, blue: 0.45)
        case 3: return Color(red: 1.00, green: 0.75, blue: 0.25)
        case 4: return Color(red: 1.00, green: 0.75, blue: 0.25)
        case 5:
            if familyPath == .join {
                return Color(red: 0.60, green: 0.45, blue: 0.85)
            }
            return Color(red: 1.00, green: 0.75, blue: 0.25)
        case 6: return Color(red: 1.00, green: 0.75, blue: 0.25)
        default: return Color(red: 1.00, green: 0.75, blue: 0.25)
        }
    }
    
    // MARK: Body
    
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            VStack {
                LinearGradient(
                    colors: [currentAccent.opacity(colorScheme == .dark ? 0.18 : 0.10), Color.clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 380)
                .ignoresSafeArea()
                .opacity(bgOpacity)
                .animation(.easeInOut(duration: 0.5), value: currentPage)
                Spacer()
            }
            
            VStack(spacing: 0) {
                Spacer()
                
                // Contenuto principale
                Group {
                    if isInfoPage {
                        // Pagine info 0-2
                        iconCard
                            .scaleEffect(iconScale)
                            .opacity(iconOpacity)
                        
                        Spacer().frame(height: 48)
                        
                        textBlock
                            .opacity(textOpacity)
                            .offset(y: textOffset)
                        
                    } else if isLinkJoinPage, let invite = pendingLinkInvite {
                        LinkInviteConfirmCard(
                            cardBackground: cardBackground,
                            accentColor:    currentAccent,
                            iconColor:      currentIconColor,
                            invite:         invite,
                            preview:        linkInvitePreview,
                            modelContext:   modelContext,
                            coordinator:    coordinator,
                            firstName:      $profileFirstName,
                            lastName:       $profileLastName,
                            onJoined: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    bgOpacity = 0; textOpacity = 0; iconOpacity = 0
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onFinish() }
                            },
                            onFallbackToManual: {
                                PendingFamilyInvite.clear()
                                pendingLinkInvite = nil
                                familyPath = nil
                            }
                        )
                        .padding(.horizontal, 24)
                        .opacity(textOpacity)
                        .offset(y: textOffset)

                    } else if isPathPickerPage {
                        FamilyPathPickerCard(
                            cardBackground: cardBackground,
                            accentColor:    currentAccent,
                            selectedPath:   $familyPath
                        )
                        .padding(.horizontal, 24)
                        .opacity(textOpacity)
                        .offset(y: textOffset)
                        
                    } else if isNamePage {
                        NameOnboardingCard(
                            cardBackground: cardBackground,
                            accentColor:    currentAccent,
                            iconColor:      currentIconColor,
                            firstName:      $profileFirstName,
                            lastName:       $profileLastName,
                            isBusy:         isSavingProfile,
                            errorText:      profileSaveError
                        )
                        .padding(.horizontal, 24)
                        .opacity(textOpacity)
                        .offset(y: textOffset)

                    } else if isCreatePage {
                        CreateFamilyCard(
                            cardBackground: cardBackground,
                            accentColor:    currentAccent,
                            iconColor:      currentIconColor,
                            modelContext:   modelContext,
                            onFamilyCreated: { familyId in
                                createdFamilyId = familyId
                                coordinator.setActiveFamily(familyId)
                                // Il documento membro è appena nato: ora che la
                                // famiglia esiste il nome raccolto a pagina 4 può
                                // arrivarci, altrimenti resterebbe solo su users/{uid}.
                                Task {
                                    await UserProfileWriter.propagateDisplayNameToMember(
                                        familyId: familyId,
                                        modelContext: modelContext
                                    )
                                }
                            }
                        )
                        .padding(.horizontal, 24)
                        .opacity(textOpacity)
                        .offset(y: textOffset)

                    } else if isJoinPage {
                        JoinFamilyOnboardingCard(
                            cardBackground: cardBackground,
                            accentColor:    currentAccent,
                            modelContext:   modelContext,
                            coordinator:    coordinator,
                            onJoined: {
                                // Il nome sul documento membro lo scrive
                                // `FamilyInviteLinkJoiner`, attraversato da ogni join.
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    bgOpacity = 0
                                    textOpacity = 0
                                    iconOpacity = 0
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    onFinish()
                                }
                            }
                        )
                        .padding(.horizontal, 24)
                        .opacity(textOpacity)
                        .offset(y: textOffset)
                        
                    } else if isInvitePage {
                        InviteOnboardingCard(
                            cardBackground: cardBackground,
                            accentColor:    currentAccent,
                            iconColor:      currentIconColor,
                            modelContext:   modelContext,
                            coordinator:    coordinator,
                            onFinish: { _ in
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    bgOpacity = 0; textOpacity = 0; iconOpacity = 0; ctaScale = 0.88
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onFinish() }
                            }
                        )
                        .padding(.horizontal, 24)
                        .opacity(textOpacity)
                        .offset(y: textOffset)
                    }
                }
                
                Spacer()
                
                pageIndicators
                    .padding(.bottom, 32)
                
                if isJoinPage || isLinkJoinPage {
                    Spacer()
                        .frame(height: 56)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 52)
                } else {
                    ctaButton
                        .scaleEffect(ctaScale)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 52)
                }
            }
        }
        .onAppear {
            animateIn()
            prefillNameFromExistingProfile()
            loadPendingLinkInviteIfAny()
        }
        // Segnala a RootGateView che siamo nel percorso "crea": così l'inserimento locale
        // della KBFamily (che avviene prima ancora di premere "Continua") non fa completare
        // l'onboarding automaticamente saltando la pagina del QR. Impostato qui, alla scelta
        // del percorso, così è già attivo prima che parta FamilyCreationService.
        .onChange(of: familyPath) { _, newPath in
            coordinator.isCreatingFamilyInOnboarding = (newPath == .create)
        }
        // Link toccato mentre il wizard era già aperto: senza questo, l'invito
        // resterebbe in attesa fino al riavvio dell'app e l'utente vedrebbe il
        // percorso manuale pur avendo appena cliccato l'invito.
        .onReceive(NotificationCenter.default.publisher(for: .kbPendingFamilyInviteStored)) { _ in
            loadPendingLinkInviteIfAny(force: true)
        }
    }

    // MARK: - Subviews info pages
    
    private var iconCard: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [currentIconColor.opacity(0.35), Color.clear],
                    center: .center, startRadius: 30, endRadius: 100
                ))
                .frame(width: 200, height: 200)
            
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(cardBackground)
                .frame(width: 130, height: 130)
                .shadow(color: currentIconColor.opacity(colorScheme == .dark ? 0.4 : 0.25),
                        radius: 30, x: 0, y: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .strokeBorder(currentIconColor.opacity(0.15), lineWidth: 1)
                )
            
            Image(systemName: infoPage.icon)
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(LinearGradient(
                    colors: [currentIconColor, currentAccent],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
        }
    }
    
    private var textBlock: some View {
        VStack(spacing: 14) {
            Text(infoPage.title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            Text(infoPage.subtitle)
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 32)
    }
    
    // MARK: - Page indicators
    
    private var pageIndicators: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { i in
                Capsule()
                    .fill(i == currentPage ? currentAccent : Color.secondary.opacity(0.25))
                    .frame(width: i == currentPage ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentPage)
            }
        }
    }
    
    // MARK: - CTA
    
    @ViewBuilder
    private var ctaButton: some View {
        if !isInvitePage {
        Button { handleCTA() } label: {
            HStack(spacing: 10) {
                Text(ctaLabel)
                    .font(.system(size: 17, weight: .semibold))
                Image(systemName: isLastPage ? "arrow.right.circle.fill" : "arrow.right")
                    .font(.system(size: isLastPage ? 20 : 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: isCTADisabled
                    ? [Color.secondary.opacity(0.35), Color.secondary.opacity(0.35)]
                    : [currentIconColor, currentAccent],
                    startPoint: .leading, endPoint: .trailing
                ),
                in: Capsule()
            )
            .shadow(color: currentAccent.opacity(isCTADisabled ? 0 : 0.4), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(isCTADisabled)
        .opacity(isCTADisabled ? 0.45 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
        } // end if !isInvitePage
    }

    private var isCTADisabled: Bool {
        if currentPage == 3 && familyPath == nil { return true }
        if currentPage == 4 && !canSubmitName { return true }
        if currentPage == 5 && familyPath == .create && createdFamilyId == nil { return true }
        return false
    }

    /// Nome e cognome sono entrambi obbligatori: un `displayName` a metà
    /// (solo nome o solo cognome) è peggio del segnaposto, perché sembra
    /// completo pur non essendolo.
    private var canSubmitName: Bool {
        !profileFirstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !profileLastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isSavingProfile
    }

    private var ctaLabel: String {
        switch currentPage {
        case 3: return "Continua"
        case 4: return isSavingProfile ? "Salvataggio…" : "Continua"
        case 5: return familyPath == .join ? "Inizia" : "Continua"
        case 6: return "Inizia"
        default: return "Continua"
        }
    }
    
    // MARK: - Navigation
    
    private func handleCTA() {
        if isLastPage {
            withAnimation(.easeInOut(duration: 0.3)) {
                bgOpacity = 0; textOpacity = 0; iconOpacity = 0; ctaScale = 0.88
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onFinish() }
        } else if isNamePage {
            // Si avanza solo a salvataggio riuscito: proseguire dopo un errore
            // lascerebbe l'utente convinto di aver messo il nome, e la famiglia
            // nascerebbe comunque con un membro anonimo.
            Task { await saveNameThenAdvance() }
        } else {
            advancePage()
        }
    }

    /// Precompila i campi da quello che già si sa dell'utente.
    ///
    /// Il profilo locale ha la precedenza; in mancanza si spezza il
    /// `displayName` di Firebase Auth, che con Google e Facebook arriva già
    /// valorizzato. Senza questo, chi entra con un social si troverebbe a
    /// riscrivere un nome che l'app conosce già.
    @MainActor
    private func prefillNameFromExistingProfile() {
        guard profileFirstName.isEmpty, profileLastName.isEmpty else { return }
        guard let user = Auth.auth().currentUser else { return }

        let uid = user.uid
        let desc = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
        if let profile = try? modelContext.fetch(desc).first {
            let fn = (profile.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ln = (profile.lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !fn.isEmpty || !ln.isEmpty {
                profileFirstName = fn
                profileLastName = ln
                return
            }
        }

        let display = (user.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !display.isEmpty, display != "Utente" else { return }
        var parts = display.split(separator: " ").map(String.init)
        guard !parts.isEmpty else { return }
        profileFirstName = parts.removeFirst()
        profileLastName = parts.joined(separator: " ")
    }

    /// Se il wizard è partito da un Universal Link, salta la scelta percorso
    /// e mostra direttamente la conferma d'invito (pagina 3, `.linkJoin`).
    ///
    /// Il controllo va fatto una volta sola all'apertura: `familyPath` diventa
    /// poi lo stato di navigazione, e un secondo tocco sul link a wizard già
    /// avviato non deve resettare la pagina in cui l'utente si trova.
    @MainActor
    private func loadPendingLinkInviteIfAny(force: Bool = false) {
        // `force` serve quando il link arriva ad app già aperta: lì il percorso
        // può essere già stato scelto, e va comunque scavalcato — l'utente ha
        // appena toccato un invito, è quello che vuole fare.
        guard force || familyPath == nil else { return }
        guard let invite = PendingFamilyInvite.load() else { return }
        pendingLinkInvite = invite
        familyPath = .linkJoin
        // `.linkJoin` ha 4 pagine (0-2 + conferma): se l'utente era più avanti
        // nel percorso manuale, il pager resterebbe su un indice inesistente.
        if currentPage > 3 { currentPage = 3 }
        Task {
            let preview = await InviteRemoteStore().fetchInvitePreview(
                familyId: invite.familyId,
                inviteId: invite.inviteId
            )
            await MainActor.run { linkInvitePreview = preview }
        }
    }

    @MainActor
    private func saveNameThenAdvance() async {
        guard !isSavingProfile else { return }
        isSavingProfile = true
        profileSaveError = nil
        defer { isSavingProfile = false }

        do {
            try await UserProfileWriter.saveNames(
                firstName: profileFirstName,
                lastName: profileLastName,
                modelContext: modelContext
            )
            KBLog.auth.kbInfo("Onboarding: profile names saved, advancing")
            advancePage()
        } catch {
            profileSaveError = error.localizedDescription
            KBLog.auth.kbError("Onboarding: profile names save failed: \(error.localizedDescription)")
        }
    }
    
    private func advancePage() {
        guard !isTransitioning else { return }
        isTransitioning = true
        
        withAnimation(.easeIn(duration: 0.18)) {
            textOpacity = 0; textOffset = -16; iconScale = 0.85; iconOpacity = 0.3
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            currentPage += 1
            textOffset = 28; iconScale = 0.5
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
                iconScale = 1.0; iconOpacity = 1.0; textOpacity = 1.0; textOffset = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTransitioning = false
            }
        }
    }
    
    private func animateIn() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.68).delay(0.1)) {
            iconScale = 1.0; iconOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
            textOpacity = 1.0; textOffset = 0
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.2)) { bgOpacity = 1.0 }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.4)) { ctaScale = 1.0 }
    }
    
    // MARK: - Path picker (pagina 3)
    
    private struct FamilyPathPickerCard: View {
        let cardBackground: Color
        let accentColor: Color
        @Binding var selectedPath: FamilyOnboardingPath?
        
        var body: some View {
            VStack(spacing: 16) {
                Text("Come vuoi iniziare?")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                pathOption(
                    path: .create,
                    icon: "house.fill",
                    color: Color(red: 0.95, green: 0.38, blue: 0.10),
                    title: "Crea la tua famiglia",
                    subtitle: "Sarai il creatore e potrai invitare il tuo partner."
                )
                
                pathOption(
                    path: .join,
                    icon: "qrcode.viewfinder",
                    color: Color(red: 0.55, green: 0.35, blue: 0.9),
                    title: "Entra in una famiglia",
                    subtitle: "Hai un link d'invito o un codice QR? Usalo per unirti."
                )
            }
            .padding(24)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: accentColor.opacity(0.12), radius: 20, x: 0, y: 10)
        }
        
        @ViewBuilder
        private func pathOption(
            path: FamilyOnboardingPath,
            icon: String,
            color: Color,
            title: String,
            subtitle: String
        ) -> some View {
            let isSelected = selectedPath == path
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(color.opacity(isSelected ? 0.2 : 0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? color : Color.secondary.opacity(0.4))
                    .font(.title3)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? color.opacity(0.07) : Color.secondary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3)) { selectedPath = path }
            }
        }
    }
    
    // MARK: - Join famiglia (pagina 4, percorso .join)
    
    private struct JoinFamilyOnboardingCard: View {
        let cardBackground: Color
        let accentColor: Color
        let coordinator: AppCoordinator
        let onJoined: () -> Void
        
        @StateObject private var vm: JoinFamilyViewModel
        @State private var showScanner = false
        
        private var joinTint: Color { Color(red: 0.60, green: 0.45, blue: 0.85) }
        
        init(
            cardBackground: Color,
            accentColor: Color,
            modelContext: ModelContext,
            coordinator: AppCoordinator,
            onJoined: @escaping () -> Void
        ) {
            self.cardBackground = cardBackground
            self.accentColor = accentColor
            self.coordinator = coordinator
            self.onJoined = onJoined
            _vm = StateObject(wrappedValue: JoinFamilyViewModel(
                modelContext: modelContext,
                coordinator: coordinator
            ))
        }
        
        var body: some View {
            VStack(spacing: 20) {
                Text("Entra nella famiglia")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Niente più codice da digitare: si entra dal link d'invito —
                // che apre l'app da solo — oppure inquadrando il QR.
                Text("Hai ricevuto un link d'invito? Aprilo e ti porta qui dentro. Altrimenti inquadra il codice QR di chi ti invita.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Button {
                    showScanner = true
                } label: {
                    Label("Scansiona QR", systemImage: "qrcode.viewfinder")
                        .font(.subheadline.bold())
                        .foregroundStyle(accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(vm.didJoin)
                
                if let error = vm.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if vm.didJoin {
                    Label("Famiglia aggiunta!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if vm.isBusy {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Ingresso in corso…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: accentColor.opacity(0.12), radius: 20, x: 0, y: 10)
            .sheet(isPresented: $showScanner) {
                OnboardingQRScannerSheet(
                    onDetected: { raw in
                        showScanner = false
                        Task { await vm.joinFromQR(payload: raw) }
                    },
                    onClose: { showScanner = false }
                )
            }
            .onChange(of: vm.didJoin) { _, joined in
                // L'avviso "senza chiave" non serve più: entrambe le strade
                // rimaste (link e QR) trasportano la chiave, quindi un join
                // riuscito è sempre completo.
                guard joined else { return }
                onJoined()
            }
        }
    }
}

// MARK: - Onboarding QR scanner (stesso flusso di JoinFamilyView)

private struct OnboardingQRScannerSheet: View {
    var onDetected: (String) -> Void
    var onClose: () -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                QRCodeScannerView(onCode: onDetected)
                    .ignoresSafeArea()
                
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                    .frame(width: 260, height: 260)
            }
            .navigationTitle("Scansiona QR")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") { onClose() }
                }
            }
        }
    }
}

// MARK: - LinkInviteConfirmCard
//
// Sostituisce la scelta percorso quando il wizard parte da un Universal Link:
// mostra la famiglia (e chi ha invitato, se noti), chiede nome e cognome e fa
// il join in un solo passaggio — niente QR, niente scelta manuale.

private struct LinkInviteConfirmCard: View {
    let cardBackground: Color
    let accentColor: Color
    let iconColor: Color
    let invite: PendingFamilyInvite
    let preview: InviteRemoteStore.InvitePreview?
    let modelContext: ModelContext
    let coordinator: AppCoordinator
    @Binding var firstName: String
    @Binding var lastName: String
    let onJoined: () -> Void
    let onFallbackToManual: () -> Void

    @State private var isBusy = false
    @State private var errorText: String?

    @FocusState private var focusedField: Field?
    private enum Field { case first, last }

    private var canSubmit: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isBusy
    }

    var body: some View {
        VStack(spacing: 24) {

            // Header
            VStack(spacing: 12) {
                ZStack {
                    Circle().fill(iconColor.opacity(0.15)).frame(width: 72, height: 72)
                    Image(systemName: "envelope.open.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(LinearGradient(
                            colors: [iconColor, accentColor],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                }
                if let familyName = preview?.familyName, !familyName.isEmpty {
                    Text("Stai per entrare nella famiglia di \(familyName)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                } else {
                    Text("Stai per entrare in una famiglia")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                }
                if let inviter = preview?.inviterDisplayName, !inviter.isEmpty {
                    Text("Invitato da \(inviter). Dicci come ti chiami ed entri subito.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                } else {
                    Text("Dicci come ti chiami ed entri subito.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 8)

            // Nome / Cognome
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nome")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Image(systemName: "person.fill")
                            .foregroundStyle(accentColor)
                            .frame(width: 20)
                        TextField("Es. Giulia", text: $firstName)
                            .focused($focusedField, equals: .first)
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .disabled(isBusy)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .last }
                    }
                    .padding(14)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(focusedField == .first ? accentColor : Color.secondary.opacity(0.15), lineWidth: 1.5)
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Cognome")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Image(systemName: "person.fill")
                            .foregroundStyle(accentColor)
                            .frame(width: 20)
                        TextField("Es. Rossi", text: $lastName)
                            .focused($focusedField, equals: .last)
                            .textContentType(.familyName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .disabled(isBusy)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                    }
                    .padding(14)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(focusedField == .last ? accentColor : Color.secondary.opacity(0.15), lineWidth: 1.5)
                    )
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await joinFamily() }
            } label: {
                HStack(spacing: 10) {
                    if isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Text("Entra nella famiglia")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(
                    LinearGradient(colors: [iconColor, accentColor],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .shadow(color: accentColor.opacity(canSubmit ? 0.35 : 0), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1.0 : 0.5)

            Button("Non funziona? Passa al metodo manuale", action: onFallbackToManual)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .disabled(isBusy)
        }
        .padding(24)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: accentColor.opacity(0.12), radius: 20, x: 0, y: 10)
    }

    @MainActor
    private func joinFamily() async {
        guard !isBusy else { return }
        isBusy = true
        errorText = nil
        defer { isBusy = false }

        do {
            try await UserProfileWriter.saveNames(
                firstName: firstName,
                lastName: lastName,
                modelContext: modelContext
            )
            // Il nome è già salvato sopra, e `FamilyInviteLinkJoiner` lo porta
            // sul documento membro appena creato.
            try await FamilyInviteLinkJoiner.join(
                invite: invite,
                modelContext: modelContext,
                coordinator: coordinator
            )
            PendingFamilyInvite.clear()
            KBLog.sync.kbInfo("LinkInviteConfirmCard: join riuscito familyId=\(invite.familyId)")
            onJoined()
        } catch {
            errorText = error.localizedDescription
            KBLog.sync.kbError("LinkInviteConfirmCard: join fallito: \(error.localizedDescription)")
        }
    }
}

// MARK: - CreateFamilyCard
//
// Schermata 4: nome famiglia + nome primo figlio.
// Chiama FamilyCreationService e salva il familyId nel parent via onFamilyCreated.

// MARK: - NameOnboardingCard
//
// Schermata 4: nome e cognome dell'utente, raccolti prima della famiglia.
//
// Sta prima apposta: il documento membro nasce alla creazione/join della
// famiglia, quindi avere già il nome permette di scriverlo lì subito invece di
// lasciare il membro anonimo agli occhi degli altri finché non apre il Profilo.
// Il salvataggio vero lo fa il parent nel CTA, via `UserProfileWriter`.

struct NameOnboardingCard: View {

    let cardBackground: Color
    let accentColor:    Color
    let iconColor:      Color

    @Binding var firstName: String
    @Binding var lastName:  String
    let isBusy:    Bool
    let errorText: String?

    @FocusState private var focusedField: Field?
    private enum Field { case first, last }

    var body: some View {
        VStack(spacing: 24) {

            // Header
            VStack(spacing: 12) {
                ZStack {
                    Circle().fill(iconColor.opacity(0.15)).frame(width: 72, height: 72)
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(LinearGradient(
                            colors: [iconColor, accentColor],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                }
                Text("Come ti chiami?")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("Il tuo nome è quello che gli altri membri vedranno in chat, nei promemoria e sulla mappa. Potrai cambiarlo dal Profilo.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 8)

            // Form
            VStack(spacing: 12) {

                VStack(alignment: .leading, spacing: 6) {
                    Text("Nome")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Image(systemName: "person.fill")
                            .foregroundStyle(accentColor)
                            .frame(width: 20)
                        TextField("Es. Giulia", text: $firstName)
                            .focused($focusedField, equals: .first)
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .disabled(isBusy)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .last }
                    }
                    .padding(14)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(focusedField == .first ? accentColor : Color.secondary.opacity(0.15), lineWidth: 1.5)
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Cognome")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Image(systemName: "person.fill")
                            .foregroundStyle(accentColor)
                            .frame(width: 20)
                        TextField("Es. Rossi", text: $lastName)
                            .focused($focusedField, equals: .last)
                            .textContentType(.familyName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .disabled(isBusy)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                    }
                    .padding(14)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(focusedField == .last ? accentColor : Color.secondary.opacity(0.15), lineWidth: 1.5)
                    )
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: accentColor.opacity(0.12), radius: 20, x: 0, y: 10)
    }
}

// MARK: - CreateFamilyCard

private struct CreateFamilyCard: View {

    let cardBackground:  Color
    let accentColor:     Color
    let iconColor:       Color
    let modelContext:    ModelContext
    let onFamilyCreated: (String) -> Void
    
    @State private var familyName  = ""
    @State private var childName   = ""
    @State private var childBirth: Date? = nil
    @State private var showDatePicker = false
    @State private var isBusy     = false
    @State private var errorText:  String? = nil
    @State private var didCreate   = false
    
    @FocusState private var focusedField: Field?
    private enum Field { case family, child }
    
    /// Il nome del figlio non entra nella condizione: è facoltativo, e
    /// pretenderlo qui obbligava a inventarne uno pur di superare la schermata.
    private var canCreate: Bool {
        !familyName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isBusy && !didCreate
    }
    
    var body: some View {
        VStack(spacing: 24) {
            
            // Header
            VStack(spacing: 12) {
                ZStack {
                    Circle().fill(iconColor.opacity(0.15)).frame(width: 72, height: 72)
                    Image(systemName: "house.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(LinearGradient(
                            colors: [iconColor, accentColor],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                }
                Text("Crea la tua famiglia")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("Dai un nome alla famiglia e aggiungi il primo figlio. Potrai modificare tutto in seguito.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 8)
            
            // Form
            VStack(spacing: 12) {
                
                // Nome famiglia
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nome famiglia")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(accentColor)
                            .frame(width: 20)
                        TextField("Es. Famiglia Rossi", text: $familyName)
                            .focused($focusedField, equals: .family)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .disabled(didCreate)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .child }
                    }
                    .padding(14)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(focusedField == .family ? accentColor : Color.secondary.opacity(0.15), lineWidth: 1.5)
                    )
                }
                
                // Nome primo figlio
                VStack(alignment: .leading, spacing: 6) {
                    Text("Primo figlio (facoltativo)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Image(systemName: "figure.child")
                            .foregroundStyle(accentColor)
                            .frame(width: 20)
                        TextField("Nome del bambino/a", text: $childName)
                            .focused($focusedField, equals: .child)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .disabled(didCreate)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                    }
                    .padding(14)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(focusedField == .child ? accentColor : Color.secondary.opacity(0.15), lineWidth: 1.5)
                    )
                }
                
                // Data di nascita (opzionale)
                Button {
                    focusedField = nil
                    showDatePicker.toggle()
                } label: {
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundStyle(accentColor)
                            .frame(width: 20)
                        Text(childBirth != nil
                             ? childBirth!.formatted(date: .long, time: .omitted)
                             : "Data di nascita (opzionale)")
                        .foregroundStyle(childBirth != nil ? .primary : .secondary)
                        Spacer()
                        Image(systemName: showDatePicker ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(didCreate)
                
                if showDatePicker {
                    DatePicker("", selection: Binding(
                        get: { childBirth ?? Date() },
                        set: { childBirth = $0 }
                    ), in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(accentColor)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            
            // Pulsante crea / stato
            if didCreate {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                    Text("Famiglia creata! Continua per invitare il partner.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                
            } else {
                Button {
                    Task { await createFamily() }
                } label: {
                    Group {
                        if isBusy {
                            ProgressView().tint(.white)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "house.badge.plus")
                                Text("Crea famiglia")
                            }
                            .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        canCreate
                        ? LinearGradient(colors: [iconColor, accentColor], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [Color.secondary.opacity(0.3), Color.secondary.opacity(0.3)], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canCreate)
            }
            
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            
            // Skip
            Text("Potrai creare la famiglia anche dopo da Impostazioni")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: didCreate)
        .animation(.easeInOut(duration: 0.25), value: showDatePicker)
    }
    
    @MainActor
    private func createFamily() async {
        let name  = familyName.trimmingCharacters(in: .whitespaces)
        let child = childName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        
        do {
            let service = FamilyCreationService(remote: FamilyRemoteStore(), modelContext: modelContext)
            let created = try await service.createFamily(
                name: name,
                childName: child,
                childBirthDate: childBirth
            )
            let familyId = created.familyId
            
            // Genera e salva la master key crittografica
            let masterKey = InviteCrypto.randomBytes(32)
            let key = CryptoKit.SymmetricKey(data: masterKey)
            try FamilyKeychainStore.saveFamilyKey(
                key,
                familyId: familyId,
                userId: Auth.auth().currentUser?.uid ?? ""
            )
            
            // Collassa il calendario: una volta creata la famiglia non serve più e,
            // se resta espanso, l'altezza della card spinge il CTA "Continua" fuori schermo.
            withAnimation {
                showDatePicker = false
                didCreate = true
            }
            onFamilyCreated(familyId)
            
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - InviteOnboardingCard
//
// Schermata 5: link condivisibile come azione primaria; QR collassabile come secondaria.
// onFinish(_ didShare:) segnala al parent se l'utente ha condiviso o saltato.

private struct InviteOnboardingCard: View {

    let cardBackground: Color
    let accentColor:    Color
    let iconColor:      Color
    let modelContext:   ModelContext
    let coordinator:    AppCoordinator
    let onFinish:       (Bool) -> Void

    @StateObject private var vm: InviteCodeViewModel
    @State private var didGenerate = false
    @State private var didCopy     = false
    @State private var showQR      = false

    init(
        cardBackground: Color,
        accentColor: Color,
        iconColor: Color,
        modelContext: ModelContext,
        coordinator: AppCoordinator,
        onFinish: @escaping (Bool) -> Void
    ) {
        self.cardBackground = cardBackground
        self.accentColor    = accentColor
        self.iconColor      = iconColor
        self.modelContext   = modelContext
        self.coordinator    = coordinator
        self.onFinish       = onFinish
        _vm = StateObject(wrappedValue: InviteCodeViewModel(
            remote: InviteRemoteStore(),
            modelContext: modelContext,
            coordinator: coordinator
        ))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {

                // ── Header ──
                VStack(spacing: 12) {
                    ZStack {
                        Circle().fill(iconColor.opacity(0.15)).frame(width: 72, height: 72)
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(LinearGradient(
                                colors: [iconColor, accentColor],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                    }
                    Text("Manda il link al tuo partner")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text("Invia via WhatsApp o SMS — può unirsi anche dopo, non serve essere vicini.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .padding(.horizontal, 8)

                // ── Pulsante condividi (primario) ──
                if vm.isBusy {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.85).tint(accentColor)
                        Text("Preparazione link…")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Color.secondary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if !vm.shareText.isEmpty {
                    ShareLink(
                        item: vm.shareText,
                        subject: Text(InviteCodeViewModel.shareSubject)
                    ) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Invia link al partner")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(
                            LinearGradient(colors: [iconColor, accentColor],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .shadow(color: accentColor.opacity(0.35), radius: 10, x: 0, y: 5)
                    }

                    // Copia link (secondario)
                    Button {
                        vm.copyToClipboard()
                        withAnimation { didCopy = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { didCopy = false }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 14, weight: .semibold))
                            Text(didCopy ? "Copiato!" : "Copia link")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(didCopy ? .green : .secondary)
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .background(Color.secondary.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    // Il segreto viaggia dentro il link: chi lo riceve entra.
                    Text("Il link contiene la chiave: vale 24 ore, una volta sola. Mandalo solo alla persona giusta.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                } else if let err = vm.errorMessage {
                    VStack(spacing: 8) {
                        Text(err).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Riprova") { Task { await vm.generateInviteCode() } }
                            .font(.caption.weight(.medium)).foregroundStyle(accentColor)
                    }
                    .padding()
                }

                // ── QR collassabile (secondario) ──
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { showQR.toggle() }
                    } label: {
                        HStack {
                            Text("Oppure mostra il QR se siete vicini — più sicuro")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: showQR ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    if showQR, let qrPayload = vm.qrPayload {
                        VStack(spacing: 8) {
                            QRCodeView(payload: qrPayload)
                                .frame(width: 140, height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text("Valido 24 ore").font(.caption).foregroundStyle(.secondary)
                            Text("La chiave viene letta dalla fotocamera: non passa da chat, email o backup.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(cardBackground,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                Divider().padding(.vertical, 4)

                // ── Bottoni di completamento ──
                VStack(spacing: 10) {
                    Button {
                        onFinish(true)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Ho inviato il link")
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(
                            LinearGradient(colors: [iconColor, accentColor],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)

                    Button { onFinish(false) } label: {
                        Text("Farlo dopo →")
                            .font(.system(size: 15))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
        }
        .onAppear {
            guard !didGenerate else { return }
            didGenerate = true
            Task { await vm.generateInviteCode() }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingWalkthroughView { print("done") }
}
