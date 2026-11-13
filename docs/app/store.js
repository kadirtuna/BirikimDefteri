// Firebase: Google ile giriş ve Firestore'daki kayıtlar. Her kayıt `users/{uid}/items/{tür}_{kimlik}` belgesidir
// (telefondaki CloudSync ile aynı biçim). Web, belgeleri canlı dinler; yazarken `updatedAt` (ms) ve sunucu zamanı yazar.

import { initializeApp } from 'https://www.gstatic.com/firebasejs/10.14.1/firebase-app.js';
import { GoogleAuthProvider, getAuth, onAuthStateChanged, signInWithPopup, signOut } from 'https://www.gstatic.com/firebasejs/10.14.1/firebase-auth.js';
import {
  collection, doc, initializeFirestore, onSnapshot, persistentLocalCache, persistentMultipleTabManager, serverTimestamp, writeBatch,
} from 'https://www.gstatic.com/firebasejs/10.14.1/firebase-firestore.js';
import { firebaseConfig } from './config.js';

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = initializeFirestore(app, { localCache: persistentLocalCache({ tabManager: persistentMultipleTabManager() }) });

let unsubscribe = null;
let uid = null;
/// id → { type, data, updatedAt }; silinmiş belgeler tutulmaz.
const items = new Map();

export const store = {
  user: null,
  /// Değişiklikte çağrılır: (records, meta) — records [{type, data}], meta { fromCache, pending }.
  onChange: () => {},
  onError: () => {},

  start(onUser) {
    onAuthStateChanged(auth, (user) => {
      unsubscribe?.();
      items.clear();
      store.user = user;
      uid = user?.uid ?? null;
      onUser(user);
      if (!user) return;
      unsubscribe = onSnapshot(collection(db, 'users', user.uid, 'items'), { includeMetadataChanges: true }, (snapshot) => {
        for (const change of snapshot.docChanges()) {
          const value = change.doc.data();
          if (change.type === 'removed' || value.deleted || !value.data) {
            items.delete(change.doc.id);
            continue;
          }
          try {
            items.set(change.doc.id, { type: value.type, data: JSON.parse(value.data), updatedAt: value.updatedAt });
          } catch {
            // Bozuk belge atlanır.
          }
        }
        store.onChange([...items.values()], { fromCache: snapshot.metadata.fromCache, pending: snapshot.metadata.hasPendingWrites });
      }, (error) => {
        store.onError(error.code === 'permission-denied'
          ? 'Bu Google hesabının verilere erişim izni yok.'
          : `Bulut hatası: ${error.message}`);
      });
    });
  },

  signIn: () => signInWithPopup(auth, new GoogleAuthProvider().setCustomParameters({ prompt: 'select_account' })),
  signOut: () => signOut(auth),

  /// Yazımlar tek seferde uygulanır: [{ type, id, data }] — data null ise silme işareti.
  async commit(writes) {
    if (!uid || !writes.length) return;
    const updatedAt = Date.now();
    for (let i = 0; i < writes.length; i += 400) {
      const batch = writeBatch(db);
      for (const w of writes.slice(i, i + 400)) {
        batch.set(doc(db, 'users', uid, 'items', `${w.type}_${w.id}`), {
          type: w.type,
          data: w.data == null ? '' : JSON.stringify(w.data),
          updatedAt,
          deleted: w.data == null,
          serverTime: serverTimestamp(),
        });
      }
      await batch.commit();
    }
  },
};
