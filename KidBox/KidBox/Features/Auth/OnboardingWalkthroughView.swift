//
//  OnboardingWalkthroughView.swift
//  KidBox
//
//  Walkthrough di benvenuto: 5 schermate animate.
//
//  Pagina 0 — Benvenuto
//  Pagina 1 — Foto condivise
//  Pagina 2 — Salute e spese
//  Pagina 3 — Crea famiglia (nome + primo figlio) → chiama FamilyCreationService
//  Pagina 4 — Invita partner (QR generato da InviteCodeViewModel)
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
            subtitle:    "Visite mediche, vaccini, spese di famiglia e lista della spesa. Tutto aggiornato tra voi due."
        )
    ]
    
    // Pagine totali: 0-2 info, 3 crea famiglia, 4 invita partner
    private let totalPages = 5
    
    // MARK: State
    
    @State private var currentPage     = 0
    @State private var iconScale:      CGFloat = 0.4
    @State private var iconOpacity:    Double  = 0
    @State private var textOpacity:    Double  = 0
    @State private var textOffset:     CGFloat = 24
    @State private var bgOpacity:      Double  = 0
    @State private var ctaScale:       CGFloat = 0.92
    @State private var isTransitioning = false
    
    // Famiglia creata nella pagina 3, usata dalla pagina 4
    @State private var createdFamilyId: String? = nil
    
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
    
    private var isInfoPage:    Bool { currentPage < 3 }
    private var isCreatePage:  Bool { currentPage == 3 }
    private var isInvitePage:  Bool { currentPage == 4 }
    private var isLastPage:    Bool { currentPage == totalPages - 1 }
    
    private var infoPage: OnboardingPage { infoPages[min(currentPage, infoPages.count - 1)] }
    
    private var currentAccent: Color {
        switch currentPage {
        case 0: return Color(red: 0.95, green: 0.38, blue: 0.10)
        case 1: return Color(red: 0.50, green: 0.35, blue: 0.80)
        case 2: return Color(red: 0.20, green: 0.55, blue: 0.38)
        case 3: return Color(red: 0.95, green: 0.38, blue: 0.10)
        default: return Color(red: 0.95, green: 0.38, blue: 0.10)
        }
    }
    private var currentIconColor: Color {
        switch currentPage {
        case 0: return Color(red: 1.00, green: 0.75, blue: 0.25)
        case 1: return Color(red: 0.60, green: 0.45, blue: 0.85)
        case 2: return Color(red: 0.30, green: 0.65, blue: 0.45)
        case 3: return Color(red: 1.00, green: 0.75, blue: 0.25)
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
                    if isCreatePage {
                        CreateFamilyCard(
                            cardBackground: cardBackground,
                            accentColor:    currentAccent,
                            iconColor:      currentIconColor,
                            modelContext:   modelContext,
                            onFamilyCreated: { familyId in
                                createdFamilyId = familyId
                                coordinator.setActiveFamily(familyId)
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
                            modelContext:   modelContext
                        )
                        .padding(.horizontal, 24)
                        .opacity(textOpacity)
                        .offset(y: textOffset)
                        
                    } else {
                        // Pagine info 0-2
                        iconCard
                            .scaleEffect(iconScale)
                            .opacity(iconOpacity)
                        
                        Spacer().frame(height: 48)
                        
                        textBlock
                            .opacity(textOpacity)
                            .offset(y: textOffset)
                    }
                }
                
                Spacer()
                
                pageIndicators
                    .padding(.bottom, 32)
                
                ctaButton
                    .scaleEffect(ctaScale)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 52)
            }
        }
        .onAppear { animateIn() }
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
    
    private var ctaButton: some View {
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
                LinearGradient(colors: [currentIconColor, currentAccent],
                               startPoint: .leading, endPoint: .trailing),
                in: Capsule()
            )
            .shadow(color: currentAccent.opacity(0.4), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
    }
    
    private var ctaLabel: String {
        switch currentPage {
        case 3: return createdFamilyId != nil ? "Continua" : "Continua"
        case 4: return "Inizia"
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
        } else {
            advancePage()
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
}

// MARK: - CreateFamilyCard
//
// Schermata 4: nome famiglia + nome primo figlio.
// Chiama FamilyCreationService e salva il familyId nel parent via onFamilyCreated.

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
    
    private var canCreate: Bool {
        !familyName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !childName.trimmingCharacters(in: .whitespaces).isEmpty &&
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
                    Text("Primo figlio")
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
        guard !name.isEmpty, !child.isEmpty else { return }
        
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
            
            withAnimation { didCreate = true }
            onFamilyCreated(familyId)
            
        } catch {
            errorText = "Errore: \(error.localizedDescription)"
        }
    }
}

// MARK: - InviteOnboardingCard
//
// Schermata 5: QR generato da InviteCodeViewModel (riusa il VM esistente).
// ShareLink per WhatsApp / AirDrop / SMS + copia codice testuale.

private struct InviteOnboardingCard: View {
    
    let cardBackground: Color
    let accentColor:    Color
    let iconColor:      Color
    let modelContext:   ModelContext
    
    @StateObject private var vm: InviteCodeViewModel
    @State private var didGenerate = false
    @State private var didCopy     = false
    
    init(cardBackground: Color, accentColor: Color, iconColor: Color, modelContext: ModelContext) {
        self.cardBackground = cardBackground
        self.accentColor    = accentColor
        self.iconColor      = iconColor
        self.modelContext   = modelContext
        _vm = StateObject(wrappedValue: InviteCodeViewModel(
            remote: InviteRemoteStore(),
            modelContext: modelContext
        ))
    }
    
    var body: some View {
        VStack(spacing: 24) {
            
            // Header
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
                Text("Aggiungi il tuo partner")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("Fallo scansionare al tuo partner per unirsi alla famiglia — riceverà tutto automaticamente.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 8)
            
            // QR card
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(cardBackground)
                    .shadow(color: accentColor.opacity(0.12), radius: 20, x: 0, y: 8)
                
                Group {
                    if vm.isBusy {
                        VStack(spacing: 12) {
                            ProgressView().scaleEffect(1.3).tint(accentColor)
                            Text("Generazione QR…").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(height: 180)
                        
                    } else if let qrPayload = vm.qrPayload {
                        VStack(spacing: 12) {
                            QRCodeView(payload: qrPayload)
                                .frame(width: 156, height: 156)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text("Valido 24 ore").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(20)
                        
                    } else if let err = vm.errorMessage {
                        VStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2).foregroundStyle(.orange)
                            Text(err).font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Riprova") { Task { await vm.generateInviteCode() } }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(accentColor)
                        }
                        .padding(24)
                        
                    } else {
                        Color.clear.frame(height: 180)
                    }
                }
            }
            
            // Azioni
            if vm.qrPayload != nil {
                HStack(spacing: 12) {
                    ShareLink(item: vm.shareText) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .semibold))
                            Text("Condividi").font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(accentColor)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(accentColor.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    
                    Button {
                        vm.copyToClipboard()
                        withAnimation { didCopy = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { didCopy = false }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 15, weight: .semibold))
                            Text(didCopy ? "Copiato!" : "Copia codice")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(didCopy ? .green : .secondary)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Color.secondary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Text("Puoi farlo anche dopo da Impostazioni → Invita partner")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
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
