//
//  KBCrashHandler.swift
//  KidBox
//

import Darwin
import Foundation

// Handler C-compatibili (nessuna capture) — richiesto da NSSetUncaughtExceptionHandler / signal().

private var kbPreviousUncaughtExceptionHandler: NSUncaughtExceptionHandler?

private func kbUncaughtExceptionHandler(_ exception: NSException) {
    CrashAnalyzer.markPendingCrashReport()
    KBLog.app.kbCrash(
        "Uncaught exception: \(exception.name.rawValue) — \(exception.reason ?? "") | \(KBDeviceInfo.deviceDescription) | \(KBDeviceInfo.osVersionDescription)"
    )
    KBFileLogger.shared.flush()
    kbPreviousUncaughtExceptionHandler?(exception)
}

private func kbSignalHandler(_ signum: Int32) {
    CrashAnalyzer.markPendingCrashReport()
    let name = KBCrashHandler.signalName(for: signum)
    KBFileLogger.shared.appendSync(
        "[CRASH] [app] \(name) — processo terminato | \(KBDeviceInfo.deviceDescription) | \(KBDeviceInfo.osVersionDescription)"
    )
    signal(signum, SIG_DFL)
    raise(signum)
}

/// Intercetta eccezioni ObjC non gestite e segnali (fatalError, SIGSEGV, …) e scrive su file in modo sincrono.
enum KBCrashHandler {

    private static let crashSignals: [Int32] = [SIGABRT, SIGSEGV, SIGILL, SIGBUS, SIGFPE]

    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true

        KBFileLogger.shared.warmUpForCrashLogging()
        installUncaughtExceptionHandler()
        installSignalHandlers()
    }

    // MARK: - NSException (crash ObjC / alcuni bridge)

    private static func installUncaughtExceptionHandler() {
        kbPreviousUncaughtExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler(kbUncaughtExceptionHandler)
    }

    // MARK: - Segnali (fatalError → SIGABRT, memory fault, …)

    private static func installSignalHandlers() {
        for signum in crashSignals {
            signal(signum, kbSignalHandler)
        }
    }

    fileprivate static func signalName(for signum: Int32) -> String {
        switch signum {
        case SIGABRT: return "SIGABRT/fatalError"
        case SIGSEGV: return "SIGSEGV"
        case SIGILL: return "SIGILL"
        case SIGBUS: return "SIGBUS"
        case SIGFPE: return "SIGFPE"
        default: return "SIGNAL-\(signum)"
        }
    }
}
