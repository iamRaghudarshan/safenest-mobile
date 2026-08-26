# SafeNest for phones — project guide

The Flutter companion to **SafeNest**, the private personal-finance and
life-records app. Read this before changing anything here.

**The server is a separate repository and has its own, much longer guide:**
`D:\AI PRO\finmate-react\CLAUDE.md`. Read that too — most of what constrains
this app is decided there, especially §1 (records never leave the customer's
machine), §7 (security model) and §8 (licensing). Nothing in this app may
contradict them.

---

## 1. Why a native app exists at all

A web page cannot read an iPhone's photo library. The file picker is the only
door, and above roughly a hundred photos iOS stops closing it. That was measured
on a real phone, in a Safari tab and in the Home-Screen copy alike, with local
photos and no format conversion involved. No web API raises that ceiling and none
can cap what the picker offers.

So "back up my gallery" could not be built out of a file input however it was
dressed up. Everything in `backup.dart` is what real library access buys:
nothing is selected, `PhotoManager` enumerates directly, and the run is resumable
by construction.

**That is the app's reason to exist. If a change makes the backup worse, it is
the wrong change however good it looks elsewhere.**

---

## 2. Stack

| Part | What |
|---|---|
| Framework | Flutter, Dart SDK `^3.12.2` |
| Flutter on this machine | `D:\flutter\bin\flutter.bat` (3.44.8) |
| State | `provider` — `Session` is the root |
| Secrets | `flutter_secure_storage` — Keychain / Keystore |
| Library access | `photo_manager` |
| Push | `firebase_messaging` + `flutter_local_notifications` |
| Hashing | `crypto` (sha256, for the backup's pre-flight check) |

There is no local database. The server is the only store; this app is a client.

---

## 3. Layout

```
safenest-mobile/
├── VERSION                 the release number — CI reads it, do not skip it
├── firebase.env            the six Firebase identifiers (see §7). TRACKED, not secret
├── lib/
│   ├── main.dart           app root, providers, routing
│   ├── session.dart        who is signed in, and to WHICH SafeNest
│   ├── api.dart            fetch wrapper, JWT, typed ApiError, licence-block hook
│   ├── backup.dart         THE POINT OF THE APP — read §4 before touching
│   ├── push.dart           FCM registration
│   ├── alarms.dart         on-device reminder alarms
│   ├── discover.dart       find the computer on the wifi
│   ├── dates.dart          dd-mm-yyyy and 12-hour AM/PM, everywhere
│   ├── masters.dart        the user's category/bank lists, cached per session
│   ├── screens/            one file per screen
│   └── widgets/
├── test/                   widget + regression tests. `flutter test` is a CI gate
├── ios/Runner/             Info.plist, and Runner.entitlements once §7 lands
└── .github/workflows/release.yml
```

---

## 4. `backup.dart` — the part that must not regress

Read the comments in the file; they record real failures. The shape:

1. `PhotoManager` enumerates the whole library (`RequestType.common` — photos
   **and** videos; it was images-only once and silently skipped every clip).
2. Pages of 200. Asking for 40,000 asset objects at once gets the app killed.
3. Skip anything already in `_sent` (the phone's own list).
4. **Ask the server what it already holds** — `POST /api/gallery/have`, matched
   on sha256 of the file as the device holds it. See §5.
5. Upload what remains, four at a time. Four was measured at 7.81 photos/sec
   against a server ceiling of 8.50; eight was *slower*.

### Things that were wrong here and must stay fixed

- **`_Sent` is a three-way enum**, not a bool. `stored` / `already` / `failed`.
  "The upload succeeded and nothing new exists on the server" is a real outcome
  and a bool cannot say it.
- **`report()` is called in three places**, not one. It used to be called only
  inside the upload loop, so a page where everything was skipped emitted nothing
  — the bar sat at 0% through the whole library and jumped to 100% at the end.
  That is precisely the run people do most: the second one.
- **`_problems` is a map keyed by cause**, not one overwritten string. A run
  where forty photos were stuck in iCloud and three hit an expired session used
  to report whichever happened last. One cause is a thing you fix.
- **`forgetSent()` is the only way back** from a deletion on the computer. The
  `_sent` list says "already backed up" and the server knowing nothing about a
  photo does not change it, so photos removed at the computer would be skipped
  for ever while sitting on the phone the whole time.
- **The headline count is what was UPLOADED**, not the size of the library.
  `68 of 1048` was arithmetically exact and read as "uploading all 1048 again";
  it was reported as a bug twice. The library figure explains itself on the
  second line.
- **Hashing is streamed** (`sha256.bind(f.openRead())`), never `readAsBytes`. A
  4K video is hundreds of megabytes.

---

## 5. The pre-flight check — `POST /api/gallery/have`

The phone's `_sent` list is local. A reinstall, cleared app data, or
`forgetSent()` leaves it empty, and the phone must then assume it has sent
nothing — so it uploaded 1,048 photos over a home connection for the server to
recognise nearly all of them and store none. Reported honestly as "already
there", which is why it looked like working software doing pointless work.

It asks first now. Up to 1000 hashes per call; the answer is which ones this
account holds.

**Matched on `source_hash`, not `content_hash`.** The server's `content_hash` is
taken after re-encoding and stripping metadata — deliberately, so a photo and
its shared copy collide — and a phone cannot reproduce that without doing the
same decode. `source_hash` is the hash of the bytes as the device holds them.

**Failure returns empty and never throws.** A backup must still work against a
server too old to answer, or one having a bad moment. It degrades to the old
behaviour: slower, never wrong.

---

## 6. Which SafeNest — the address is never assumed

Every customer runs their own copy on their own machine. **There is no default
address and no fallback.** A hard-coded one was a real bug in the desktop
product, where every customer's screen advertised the publisher's own domain as
though it were theirs.

- `session.dart::normaliseAddress()` accepts what a person types. **http is
  allowed only for a private address** — over the internet it would send the
  password in the clear; on a home network, insisting on https would make the
  app unusable for someone who has not set up a domain, which is most people on
  the day they install it.
- **`/api/health` is checked before a password is sent**, and `service` must
  equal `finmate-api`. A domain resolving to somebody else's site answers 200
  perfectly happily.
- `changeAddress()` **tests the existing token** against the new address rather
  than assuming. One computer usually has two addresses — a home IP and a domain
  — and which works depends on where the phone is. Changing between them must
  not throw away a good session.
- `discover.dart` finds the computer on the wifi so the first sign-in does not
  require typing an IP.

---

## 7. Push — the state of it, honestly

**Server-side complete. On iPhone it has never once worked, and the reason is
in this repository.**

There was no entitlements file in the iOS project at all — `aps-environment`
appeared nowhere, in any configuration. iOS issues an APNs device token only to
an app carrying that entitlement, and Firebase's `getToken()` is a wrapper
around that token. No APNs token, no FCM token, nothing to send to.

Everything downstream was already correct, which is why it took three releases
to find: `firebase.env` carries all six identifiers and reaches both builds via
`--dart-define-from-file`; the service account on the server is configured;
permission was granted on the phone. And `push_subscriptions` held two rows,
both `kind='web'` from Safari, from July. Not one token from the phone app.

Nothing logged a fault because nothing had faulted — the app asked a system that
had no token to give, and every layer above reported success at doing nothing.

**The fix is on the branch `push-entitlement`, deliberately not on main.**
Signing is manual against the profile "SafeNest AppStore", and an entitlement
the profile does not contain fails the build outright:

    Provisioning profile "SafeNest AppStore" doesn't include the
    aps-environment entitlement.

### Merging it needs these, in order, and only the owner can do them

1. Apple Developer → Identifiers → `safenest.raghudarshan.online` → enable
   **Push Notifications**.
2. Profiles → **SafeNest AppStore** → regenerate → download → update the GitHub
   secret **`IOS_PROFILE_BASE64`**.
3. Apple Developer → Keys → create an **APNs auth key** (`.p8`, downloads once).
4. Firebase → project `safenest-dd21f` → Cloud Messaging → upload the `.p8` with
   its Key ID and Team ID **P57Y6ND67Y**. Without this Firebase cannot reach
   Apple at all.

Then merge, bump `VERSION`, tag, and **send a real push and watch it arrive** —
this is the exact feature that has looked done three times.

### `firebase.env` is tracked on purpose

Google publishes these identifiers inside every shipped APK; they are not
secrets. The key that authorises *sending* is a service account on the owner's
own server and is not in this repository. The file says so at the top.

`push.dart` picks `_appId` / `_apiKey` by platform — iOS and Android have
different values, and using Android's on an iPhone fails at `initializeApp` with
a message that reads like a bug in this app.

---

## 8. Releasing

```
1. edit VERSION  AND  pubspec.yaml   e.g. VERSION=1.51.0, pubspec version: 1.51.0+1
2. commit, push
3. git tag v1.51.0 && git push origin v1.51.0        (iOS -> TestFlight)
   git tag android-1.51.0 && git push origin android-1.51.0   (Android APK)
4. fetch the APK to the server: releases/SafeNest-android.apk
```

**THE ONE THAT KEEPS BITING: the store version comes from `$(cat VERSION)`, NOT
pubspec and NOT the tag.** Bumping pubspec alone (or only tagging) ships the newest
CODE but labelled with the OLD `VERSION`. It happened at 1.17.0, and again 23 Aug
2026: pubspec went 1.45->1.50 while VERSION stayed 1.38.0, so six TestFlight builds
all read "1.38.0". Always bump `VERSION` and `pubspec` together, to the same
number as the tag. See [[release-by-pushing-a-tag]].

The tag is what builds. `.github/workflows/release.yml`:

- **`v*` tags** → iOS build, signed, uploaded to TestFlight via `altool`.
- **`android-*` tags** → APK only.
- `flutter analyze` and `flutter test` **gate** the build. A build that ships
  with a known error is worse than one that never ships.
- The version comes from `$(cat VERSION)`, the build number from
  `github.run_number`.

`GITHUB_TOKEN` in the server's `backend/.env` is deliberately **Actions
read-only** — it cannot dispatch workflows, and must not be widened. Releases
happen by pushing a tag.

### Known release facts

- **Latest shipped: 1.52.1** (25 Aug 2026) — iOS on TestFlight, Android APK on
  the website. It fixes the faces strip and album uploads from the phone; both
  are written up in §10. 1.52.0 shipped with both defects and is superseded.
- Apple error **1064 "holiday"** on upload means Apple maintenance, not a
  revoked password. Check their status feed before touching credentials.
- **Minimum iOS is 13.0.** From Spring 2027 Apple requires 15.0. A warning
  today, a hard block later.

---

## 9. Verifying a change

```bash
D:/flutter/bin/flutter.bat analyze     # must be "No issues found!"
D:/flutter/bin/flutter.bat test
```

**`flutter analyze` cannot see the bugs this app actually produces.** It has
passed clean through every one of: a RenderFlex overflow, a filter chip that
filtered nothing, a tab nothing navigated to, and push that never registered.
A clean analyze means the code compiles, not that the feature is reachable.

So: **drive the real thing.** The server's guide (§13 there) has the patterns —
mint an admin token, call the live API, watch the database. For this app, the
equivalent is running it against the real server and checking the server saw
what you expected. `audit_logs` is the honest record of whether the phone did
anything at all.

Tests worth knowing about:
- `test/record_form_test.dart` pins the MySQL ENUM values. Several columns are
  ENUMs and a dropdown offering something else is refused by the database on
  save, having looked fine in the form.
- `test/dates_test.dart` caught six files whose UTF-8 had been mangled by a
  PowerShell `Get-Content`/`Set-Content` round trip on this machine. **Do not
  edit source files that way.**

---

## 10. The recurring defect in this codebase

**Complete on the server, unreachable from the client.** It has happened, at
minimum, to: the Gallery tab, search-by-people, the notifications bell, video
support, two-factor sign-in, `kind=screenshots`, `sort=added`, and push.

Every one of them passed static checks. Every one of them existed as working,
tested server code with no way to reach it from a phone.

**Before building something, check whether it already exists on the server and
is simply unwired.** Read `backend/app/routers/` for what is actually offered,
and compare against what a screen calls. That check costs minutes and has
repeatedly replaced days of rebuilding.

### Its mirror image: reaching for a server feature that is not there yet

Reading `backend/app/routers/` tells you what THIS repository offers. It does
not tell you what the server on the other end of the phone is running, and those
are not the same thing — there is more than one SafeNest installation in this
household, and the owner's phone talks to the one that is behind.

`album_id` on `POST /api/gallery/upload` was added and 1.52.0 used it. FastAPI
**ignores a query parameter no argument claims**, so against the older
installation the upload succeeded, the photos appeared in the gallery, and the
album stayed empty. No error on either side. It was reported from a real phone:
two photos sent from the album screen, album still reading "0 photos".

1.52.1 uploads and then attaches the returned ids itself through
`/albums/{id}/photos`, an endpoint as old as albums, and says so plainly if that
step is the one that fails.

**A server change and a phone release do not arrive together. Assume the far end
is older: use what has always been there, or check before relying on what is
new.** An unknown query parameter is silently dropped; an unknown endpoint at
least gives you a 404 to notice.

### Working offline — `lib/offline/`

The server is somebody's home PC, so unreachable is the normal case. Records are
held on the phone and pushed when the owner presses **Sync**.

`store.dart` holds **two things with two lifetimes**, and conflating them is the
whole risk. `cache` is what the server last said — disposable, replaced
wholesale on each fetch. `pending` is what the owner typed while the computer
was asleep, and **until it syncs it exists in exactly one place in the world.**
So `confirmed()` deletes the one row the server named; a refusal is kept with
its reason. Eight of ten landing leaves exactly two behind, and a test says so.

Three rules that must survive any edit here:

1. **Replay oldest-first.** A create that replays after the edit which followed
   it is an edit against nothing. `resolveLocalId` re-points later operations
   once a create lands.
2. **Clear per item, never per batch.**
3. **Never silently discard a value.** A conflict keeps the local copy and tells
   the owner; the server's version stands until they say otherwise.

`sqflite`, **not** `sqflite_sqlcipher` — the latter bundles its own SQLite and
crypto natively, charged per ABI, ~5-6 MB against an APK that is 95% native
code. Payloads are sealed with a SHA-256 counter-mode stream plus an HMAC tag
(`crypto`, already a dependency), which is stated plainly in the header rather
than letting "encrypted" imply AES-GCM.

**The engine refuses to sync into a server whose `/api/sync/capabilities` 404s**
— see the version-drift trap above. It also distinguishes that from *cannot
reach it*, because those need different actions from the owner.

Vault is excluded and must stay excluded: its contents are decrypted on the
computer and the key never leaves it. Gallery and Documents keep their own
queues.

Server side lives in `finmate-react/backend/app/routers/sync.py`, verified by
`backend/verify_sync.py` against a running server.

### Media URLs from the server are relative — make them absolute

`/api/gallery/media/thumb/<name>?t=<signature>` is correct for the web app,
which is same-origin, and unusable here: `Image.network` cannot resolve a
relative URL and fails outright. The faces strip passed `cover_url` straight
through, so every face fell to its errorBuilder and the top of the gallery was a
row of grey silhouettes — reading as "face detection is broken" when every face
had been found and the pictures were simply never fetched.

`absoluteMedia()` in `lib/widgets/photo_tile.dart` is the one definition. The
rule had been copied into four widgets and the fifth forgot it; use the function
rather than writing `startsWith('http')` a sixth time. Pinned by
`test/faces_strip_test.dart`.

---

## 11. House style

Comments explain **why**, not what — and the convention here is to record the
real failure and the reasoning that fixed it. If you find yourself writing
`// increment the counter`, delete it. If you are writing `// 0 is falsy, so a
zero-day licence became a thirty-day one`, keep it.

British spelling in user-facing copy ("licence" the noun, "favourite",
"organised"). Amounts are rupees. Dates are **dd-mm-yyyy** and times are
**12-hour with AM/PM**, everywhere, via `dates.dart`.
