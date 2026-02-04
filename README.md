# KidBox
Organizzatore condiviso per genitori
KidBox è un’app Apple-first che aiuta i genitori a organizzare e condividere tutto ciò che riguarda i propri figli, riducendo dimenticanze e discussioni inutili.

Non è una chat.
Non è un gestionale.
È una box condivisa del carico mentale legato ai bambini.

⸻

Vision

Rendere visibile, condiviso e neutro tutto ciò che riguarda un figlio, così che i genitori — insieme o separati — possano collaborare senza doverne parlare continuamente.

KidBox mette il bambino al centro, non gli adulti.

⸻

Target
	•	Genitori con figli piccoli (0–6 anni)
	•	Coppie conviventi e coppie separate collaborative
	•	Famiglie che vogliono:
	•	non dimenticare le routine quotidiane
	•	dividersi i compiti senza conflitti
	•	avere una visione chiara di impegni e giorni

⸻

Core principles
	•	Child-centric: i dati riguardano il bambino, non i singoli genitori
	•	Local-first: l’app funziona anche offline
	•	Low friction: meno parole, più chiarezza
	•	Neutral tone: niente giudizi, niente punteggi
	•	Apple-native: UX e performance prima di tutto

⸻

MVP scope (v0.1)

Included
	•	Family & child setup
	•	Routine quotidiane condivise
	•	Vista “Oggi” (routine + impegni)
	•	Calendario impegni (nido, visite, corsi, compleanni)
	•	Lista cose da fare (senza data)
	•	Calendario giorni (affidamento base)
	•	Sincronizzazione tra genitori
	•	Offline support

Explicitly excluded
	•	Chat generica
	•	Messaggistica in tempo reale
	•	Funzionalità legali o di tracciamento conflitti
	•	Foto gallery
	•	Meal planner
	•	Location tracking

⸻

Architecture
	•	UI: SwiftUI
	•	State: MVVM leggero
	•	Persistence: SwiftData (local-first)
	•	Sync: Firebase Firestore (replica + sharing)
	•	Auth: Sign in with Apple

Data conflicts are handled with:
	•	Last-Write-Wins for standard entities
	•	Event-based model for routine completion


⸻

Project structure
KidBox/
├── App/
├── Features/
│   ├── Home/
│   ├── Routine/
│   ├── Calendar/
│   ├── Todo/
│   └── Settings/
├── Domain/
│   ├── Models/
│   └── UseCases/
├── Data/
│   ├── SwiftData/
│   ├── Repositories/
│   └── Sync/
├── UIComponents/
└── Support/


⸻

Roadmap
	•	M0 – Repo & project skeleton
	•	M1 – SwiftData models
	•	M2 – Auth + Family sharing
	•	M3 – Sync engine v1
	•	M4 – Home v0.1
	•	M5 – TestFlight beta

⸻

Non-goals

KidBox does not aim to:
	•	replace messaging apps
	•	manage legal custody disputes
	•	provide parenting advice
	•	gamify parental responsibilities

⸻

Status

🚧 Early development – private repo
