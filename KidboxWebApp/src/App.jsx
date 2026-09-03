import { useEffect, useState } from "react";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { AuthProvider, useAuth } from "./AuthContext";
import { FamilyProvider } from "./FamilyContext";
import { LocaleProvider } from "./i18n/LocaleContext";
import { ThemeProvider } from "./ThemeContext";
import Layout from "./components/Layout";
import Home from "./pages/Home";
import TodoPage from "./pages/TodoPage";
import Calendario from "./pages/Calendario";
import Note from "./pages/Note";
import Documenti from "./pages/Documenti";
import Spesa from "./pages/Spesa";
import Foto from "./pages/Foto";
import Spese from "./pages/Spese";
import Posizione from "./pages/Posizione";
import Password from "./pages/Password";
import Wallet from "./pages/Wallet";
import Animali from "./pages/Animali";
import Casa from "./pages/Casa";
import Garage from "./pages/Garage";
import Viaggi from "./pages/Viaggi";
import Assistente from "./pages/Assistente";
import Profilo from "./pages/Profilo";
import Impostazioni from "./pages/Impostazioni";
import Famiglia from "./pages/Famiglia";
import Chat from "./pages/Chat";
import Placeholder from "./pages/Placeholder";
import { listenForegroundPush } from "./services/push";
import { NAV_SECTIONS, ACCOUNT_SECTIONS } from "./nav";
import "./App.css";

function GoogleIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none">
      <path fill="#4285F4" d="M23.5 12.27c0-.82-.07-1.6-.2-2.36H12v4.47h6.47a5.53 5.53 0 0 1-2.4 3.63v3h3.87c2.27-2.09 3.56-5.17 3.56-8.74Z" />
      <path fill="#34A853" d="M12 24c3.24 0 5.96-1.07 7.94-2.9l-3.87-3c-1.08.72-2.45 1.15-4.07 1.15-3.13 0-5.78-2.11-6.73-4.96H1.28v3.1A12 12 0 0 0 12 24Z" />
      <path fill="#FBBC05" d="M5.27 14.29a7.2 7.2 0 0 1 0-4.58v-3.1H1.28a12 12 0 0 0 0 10.78l3.99-3.1Z" />
      <path fill="#EA4335" d="M12 4.75c1.77 0 3.35.61 4.6 1.8l3.42-3.42C17.95 1.19 15.24 0 12 0A12 12 0 0 0 1.28 6.61l3.99 3.1C6.22 6.86 8.87 4.75 12 4.75Z" />
    </svg>
  );
}

function AppleIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor">
      <path d="M16.5 1c.1 1.1-.32 2.16-1 2.94-.7.8-1.85 1.4-2.9 1.32-.13-1.06.36-2.16 1-2.87.72-.82 1.98-1.42 2.9-1.39ZM20.6 17.1c-.36.84-.53 1.2-.99 1.94-.65 1.05-1.56 2.35-2.7 2.36-1 .01-1.26-.66-2.62-.65-1.36 0-1.65.66-2.65.67-1.14.01-2-1.17-2.65-2.22-1.82-2.9-2-6.3-.88-8.1.79-1.28 2.05-2.03 3.24-2.03 1.2 0 1.96.68 2.96.68.97 0 1.55-.68 2.94-.68 1.06 0 2.18.58 2.98 1.58-2.62 1.44-2.2 5.18.37 6.45Z" />
    </svg>
  );
}

function FacebookIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="#1877F2">
      <path d="M24 12.07C24 5.7 18.63.5 12 .5S0 5.7 0 12.07c0 5.75 4.39 10.52 10.13 11.36v-8.04H7.08v-3.32h3.05V9.41c0-3.02 1.8-4.7 4.55-4.7 1.32 0 2.7.24 2.7.24v2.97h-1.52c-1.5 0-1.97.94-1.97 1.9v2.28h3.34l-.53 3.32h-2.81v8.04C19.61 22.6 24 17.82 24 12.07Z" />
    </svg>
  );
}

function EmailIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <rect x="2" y="4" width="20" height="16" rx="3" />
      <path d="m3 7 9 6 9-6" />
    </svg>
  );
}

