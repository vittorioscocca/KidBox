import { createContext, useContext } from "react";

/**
 * Apre l'assistente unico dal punto in cui si è. Lo fornisce il `Layout`, che
 * possiede il pannello; le sezioni con un pulsante AI proprio (Salute, visite,
 * esami) lo chiamano con un focus `{ personId, personName, scope, itemId,
 * detail }`, il pulsante flottante generico senza.
 */
export const AssistantContext = createContext({ openAssistant: () => {} });

export const useAssistant = () => useContext(AssistantContext);
