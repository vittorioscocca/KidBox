import { initializeApp } from "firebase/app";
import { getAuth } from "firebase/auth";
import { getFirestore } from "firebase/firestore";
import { getFunctions } from "firebase/functions";
import { getStorage } from "firebase/storage";

const firebaseConfig = {
  apiKey: "AIzaSyC7mDpJ1LadjvhhcoospAp2f0xuawCOOFk",
  authDomain: "kidbox-42cd7.firebaseapp.com",
  projectId: "kidbox-42cd7",
  storageBucket: "kidbox-42cd7.firebasestorage.app",
  messagingSenderId: "52613538008",
  appId: "1:52613538008:web:c5417674e80de0303df7ad",
  measurementId: "G-0PG65CW2VF",
};

export const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app);
export const functions = getFunctions(app, "europe-west1");
export const storage = getStorage(app);
