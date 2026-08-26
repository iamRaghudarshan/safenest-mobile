# Working offline — plan and progress

The phone is useless when the computer it talks to is asleep, and that computer
is somebody's home PC. Everything except **Gallery**, **Documents** and
**Vault** is small text-and-numbers data that has no business requiring a live
server to look at.

So: records are held on the phone, changes are made on the phone, and a **Sync**
button pushes them when the server is reachable — with a progress bar, and
nothing moving until it is pressed.

**Vault is excluded deliberately.** Its contents are decrypted *server-side* and
the key never leaves that machine. Caching passwords on the device most likely to
be lost would quietly undo the security model (see the main repo's CLAUDE.md §7).
Titles and usernames may be cached; the password never.

**Gallery and Documents are excluded** because they are large binaries and
already have their own queues (`backup.dart`, `BackupProgress`).

---

## The three rules this feature lives or dies by

1. **Replay in order, per record.** The journal is FIFO. A create-then-edit must
   never replay as edit-then-create, so when a create lands, its `local_id` is
   rewritten to the returned `server_id` in every later operation.

2. **Clear only what the server confirms — per item, never per batch.** If eight
   of ten sync and two fail, the two stay and stay retryable. `backup.dart`
   learned this already: a batch that reports "done" and clears everything loses
   the ones that did not land, and between typing and syncing that data exists in
   exactly **one** place.

3. **Never silently discard a value.** Conflicts are detected by sending the
   `updated_at` the edit was based on. If the server's is newer, the server's
   version stands, the local one is **kept for review**, and the owner is told.
   Edit-versus-delete resurrects rather than deletes. Same instinct as the
   gallery's "a photo you cannot see is worse than one filed oddly".

---

## Tasks

- [x] **1. Stop shipping 21 MB nobody can run** — the APK carries three ABIs,
      and `x86_64` (21.1 MB of 60.8 MB) is emulators and a few Chromebooks. No
      phone runs it. Independent of everything below; done first because it is
      small and measurable.
- [ ] **2. Server: make replay safe** — one `sync_ops(user_id, client_uuid,
      module, server_id)` table so a retried create returns the existing row
      instead of making a second one. One table, one migration, every module —
      rather than a `client_uuid` column on nine tables. Plus a capability the
      phone can ask about, so an older server refuses the sync instead of
      silently duplicating everything (CLAUDE.md §10's mirror image).
- [ ] **3. Local store and read cache** — `sqflite` (uses the OS's own SQLite,
      so it adds no database engine to the download), payloads encrypted with a
      key from `flutter_secure_storage`. Screens read offline. Nothing can be
      lost yet, because the server is still the only writer.
- [ ] **4. Offline creates + the Sync button** — the outbox, the progress bar,
      per-item results. The common case, and no conflicts are possible yet.
- [ ] **5. Edits and deletes + conflicts** — tombstones, the `updated_at` check,
      and the review list. The hard part, attempted only once the machinery
      above is proven.
- [ ] **6. Offer, do not act** — when the server appears and something is
      pending, a prompt says so. It never syncs by itself. A pending count that
      is hard to ignore, because unsynced data lives in one place only.
- [ ] **7. Document and release** — CLAUDE.md §10, the field-table tests, and a
      real-server verification script.

---

## Size budget

Native code is **95% of the APK** (58 of 60.8 MB). This feature adds Dart and a
thin platform wrapper, so it should cost **well under 1 MB**.

**Do not use `sqflite_sqlcipher`.** It bundles SQLCipher as *native* code, which
is charged once per ABI — roughly 5–6 MB. Android and iOS already encrypt
app-private storage, and encrypting the JSON payloads with a key from
`flutter_secure_storage` (already a dependency) costs kilobytes.

Measure every release: the arithmetic above is a prediction until an APK is
weighed.
