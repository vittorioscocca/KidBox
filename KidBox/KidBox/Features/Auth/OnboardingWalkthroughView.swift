//
//  OnboardingWalkthroughView.swift
//  KidBox
//
//  Wizard post-registrazione, in due schermate.
//
//  Pagina 0 — «Tu e la tua famiglia»: nome, cognome e nome della famiglia,
//              con il CTA che salva il profilo e crea la famiglia in un colpo.
//              In fondo, «Ho un invito» porta al percorso .join (QR).
//  Pagina 1 — Invita il partner (percorso .create) oppure scansione QR
//              (percorso .join).
//
//  Con un invito da Universal Link (`PendingFamilyInvite`) il wizard è una
//  pagina sola: la conferma d'invito, che chiede il nome ed entra.
//
//  Storia: fino alla 2.2.9 il wizard aveva sette pagine — tre slide di
//  presentazione (info_0-2), la scelta del percorso, il nome, la famiglia con
//  il primo figlio, l'invito. GA4 con `last_step_seen` (18/09/2026) diceva che
//  7 abbandoni su 12 si fermavano a info_0: tre schermate che non chiedono
//  niente, mostrate a chi si è appena registrato. Il primo figlio si aggiunge
//  dalla Home, dove ha un senso; le slide di valore restano sullo store e
//  sulla schermata di benvenuto. Obiettivo: iniziato → completato dal 56% al
//  75% sui 28 giorni.
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

// MARK: - OnboardingWalkthroughView

struct OnboardingWalkthroughView: View {

    private enum FamilyOnboardingPath: Equatable {
        case create
        case join
        /// Impostato in automatico quando c'è un `PendingFamilyInvite` da
        /// link: sostituisce tutto con la conferma d'invito.
        case linkJoin
    }

    let onFinish: () -> Void

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

    /// `.create` è il default: la scelta esplicita di pagina «Come vuoi
    /// iniziare?» non c'è più. Chi ha un QR tocca «Ho un invito» e passa a
    /// `.join`; chi ha toccato un link arriva già in `.linkJoin`.
    @State private var familyPath: FamilyOnboardingPath = .create

    // Invito da link, se il wizard è partito da un Universal Link.
    @State private var pendingLinkInvite: PendingFamilyInvite? = nil
    @State private var linkInvitePreview: InviteRemoteStore.InvitePreview? = nil

    // Anagrafica e nome famiglia raccolti a pagina 0, salvati dal CTA.
    @State private var profileFirstName   = ""
    @State private var profileLastName    = ""
    @State private var familyName         = ""
    @State private var isSaving           = false
    @State private var setupError: String? = nil

    // «Esci» in alto a destra su ogni pagina: chi si è registrato con
    // l'account sbagliato, o vuole solo tornare al login, prima non aveva
    // nessuna uscita dal wizard se non disinstallare.
    @State private var showSignOutConfirm = false
    @State private var isSigningOut       = false

    // Invito toccato PRIMA di installare: la pagina /join l'ha copiato negli
    // appunti. `pasteboardMayHaveInvite` lo rileva senza leggere (niente
    // banner); la lettura vera parte solo dal tocco dell'utente.
    // Vedi InvitePasteboardPickup.
    @State private var pasteboardMayHaveInvite = false
    @State private var pasteboardCheckFailed   = false

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

    // Pagine: 0 setup (nome + famiglia) · 1 invito (crea) o QR (join).
    // Percorso `.linkJoin`: una pagina sola, la conferma d'invito.
    private var totalPages: Int { familyPath == .linkJoin ? 1 : 2 }

    private var isLinkJoinPage: Bool { familyPath == .linkJoin }
    private var isSetupPage: Bool { currentPage == 0 && familyPath != .linkJoin }
    private var isJoinPage: Bool { currentPage == 1 && familyPath == .join }
    private var isInvitePage: Bool { currentPage == 1 && familyPath == .create }
    private var isLastPage: Bool { currentPage == totalPages - 1 }