function LoginScreen() {
  const { signInWithGoogle, signInWithApple, signInWithFacebook, signInWithEmail, signUpWithEmail } = useAuth();
  const [showEmailForm, setShowEmailForm] = useState(false);
  const [isSignUp, setIsSignUp] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState(null);
  const [pending, setPending] = useState(false);

  const runProvider = async (fn) => {
    setError(null);
    setPending(true);
    try {
      await fn();
    } catch (err) {
      setError(err.message);
    } finally {
      setPending(false);
    }
  };

  const handleEmailSubmit = (e) => {
    e.preventDefault();
    runProvider(() => (isSignUp ? signUpWithEmail(email, password) : signInWithEmail(email, password)));
  };

  return (
    <div className="login-screen">
      <img className="logo" src="/icon.png" alt="KidBox" />
      <h1>KidBox</h1>
      <p className="subtitle">Accedi per organizzare la tua famiglia</p>

      {error && <p className="error">{error}</p>}

      <div className="providers">
        <button className="auth-btn" disabled={pending} onClick={() => runProvider(signInWithGoogle)}>
          <GoogleIcon /> Accedi con Google
        </button>
        <button className="auth-btn" disabled={pending} onClick={() => runProvider(signInWithApple)}>
          <AppleIcon /> Accedi con Apple
        </button>
        <button className="auth-btn" disabled={pending} onClick={() => runProvider(signInWithFacebook)}>
          <FacebookIcon /> Accedi con Facebook
        </button>

        {!showEmailForm && (
          <button className="auth-btn secondary" onClick={() => setShowEmailForm(true)}>
            <EmailIcon /> Accedi con email
          </button>
        )}
      </div>

      {showEmailForm && (
        <>
          <div className="divider">email</div>
          <form className="email-form" onSubmit={handleEmailSubmit}>
            <input
              type="email"
              placeholder="Email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
            <input
              type="password"
              placeholder="Password"
              required
              minLength={6}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
            <button className="auth-btn" type="submit" disabled={pending}>
              {isSignUp ? "Crea account" : "Accedi"}
            </button>
            <button
              type="button"
              className="toggle-mode"
              onClick={() => setIsSignUp((v) => !v)}
            >
              {isSignUp ? "Hai già un account? Accedi" : "Non hai un account? Registrati"}
            </button>
          </form>
        </>
      )}
    </div>
  );
}

function AuthedApp() {
  // A scheda aperta il browser non mostra niente da solo: il messaggio arriva
  // all'app, che decide se trasformarlo in un avviso di sistema.
  useEffect(() => {
    listenForegroundPush();
  }, []);

  return (
    <FamilyProvider>
      <BrowserRouter>
        <Routes>
          <Route element={<Layout />}>
            <Route path="/" element={<Home />} />
            <Route path="/calendario" element={<Calendario />} />
            <Route path="/note" element={<Note />} />
            <Route path="/documenti" element={<Documenti />} />
            <Route path="/spesa" element={<Spesa />} />
            <Route path="/foto" element={<Foto />} />
            <Route path="/spese" element={<Spese />} />
            <Route path="/posizione" element={<Posizione />} />
            <Route path="/password" element={<Password />} />
            <Route path="/wallet" element={<Wallet />} />
            <Route path="/animali" element={<Animali />} />
            <Route path="/casa" element={<Casa />} />
            <Route path="/garage" element={<Garage />} />
            <Route path="/viaggi" element={<Viaggi />} />
            <Route path="/assistente" element={<Assistente />} />
            <Route path="/account/profilo" element={<Profilo />} />
            <Route path="/account/impostazioni" element={<Impostazioni />} />
            <Route path="/account/family" element={<Famiglia />} />
            <Route path="/chat" element={<Chat />} />
            <Route path="/todo" element={<TodoPage />} />
            {NAV_SECTIONS.filter((s) => !s.exact && s.path !== "/calendario" && s.path !== "/todo" && s.path !== "/note" && s.path !== "/documenti" && s.path !== "/spesa" && s.path !== "/foto" && s.path !== "/spese" && s.path !== "/posizione" && s.path !== "/password" && s.path !== "/wallet" && s.path !== "/animali" && s.path !== "/casa" && s.path !== "/garage" && s.path !== "/viaggi" && s.path !== "/assistente" && s.path !== "/chat").map((s) => (
              <Route key={s.key} path={s.path} element={<Placeholder title={s.label} />} />
            ))}
            {ACCOUNT_SECTIONS.filter((s) => s.path !== "/account/profilo" && s.path !== "/account/impostazioni" && s.path !== "/account/family").map((s) => (
              <Route key={s.key} path={s.path} element={<Placeholder title={s.label} />} />
            ))}
          </Route>
        </Routes>
      </BrowserRouter>
    </FamilyProvider>
  );
}

function AppShell() {
  const { user } = useAuth();
  if (user === undefined) return <p className="loading">Caricamento...</p>;
  return user ? <AuthedApp /> : <LoginScreen />;
}

export default function App() {
  return (
    <LocaleProvider>
      <ThemeProvider>
        <AuthProvider>
          <AppShell />
        </AuthProvider>
      </ThemeProvider>
    </LocaleProvider>
  );
}
