//
//  firebase.js
//  Retainic Web
//
//  Initializes the Firebase Web SDK against the SAME project the iOS app uses
//  (retainic-85b91), so accounts and data are shared across iOS and the web.
//
//  The config is derived from the iOS GoogleService-Info.plist. `appId` is the
//  iOS app id; Auth / Firestore / Storage work fine with it. If you register a
//  dedicated Web App in the Firebase console you can paste its appId here.
//

import { initializeApp } from "https://www.gstatic.com/firebasejs/11.0.2/firebase-app.js";
import { getAuth } from "https://www.gstatic.com/firebasejs/11.0.2/firebase-auth.js";
import { getFirestore } from "https://www.gstatic.com/firebasejs/11.0.2/firebase-firestore.js";
import { getStorage } from "https://www.gstatic.com/firebasejs/11.0.2/firebase-storage.js";

const firebaseConfig = {
  apiKey: "AIzaSyBvct2kc9VnDDfMNTouFz2KxNhfJx0aGsw",
  authDomain: "retainic-85b91.firebaseapp.com",
  projectId: "retainic-85b91",
  storageBucket: "retainic-85b91.firebasestorage.app",
  messagingSenderId: "497362298362",
  appId: "1:497362298362:ios:957f8dea035c6fb1ca3043",
};

const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app);
export const storage = getStorage(app);