    // Una volta creata la famiglia (o completato un join) non si torna più
    // indietro: la scrittura su Firestore è già avvenuta, e riproporre la
    // pagina precedente farebbe pensare all'utente di poterla ancora annullare.
    private var canGoBack: Bool {
        currentPage > 0 && !isTransitioning && !isSaving && createdFamilyId == nil
    }

    /// Nomi dei passi per GA4. `setup` è nuovo; `create_family`, `name`,
    /// `join_family`, `invite` e `link_invite_confirm` restano quelli di prima,
    /// così il funnel per passo della routine continua a leggersi.
    private func stepName(for page: Int, path: FamilyOnboardingPath) -> String {
        switch (page, path) {
        case (_, .linkJoin): return "link_invite_confirm"
        case (0, _):         return "setup"
        case (1, .join):     return "join_family"
        default:             return "invite"
        }
    }

    private func fireStepShown() {
        let name = stepName(for: currentPage, path: familyPath)
        AppAnalytics.onboardingStepShown(stepName: name, stepNumber: currentPage)
        coordinator.lastOnboardingStepSeen = name
    }

    private var currentAccent: Color {
        familyPath == .join && currentPage == 1
        ? Color(red: 0.55, green: 0.35, blue: 0.9)
        : Color(red: 0.95, green: 0.38, blue: 0.10)
    }
    private var currentIconColor: Color {
        familyPath == .join && currentPage == 1
        ? Color(red: 0.60, green: 0.45, blue: 0.85)
        : Color(red: 1.00, green: 0.75, blue: 0.25)
    }

    // MARK: Body

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()
                // Tocco fuori dai campi = via la tastiera. Senza, sulla pagina
                // setup la tastiera copriva «Crea la famiglia» e l'unico modo
                // per chiuderla era il tasto Fine, che non tutti trovano.
                .contentShape(Rectangle())
                .onTapGesture { dismissKeyboard() }

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

