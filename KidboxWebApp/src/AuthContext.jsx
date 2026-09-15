import { createContext, useContext, useEffect, useState } from "react";
import { setInternalTraffic } from "./services/analytics";
import {
  onAuthStateChanged,
  signInWithPopup,
  signOut,
  GoogleAuthProvider,
  OAuthProvider,
  FacebookAuthProvider,
  signInWithEmailAndPassword,
  createUserWithEmailAndPassword,
  sendEmailVerification,
  sendPasswordResetEmail,
} from "firebase/auth";
import { auth } from "./firebase";

const AuthContext = createContext(null);

const isPasswordUnverified = (u) =>
  u.providerData.some((p) => p.providerId === "password") && !u.emailVerified;

/** Stesso `code` di Firebase così `friendlyError` lo traduce come gli altri. */
export class EmailNotVerifiedError extends Error {
  constructor() {
    super("Email address not verified.");
    this.code = "kidbox/email-not-verified";
  }
}

export function AuthProvider({ children }) {
  const [user, setUser] = useState(undefined); // undefined = loading, null = signed out

  /**
   * Senza email verificata non si entra, nemmeno con la sessione ripristinata
   * all'apertura: gemello di `AppCoordinator.startSessionListener` su iOS.
   * Al 13/09/2026 i 10 account email non verificati non erano mai tornati
   * dopo il giorno di registrazione, quindi qui non si espelle nessuno.
   */
  useEffect(
    () =>
      onAuthStateChanged(auth, (u) => {
        if (u && isPasswordUnverified(u)) {
          signOut(auth);
          return;
        }
        setInternalTraffic(u);
        setUser(u);
      }),
    []
  );

  const signInWithGoogle = () => signInWithPopup(auth, new GoogleAuthProvider());

  const signInWithApple = () => {
    const provider = new OAuthProvider("apple.com");
    provider.addScope("email");
    provider.addScope("name");
    return signInWithPopup(auth, provider);
  };

  const signInWithFacebook = () => signInWithPopup(auth, new FacebookAuthProvider());

  const signInWithEmail = async (email, password) => {
    const result = await signInWithEmailAndPassword(auth, email, password);
    if (isPasswordUnverified(result.user)) {
      // Reinvio best effort: Firebase lo rifiuta se il link è appena partito,
      // e non deve coprire il motivo vero del rifiuto.
      await sendEmailVerification(result.user).catch(() => {});
      await signOut(auth);
      throw new EmailNotVerifiedError();
    }
    return result;
  };

  /**
   * Come `LoginViewModel.registerEmail` su iOS: si crea l'account, si manda il
   * link di verifica e si esce subito. L'utente entra al login successivo.
   */
  const signUpWithEmail = async (email, password) => {
    const result = await createUserWithEmailAndPassword(auth, email, password);
    await sendEmailVerification(result.user);
    await signOut(auth);
  };

  const resetPassword = (email) => sendPasswordResetEmail(auth, email);

  const logout = () => signOut(auth);

  return (
    <AuthContext.Provider
      value={{
        user,
        signInWithGoogle,
        signInWithApple,
        signInWithFacebook,
        signInWithEmail,
        signUpWithEmail,
        resetPassword,
        logout,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}
