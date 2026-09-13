/**
 * Preferenze dell'account su `users/{uid}` (chat, AI, notifiche, contesto
 * Salute), con aggiornamento ottimistico e rollback come i ViewModel di iOS:
 * l'interruttore si muove subito e torna indietro solo se la scrittura
 * fallisce davvero. Condiviso dalle pagine di dettaglio delle Impostazioni.
 */
import { useEffect, useState } from "react";
import { useAuth } from "../AuthContext";
import {
  loadSettings,
  setAIEnabled,
  setChatEnabled,
  setHealthContextSendPreference,
  setNotificationPref,
} from "../services/settings";

export function useAccountSettings() {
  const { user } = useAuth();
  const [prefs, setPrefs] = useState(null);
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!user) return;
    loadSettings(user.uid).then(setPrefs).catch((err) => setError(err.message));
  }, [user]);

  const commit = async (patch, write) => {
    const previous = prefs;
    setPrefs({ ...prefs, ...patch });
    setError(null);
    setBusy(true);
    try {
      await write();
    } catch (err) {
      setPrefs(previous);
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  const toggleNotification = (key, enabled) =>
    commit({ notifications: { ...prefs.notifications, [key]: enabled } }, () =>
      setNotificationPref(user.uid, key, enabled)
    );

  const toggleChat = async (enabled) => {
    const previous = prefs;
    setPrefs({ ...prefs, chatEnabled: enabled });
    setError(null);
    setBusy(true);
    try {
      const notify = await setChatEnabled(user.uid, enabled, prefs.notifications.notifyOnNewMessages);
      setPrefs((cur) => ({
        ...cur,
        chatEnabled: enabled,
        notifications: { ...cur.notifications, notifyOnNewMessages: notify },
      }));
    } catch (err) {
      setPrefs(previous);
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  const toggleAI = (enabled) => commit({ aiEnabled: enabled }, () => setAIEnabled(user.uid, enabled));

  const setHealthContext = (option) =>
    commit({ healthContextSendPreference: option }, () => setHealthContextSendPreference(user.uid, option));

  return { prefs, error, setError, busy, setBusy, toggleNotification, toggleChat, toggleAI, setHealthContext };
}