            // ScrollView e non VStack pieno: con la tastiera aperta la pagina
            // setup (tre campi + pulsante) non ci sta, e il pulsante deve
            // restare raggiungibile scorrendo.
            ScrollView(showsIndicators: false) {
              VStack(spacing: 0) {
                Spacer(minLength: 24)

                // Contenuto principale
                Group {
                    if isLinkJoinPage, let invite = pendingLinkInvite {
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
                                AppAnalytics.onboardingStepCompleted(stepName: "link_invite_confirm")
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    bgOpacity = 0; textOpacity = 0; iconOpacity = 0
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onFinish() }
                            },
                            onFallbackToManual: {
                                PendingFamilyInvite.clear()
                                pendingLinkInvite = nil
                                familyPath = .create
                            }
                        )
                        .padding(.horizontal, 24)
                        .opacity(textOpacity)
                        .offset(y: textOffset)

                    } else if isSetupPage {
                        SetupFamilyCard(
                            cardBackground: cardBackground,
                            accentColor:    currentAccent,
                            iconColor:      currentIconColor,
                            firstName:      $profileFirstName,
                            lastName:       $profileLastName,
                            familyName:     $familyName,
                            isJoin:         familyPath == .join,
                            isBusy:         isSaving,
                            errorText:      setupError,
                            onTogglePath: {
                                withAnimation(.spring(response: 0.3)) {
                                    familyPath = familyPath == .join ? .create : .join
                                }
                            },
                            onSubmit: {
                                if canSubmitSetup { handleCTA() }
                            },
                            pasteboardInvite: pasteboardMayHaveInvite,
                            pasteboardInviteFailed: pasteboardCheckFailed,
                            onUseInvite: { useInviteFromPasteboard() }
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
                                AppAnalytics.onboardingStepCompleted(stepName: "join_family")
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

                if totalPages > 1 {
                    pageIndicators
                        .padding(.bottom, 32)
                }

                if isJoinPage || isLinkJoinPage || isInvitePage {
                    // Queste pagine hanno i loro pulsanti dentro la card.
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
              .frame(minHeight: UIScreen.main.bounds.height - 40)
            }
            .scrollDismissesKeyboard(.interactively)

            // Barra in alto (indietro, esci) DOPO la ScrollView: in uno ZStack
            // l'ultimo figlio sta sopra e riceve i tocchi. Prima stava sotto e
            // la ScrollView, che copre tutto lo schermo, si mangiava i tap —
            // il pulsante si vedeva ma non rispondeva.
            VStack {
                HStack {
                    if canGoBack {
                        backButton
                    }
                    Spacer()
                    signOutButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                Spacer()
            }
        }
        .onAppear {
            animateIn()
            prefillNameFromExistingProfile()
            loadPendingLinkInviteIfAny()
            Task { pasteboardMayHaveInvite = await InvitePasteboardPickup.mightHaveInvite() }
            if coordinator.onboardingStartedAt == nil {
                coordinator.onboardingStartedAt = Date()
            }
            fireStepShown()
        }
        .onChange(of: currentPage) { _, _ in
            fireStepShown()
        }
        // Link toccato mentre il wizard era già aperto: senza questo, l'invito
        // resterebbe in attesa fino al riavvio dell'app e l'utente vedrebbe il
        // percorso manuale pur avendo appena cliccato l'invito.
        .onReceive(NotificationCenter.default.publisher(for: .kbPendingFamilyInviteStored)) { _ in
            loadPendingLinkInviteIfAny(force: true)
        }
    }

    // MARK: - Sign out

    private var signOutButton: some View {
        Button {
            dismissKeyboard()
            showSignOutConfirm = true
        } label: {
            Text("Esci")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(currentAccent)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(cardBackground, in: Capsule())
                .shadow(color: currentAccent.opacity(0.12), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isSigningOut || isSaving)
        .alert("Vuoi uscire dall'account?", isPresented: $showSignOutConfirm) {
            Button("Esci", role: .destructive) { signOut() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Torni alla schermata di accesso. Quello che hai già creato resta sul tuo account.")
        }
    }

    private func signOut() {
        guard !isSigningOut else { return }
        isSigningOut = true
        // Flag in memoria del wizard: azzerati subito, altrimenti al prossimo
        // login (magari con un altro account, via join) resterebbero attivi.
        coordinator.isCreatingFamilyInOnboarding = false
        coordinator.lastOnboardingStepSeen = nil
        Task { @MainActor in
            await coordinator.signOut(modelContext: modelContext)
            KBLog.auth.kbInfo("Onboarding: sign out from wizard")
            isSigningOut = false
        }
    }

    // MARK: - Back button

    private var backButton: some View {
        Button(action: goBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(currentAccent)
                .frame(width: 36, height: 36)
                .background(cardBackground, in: Circle())
                .shadow(color: currentAccent.opacity(0.12), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
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

    private var ctaButton: some View {
        Button { handleCTA() } label: {
            HStack(spacing: 10) {
                if isSaving {
                    ProgressView().tint(.white)
                }
                Text(ctaLabel)
                    .font(.system(size: 17, weight: .semibold))
                if !isSaving {
                    Image(systemName: familyPath == .join ? "arrow.right" : "house.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                }
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
    }

    private var isCTADisabled: Bool { !canSubmitSetup }

    /// Nome e cognome sono entrambi obbligatori: un `displayName` a metà
    /// (solo nome o solo cognome) è peggio del segnaposto, perché sembra
    /// completo pur non essendolo. Il nome famiglia serve solo nel percorso
    /// «crea».
    private var canSubmitSetup: Bool {
        !profileFirstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !profileLastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        (familyPath == .join || !familyName.trimmingCharacters(in: .whitespaces).isEmpty) &&
        !isSaving
    }

    private var ctaLabel: String {
        if isSaving { return familyPath == .join ? "Salvataggio…" : "Creazione…" }
        return familyPath == .join ? "Continua" : "Crea la famiglia"
    }

    // MARK: - Navigation

    private func handleCTA() {
        // Si avanza solo a salvataggio riuscito: proseguire dopo un errore
        // lascerebbe l'utente convinto di aver messo il nome, e la famiglia
        // nascerebbe comunque con un membro anonimo.
        Task { await saveSetupThenAdvance() }
    }

    /// Precompila i campi da quello che già si sa dell'utente.
    ///
    /// Il profilo locale ha la precedenza; in mancanza si spezza il
    /// `displayName` di Firebase Auth, che con Google e Facebook arriva già
    /// valorizzato. Senza questo, chi entra con un social si troverebbe a
    /// riscrivere un nome che l'app conosce già. Il cognome, se c'è, propone
    /// anche il nome della famiglia («Famiglia Rossi»).
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
                prefillFamilyName()
                return
            }
        }

        let display = (user.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !display.isEmpty, display != "Utente" else { return }
        var parts = display.split(separator: " ").map(String.init)
        guard !parts.isEmpty else { return }
        profileFirstName = parts.removeFirst()
        profileLastName = parts.joined(separator: " ")
        prefillFamilyName()
    }

    private func prefillFamilyName() {
        guard familyName.isEmpty, !profileLastName.isEmpty else { return }
        familyName = String(format: NSLocalizedString("Famiglia %@", comment: "Nome famiglia proposto dal cognome"), profileLastName)
    }

    /// Se il wizard è partito da un Universal Link, mostra direttamente la
    /// conferma d'invito (`.linkJoin`).
    ///
    /// Il controllo va fatto una volta sola all'apertura: `familyPath` diventa
    /// poi lo stato di navigazione, e un secondo tocco sul link a wizard già
    /// avviato non deve resettare la pagina in cui l'utente si trova.
    @MainActor
    private func loadPendingLinkInviteIfAny(force: Bool = false) {
        // `force` serve quando il link arriva ad app già aperta: lì il percorso
        // può essere già stato scelto, e va comunque scavalcato — l'utente ha
        // appena toccato un invito, è quello che vuole fare. Non però a
        // famiglia già creata: lì il join lo farà dalla Home.
        guard force || familyPath == .create else { return }
        guard createdFamilyId == nil else { return }
        guard let invite = PendingFamilyInvite.load() else { return }
        pendingLinkInvite = invite
        familyPath = .linkJoin
        currentPage = 0
        Task {
            let preview = await InviteRemoteStore().fetchInvitePreview(
                familyId: invite.familyId,
                inviteId: invite.inviteId
            )
            await MainActor.run { linkInvitePreview = preview }
        }
    }

    /// Salva nome e cognome e, nel percorso «crea», crea la famiglia; poi
    /// passa alla pagina successiva. Nel percorso «entra» la famiglia arriva
    /// dal QR alla pagina dopo.
    @MainActor
    private func saveSetupThenAdvance() async {
        guard !isSaving, canSubmitSetup else { return }
        isSaving = true
        setupError = nil
        defer { isSaving = false }

        do {
            try await UserProfileWriter.saveNames(
                firstName: profileFirstName,
                lastName: profileLastName,
                modelContext: modelContext
            )
            AppAnalytics.onboardingStepCompleted(stepName: "name")

            if familyPath == .create {
                // Segnala a RootGateView che la famiglia sta per nascere QUI:
                // la KBFamily entra in SwiftData prima della pagina invito, e
                // senza questo flag la Home partirebbe da sola saltandola.
                // Va acceso solo adesso e non all'apertura del wizard: acceso
                // prima, bloccava anche l'ingresso in Home di chi una famiglia
                // ce l'ha già (stesso account usato su Android) e stava solo
                // aspettando che arrivasse dal server — e si ritrovava a
                // riscrivere nome e famiglia.
                coordinator.isCreatingFamilyInOnboarding = true
                let service = FamilyCreationService(remote: FamilyRemoteStore(), modelContext: modelContext)
                let created = try await service.createFamily(
                    name: familyName.trimmingCharacters(in: .whitespaces),
                    childName: "",
                    childBirthDate: nil
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

                createdFamilyId = familyId
                AppAnalytics.onboardingStepCompleted(stepName: "create_family")
                coordinator.setActiveFamily(familyId)
                // Il documento membro è appena nato: ora che la famiglia esiste
                // il nome raccolto qui sopra può arrivarci, altrimenti
                // resterebbe solo su users/{uid}.
                await UserProfileWriter.propagateDisplayNameToMember(
                    familyId: familyId,
                    modelContext: modelContext
                )
                KBLog.auth.kbInfo("Onboarding: profile saved and family created, advancing to invite")
            } else {
                KBLog.auth.kbInfo("Onboarding: profile saved, advancing to join")
            }
            AppAnalytics.onboardingStepCompleted(stepName: "setup")
            advancePage()
        } catch {
            coordinator.isCreatingFamilyInOnboarding = false
            setupError = error.localizedDescription
            KBLog.auth.kbError("Onboarding: setup failed: \(error.localizedDescription)")
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

    private func goBack() {
        guard canGoBack else { return }
        isTransitioning = true

        withAnimation(.easeIn(duration: 0.18)) {
            textOpacity = 0; textOffset = 16; iconScale = 0.85; iconOpacity = 0.3
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            currentPage -= 1
            textOffset = -28; iconScale = 0.5
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
                iconScale = 1.0; iconOpacity = 1.0; textOpacity = 1.0; textOffset = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTransitioning = false
            }
        }
    }

    /// Tocco su «Usa l'invito»: legge gli appunti (banner di sistema, una
    /// volta). Se c'è un invito, `store()` avvisa il wizard che passa da solo
    /// alla conferma; altrimenti si spiega come fare.
    private func useInviteFromPasteboard() {
        dismissKeyboard()
        if InvitePasteboardPickup.pickUp() == nil {
            pasteboardCheckFailed = true
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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

    // MARK: - Join famiglia (pagina 1, percorso .join)
    
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
// Sostituisce tutto il wizard quando parte da un Universal Link:
// mostra la famiglia (e chi ha invitato, se noti), chiede nome e cognome e fa
// il join in un solo passaggio — niente QR, niente pagina di setup.

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

// MARK: - SetupFamilyCard
//
// Pagina 0: nome e cognome dell'utente e nome della famiglia, in una
// schermata sola. Il salvataggio e la creazione li fa il parent nel CTA.
//
// Il nome sta qui, prima della famiglia, apposta: il documento membro nasce
// alla creazione/join, quindi avere già il nome permette di scriverlo lì
// subito invece di lasciare il membro anonimo agli occhi degli altri.
//
// Nel percorso «entra» (QR) il campo famiglia sparisce: il nome della
// famiglia lo porta l'invito.

private struct SetupFamilyCard: View {

    let cardBackground: Color
    let accentColor:    Color
    let iconColor:      Color

    @Binding var firstName:  String
    @Binding var lastName:   String
    @Binding var familyName: String
    let isJoin:    Bool
    let isBusy:    Bool
    let errorText: String?
    let onTogglePath: () -> Void
    /// Invio sull'ultimo campo: come premere il pulsante in fondo.
    let onSubmit: () -> Void
    /// Negli appunti c'è probabilmente un link (rilevato senza leggerlo).
    let pasteboardInvite: Bool
    /// L'utente ha provato e negli appunti non c'era un invito KidBox.
    let pasteboardInviteFailed: Bool
    let onUseInvite: () -> Void

    @FocusState private var focusedField: Field?
    private enum Field { case first, last, family }

    var body: some View {
        VStack(spacing: 22) {

            // Header
            VStack(spacing: 12) {
                ZStack {
                    Circle().fill(iconColor.opacity(0.15)).frame(width: 72, height: 72)
                    Image(systemName: isJoin ? "qrcode.viewfinder" : "house.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(LinearGradient(
                            colors: [iconColor, accentColor],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                }
                Text(isJoin ? "Entra nella tua famiglia" : "Tu e la tua famiglia")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(isJoin
                     ? "Dicci come ti chiami: al passo dopo inquadri il QR di chi ti ha invitato."
                     : "Come ti vedranno gli altri, e come si chiama la vostra famiglia. Figli e tutto il resto li aggiungi dopo.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 8)

            if pasteboardInvite && !isJoin {
                // Invito copiato da /join prima dell'installazione: un tocco
                // e si entra, senza tornare sul messaggio.
                VStack(alignment: .leading, spacing: 8) {
                    Label("Hai ricevuto un invito?", systemImage: "envelope.open.fill")
                        .font(.subheadline.weight(.semibold))
                    Text(pasteboardInviteFailed
                         ? "Negli appunti non c'è un invito KidBox. Torna sul messaggio che hai ricevuto e tocca di nuovo il link."
                         : "Sembra che tu abbia un link d'invito negli appunti: usalo per entrare nella famiglia che ti aspetta.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !pasteboardInviteFailed {
                        Button(action: onUseInvite) {
                            Text("Usa l'invito")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            // Form
            VStack(spacing: 12) {
                field(label: "Nome", icon: "person.fill", placeholder: "Es. Giulia",
                      text: $firstName, focus: .first, content: .givenName, submit: .next) {
                    focusedField = .last
                }
                field(label: "Cognome", icon: "person.fill", placeholder: "Es. Rossi",
                      text: $lastName, focus: .last, content: .familyName,
                      submit: isJoin ? .go : .next) {
                    if isJoin { focusedField = nil; onSubmit() } else { focusedField = .family }
                }
                if !isJoin {
                    field(label: "Nome famiglia", icon: "person.2.fill", placeholder: "Es. Famiglia Rossi",
                          text: $familyName, focus: .family, content: nil, submit: .go) {
                        focusedField = nil
                        onSubmit()
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            // Percorso alternativo, in fondo e discreto: chi ha un invito è
            // una minoranza, e chi ha toccato un link non passa nemmeno di qui.
            Button(action: onTogglePath) {
                Text(isJoin ? "Non hai un invito? Crea la tua famiglia" : "Hai ricevuto un invito? Entra con il QR")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
        .padding(24)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: accentColor.opacity(0.12), radius: 20, x: 0, y: 10)
        .animation(.easeInOut(duration: 0.25), value: isJoin)
        // «Fine» sopra la tastiera: la via d'uscita che si vede sempre.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fine") { focusedField = nil }
                    .font(.body.weight(.semibold))
            }
        }
    }

    @ViewBuilder
    private func field(
        label: LocalizedStringKey,
        icon: String,
        placeholder: LocalizedStringKey,
        text: Binding<String>,
        focus: Field,
        content: UITextContentType?,
        submit: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(accentColor)
                    .frame(width: 20)
                TextField(placeholder, text: text)
                    .focused($focusedField, equals: focus)
                    .textContentType(content)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .disabled(isBusy)
                    .submitLabel(submit)
                    .onSubmit(onSubmit)
            }
            .padding(14)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(focusedField == focus ? accentColor : Color.secondary.opacity(0.15), lineWidth: 1.5)
            )
        }
    }
}

// MARK: - InviteOnboardingCard
//
// Pagina 1 (percorso .create): link condivisibile come azione primaria; QR collassabile come secondaria.
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
        // Niente ScrollView proprio: scorre già il wizard che la contiene.
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
                .simultaneousGesture(TapGesture().onEnded {
                    AppAnalytics.inviteShared(channel: "system_share_sheet")
                })

                // Copia link (secondario)
                Button {
                    vm.copyToClipboard()
                    AppAnalytics.inviteShared(channel: "copy")
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
                Text("Il link contiene la chiave: vale 7 giorni, una volta sola. Mandalo solo alla persona giusta.")
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
                        Text("Valido 7 giorni").font(.caption).foregroundStyle(.secondary)
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

                Button {
                    AppAnalytics.onboardingInviteStepSkipped()
                    onFinish(false)
                } label: {
                    Text("Farlo dopo →")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            guard !didGenerate else { return }
            didGenerate = true
            AppAnalytics.onboardingInviteStepShown()
            Task { await vm.generateInviteCode() }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingWalkthroughView { print("done") }
}
