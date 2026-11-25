# Luminum P2P File Distribution — Design

**Version:** 0.1-draft
**Status:** PROPOSED — design for review; nothing here is built yet.
**Depends on:** `docs/protocol.md` v1.0-draft (envelope, framing, signing, MQTT control plane).

---

## 1. Purpose

Distribute package files from the server to many clients without the server being the
bottleneck. Once any client legitimately holds a file, the server may direct other
clients to fetch that file from the holding client. The server remains the authority:

1. **No client ever receives a file unless the server directs it to.** A transfer
   happens only under a server-signed, single-use transfer grant.
2. **The server decides who serves whom.** Holder tracking, source selection, and
   re-routing on failure are all server-side decisions.
3. **The server is always a valid source.** It holds every file it has published and
   is the fallback when no peer can serve (the "seed" path).

P2P is an extension of the existing bulk-data reference pattern (protocol §8.3), not
a new transport paradigm: same framing, same envelope, same signing, same trust
roots. The only new ingredients are a peer listener port, a client TLS identity, and
the transfer grant.

---

## 2. Port allocation

| Port | Name | Direction | Purpose |
|---|---|---|---|
| 8883 | `MPORT` | client → server | MQTT control plane (existing) |
| 10465 | `LPORT` | client → server | Bootstrap + client→server bulk data (existing) |
| **10464** | **`PPORT`** | **client ↔ client** | **P2P file transfer (new)** |
| 10704 | `IPORT` | server → client | Server→client bulk data / seed path (existing, reserved) |
| 10461 | `LPORT_LOCAL` | local | Lumy IPC (existing) |

**10704 is already reserved** for the server→client data channel (protocol §2, §8.3):
the server opens a TLS connection to `client:10704` to push package bytes. The client
already binds it on all three platforms (handler not yet implemented). It stays
dedicated to the server; P2P traffic never uses it.

**10464 (`PPORT`) is the new peer listener.** Every registered client binds it at
startup, exactly like `IPORT`. Any client may connect to any other client's 10464,
but the connection is only useful if the initiator presents a valid transfer grant
(§5). As with 10704, reachability (NAT/firewall) is the operator's responsibility.

---

## 3. Current state (what the design builds on / what is missing)

| Item | State |
|---|---|
| Envelope + Ed25519 signing + canonical JSON | Implemented (client + broker) |
| MQTT control plane, outbox (`CLIENTS.COMMANDS`) | Implemented |
| Bootstrap channel (10465), registration | Implemented |
| Client inbound data listener (10704) | Bound on client; handler is a TODO; server side not implemented |
| `deploy` command | Queued by broker; client answers `NOT_IMPLEMENTED` |
| Package storage / upload | Not implemented — `CONTENT.PACKAGES` table exists, console page is a UI stub, no file store, no per-file hash table |
| Client content directories | `Packages/` and `Downloads/` exist in the install layout (all platforms) |
| Luminum CA | Exists in generate mode (`luminum-ca.crt`/`.key`); import mode falls back to the self-signed server certificate as its own trust anchor |
| Client TLS identity | **Does not exist** — clients authenticate to the server one-way only. This design adds it (§4) |

**Prerequisite (Phase 0):** the server must actually hold package files with
per-file SHA-256 hashes before any of this can work. P2P distributes what the
package upload feature stores; it does not replace that feature.

---

## 4. Peer trust: client certificates

P2P channels carry file bytes between endpoints that have no prior relationship.
Two requirements:

- **Confidentiality in transit** — TLS 1.2+ on 10464, no plaintext fallback
  (protocol §2 rule).
- **Peer identity** — the serving client must be able to prove *which* endpoint is
  on the other end, so the server's grant (which names a specific requester UID)
  can be bound to the actual peer.

Neither is provided by today's one-way TLS. The design reuses the existing trust
root: **the Luminum CA issues each client a TLS certificate at registration.**

### 4.1 Issuance (registration extension)

The registration flow (protocol §7.1) gains one exchange:

1. At first run, alongside the Ed25519 signing keypair, the client generates a
   dedicated TLS keypair (P-256 ECDSA) and a CSR. The private key never leaves the
   endpoint.
2. The `register` request carries `tls_csr` (base64 PEM CSR).
3. The server signs the CSR with **the key that issued the server TLS
   certificate** — `luminum-ca.key` in generate mode, or the server certificate's
   own key in import/self-signed mode (mirroring the existing `prepare_signing`
   fallback). Subject: `CN = luminum-client-{UID}`; the UID is the identity.
4. The signed certificate (PEM) is returned in the signed `register` response as
   `clientcert`. The client stores it at `config/client.crt` next to
   `config/client.key` (both mode 0600).

No new trust material reaches the client: it verifies peer certificates against the
same root it already uses for the server (`luminum-ca.crt`, or the self-signed
`server.crt` in import mode). A client certificate chains to that root by
construction.

### 4.2 Verification on the P2P channel

Both ends of a 10464 connection perform mutual TLS:

- Each side presents its client certificate + key.
- Each side verifies the peer's certificate against its trusted root and extracts
  the peer UID from the CN (`luminum-client-{UID}`).
- The serving client additionally requires **peer UID == grant requester UID**
  (§5.3) — this binds the server's grant to the authenticated channel identity. A
  client holding a grant cannot hand it to a third party over its own connection,
  because the third party's certificate would name a different UID.

### 4.3 Revocation (v1 limitation)

v1 has no CRL/OCSP. Mitigations: grants are single-use and expire in 5 minutes, so
the exposure window for a de-registered or deactivated certificate is bounded; the
server stops issuing grants for deactivated UIDs immediately. Certificate
validity is set to 1 year at issuance; re-issuance on re-registration replaces the
stored certificate. A revocation list is a documented v2 item.

---

## 5. The transfer grant

The grant is the server's directive: *requester R may fetch file set F from source
S, once, within 5 minutes.* It is a **signed envelope** (protocol §5), so it is
self-authenticating — the serving peer verifies it with the server signing key the
client already holds (the §7.1 trust anchor). No out-of-band channel is needed to
validate a grant.

### 5.1 Format

```json
{
  "v": "1.0",
  "id": "9b2f...-grant-uuid",
  "ts": 1735689600,
  "src": "server",
  "uid": "451",
  "lumy": "core",
  "action": "p2pgrant",
  "status": "OK",
  "data": {
    "token": "c1a0...-uuid",
    "pkgid": 17,
    "os": "Linux",
    "files": [
      { "fileid": 311, "path": "scripts/apply.sh", "size": 48213, "sha256": "ab12..." },
      { "fileid": 312, "path": "content/policy.xml", "size": 90211, "sha256": "cd34..." }
    ],
    "src": { "uid": 208, "ip": "172.16.0.44", "port": 10464 },
    "exp": 1735689900
  },
  "sig": "base64..."
}
```

- `uid` is the **requester** UID. `data.src` is the **source**: a peer
  (`uid` = peer's numeric UID, `ip` from `CLIENTS.STATUS.IPV4`, `port` = 10464) or
  the server itself (`uid` = 0, `ip` = server address, `port` = 10704).
- The grant covers **one package revision for one OS** — the full per-file list, so
  a multi-file package is one grant and one connection, not N connections.
- `exp` = `ts` + 300 s (same 5-minute lifetime as §8.3 data tokens).
- `token` is single-use (one transfer session) and tracked server-side (§7.3).

The grant travels to the requester inside the `deploy` command:

```json
{ "aid": "...", "pkgid": 17, "ref": { "channel": "p2p", "grant": "<grant envelope>" } }
```

(`ref.channel: "data"` with a plain token remains the §8.3 form for the
client→server direction and oversized sensor output; the deploy flow always uses
the grant form, including the server-seeded case, so there is one token mechanism.)

### 5.2 Lifecycle

1. Console queues a `deploy` for target set T (existing outbox flow).
2. For each target, the broker resolves a source (§7.1) and mints a grant
   (new token, `exp` = now + 300 s), recording it in `CLIENTS.P2PTOKENS`.
3. The grant is embedded in that target's `deploy` command data.
4. The requester presents it to the source (§6). The source verifies and consumes
   it (locally, for the session).
5. On completion the requester reports `p2p_fetch_ok`; the server marks the token
   `USED` and records the requester as a holder. On failure the server may mint a
   replacement grant with a different source (§7.2).
6. Unconsumed tokens expire after 5 minutes (broker sweep).

### 5.3 Source-side verification checklist

The serving peer accepts a transfer only if **all** hold:

1. mTLS succeeded and the peer certificate validated against the trusted root.
2. Peer certificate UID == grant `uid` (channel identity bound to the grant).
3. Grant signature verifies under the server signing key (the §7.1 anchor).
4. `exp` is in the future.
5. `token` has not been used on this endpoint (local used-token ring, same
   pattern as the 1,000-entry message-ID dedup ring, protocol §9.2).
6. Every `fileid` in the grant is present in the local file manifest (§8.2) with
   matching `size` and `sha256` (a holder whose copy was modified locally cannot
   serve it; the mismatch is reported to the server).

Any failure ⇒ `ERR` response with a machine-readable code (`BAD_GRANT`,
`GRANT_EXPIRED`, `GRANT_USED`, `UID_MISMATCH`, `FILE_MISSING`, `FILE_MISMATCH`)
and the connection closes. The requester reports the failure to the server.

---

## 6. Peer channel wire protocol

Port 10464, TLS 1.2+, then the existing length-prefixed framing (protocol §8.2:
4-byte big-endian length + payload). One connection per (requester, source) grant.

```
Requester (R)                          Source (S)
  |=== mTLS (both present client certs) =>|
  |-- frame: p2pgrant envelope (the grant) ->|
  |                                       | verify §5.3
  |<-- frame: core/p2pfetch resp ----------|  {token, status: OK, files: [sizes]}
  |                                       |
  |  for each file in grant order:        |
  |  |-- frame: core/p2pfetch req -------->|  {token, fileid}
  |  |<-- frame: core/p2pfetch resp -------|  {token, fileid, status: OK, size}
  |  |<-- raw chunks (4B len + bytes) ---->|  up to 1 MiB per chunk
  |  |<-- frame: zero-length (EOF) --------|
  |                                       |
  |-- TLS close -------------------------->|
```

- Handshake envelopes are signed by the **requester** (the grant envelope is
  server-signed and forwarded verbatim; the per-file `p2pfetch` req/resp envelopes
  are signed by their sender).
- Raw chunks are plain file bytes in the same framing — not JSON. A zero-length
  frame terminates a file's stream.
- The requester writes each file to `Downloads/` (staging), verifies total size and
  SHA-256, then moves it to its final path under `Packages/` and records it in the
  local manifest. A hash mismatch aborts the whole session: staged files are
  deleted, `p2p_fetch_fail` is reported, nothing is installed.
- The requester's package **Download Timeout** (the field already on the package
  form, default 2 min) bounds the whole session; the per-file stream has no
  independent timeout in v1.

---

## 7. Server-side behavior

### 7.1 Source selection (broker, at deploy-queue time)

For each target endpoint and each file set in the deploy:

1. **Candidates** = rows in `CONTENT.PKGHOLDERS` for the package's files where
   holder UID ≠ target, the holder is online (`CSTATE` live, not `MISSING`, not
   `DEACT`), reports the P2P capability (§7.4), and `P2PENABLED` is `Enabled`.
   A candidate must hold **every** file in the grant's list.
2. If candidates exist: pick one (v1: the least recently selected, tracked by
   `P2PTOKENS` history; same-/24 preference per `CLIENTS.STATUS.IPV4` is a v2
   nicety) and mint a peer grant.
3. Otherwise: mint a **server grant** (`src.uid = 0`, port 10704) — the seed path
   over the existing server→client data channel.

The server therefore de-loads itself automatically: the first endpoints to finish
a deploy become sources for the rest of the target set, which the broker processes
row by row as reports arrive.

### 7.2 Failure re-routing

On `p2p_fetch_fail` from target T naming source S:

1. Mark token used (a failed session consumes the grant).
2. Re-run source selection for T excluding S (S is excluded for the remainder of
   this deploy; repeated failures from S across deploys demote S — v1 simply
   excludes per-deploy).
3. Mint a fresh grant (new token) and enqueue a new `deploy` command for T.
4. If no peer remains, the fresh grant is a server grant.

A target that fails against every source (and the server) is reported to the
console as a failed deploy, same as any command timeout.

### 7.3 Token and holder bookkeeping

- `CLIENTS.P2PTOKENS` rows are swept by the broker's existing periodic sweep
  (the one that already handles `MISSINGAFTER`): `EXPIRES` passed and unused ⇒
  delete; `USED` rows are retained briefly for audit then pruned.
- `p2p_fetch_ok` ⇒ upsert `CONTENT.PKGHOLDERS (fileid, requester, source)` for
  every file in the grant, mark token `USED`.
- Deregistration (console or client-initiated) and the missing sweep delete the
  endpoint's `PKGHOLDERS` rows.
- A new package **revision** mints new file rows (new SHA-256) ⇒ old holders do
  not qualify as sources for the revision, by construction.

### 7.4 Capability advertisement

The check-in payload (protocol §6.1 `core/checkin`) gains one optional field:
`p2p` (boolean). The broker stores it (new `CLIENTS.STATUS.P2P` column) and uses
it in candidate selection, so pre-P2P clients are never selected as sources nor
sent peer grants. The server itself is always a valid source regardless.

---

## 8. Client-side behavior

### 8.1 New components (per platform; Linux first, mirroring project pattern)

| Component | Responsibility |
|---|---|
| P2P listener | Bind `PPORT` 10464 at startup (like `IPORT`); accept loop, one thread per connection; enforce a max of **1 concurrent serving session** (v1) — excess connections are refused with `ERR BUSY` |
| Fetcher | On a `deploy` command with `ref.channel = "p2p"`: connect to `src` (mTLS, verify peer cert UID == grant `src.uid`), run the §6 session, stage in `Downloads/`, verify, install under `Packages/`, update manifest, report |
| Grant/token state | Local used-token ring (in-memory, §5.3 item 5); in-flight session state |
| File manifest | SQLite table (new `config/p2p.db`, mode 0600): `FILEID, PKGID, OS, PATH, SIZE, SHA256, TS` — the endpoint's record of what it holds |
| Startup sync | After MQTT connect, publish a one-shot `p2p/have` event (events topic) listing manifest `FILEID`s, so the server can rebuild `PKGHOLDERS` after client or server restarts |

### 8.2 Storage layout

- Staging: `Downloads/{token}/…` (deleted on success or failure).
- Final: `Packages/{pkgid}/{path}` where `{path}` is the grant's relative path
  (server-assigned, sanitized — no `..`, no absolute paths; the client rejects
  anything else before writing).
- The manifest is the single source of truth for "what can I serve"; a file on
  disk without a manifest row is not served.

### 8.3 Registration extension

Generate the TLS keypair + CSR at first run (§4.1), send `tls_csr` in the
`register` request, store `clientcert` from the response. A client that
registered before this feature exists re-registers on upgrade (new keypair/UUID
flow already handles this) — or, to avoid churning endpoint records, the broker
supports a `core/certrenew` bootstrap request (existing fingerprint, same UID)
that mints and returns a client certificate without re-registering. **[DECISION:
recommend `certrenew`; avoids endpoint-record churn on fleet upgrade.]**

---

## 9. Database schema additions

```sql
-- CONTENT: per-OS file blobs belonging to a package (Phase 0, package upload)
CREATE TABLE IF NOT EXISTS `PKGFILES` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `PKGID` int(20) NOT NULL,
  `OS` tinytext NOT NULL,            -- 'Linux' | 'Mac' | 'Windows'
  `FILENAME` tinytext NOT NULL,
  `PATH` tinytext NOT NULL,          -- relative path inside the package
  `SIZE` tinytext NOT NULL,
  `SHA256` char(64) NOT NULL,
  `SERVERPATH` tinytext NOT NULL,    -- absolute path on the server
  PRIMARY KEY (`ID`),
  KEY `IDX_PKGFILES_PKG` (`PKGID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- CONTENT: which endpoints currently hold which files
CREATE TABLE IF NOT EXISTS `PKGHOLDERS` (
  `ID` int(20) NOT NULL AUTO_INCREMENT,
  `FILEID` int(20) NOT NULL,
  `UID` int(20) NOT NULL,
  `SOURCE` tinytext NOT NULL,        -- 'server', 'local', or the serving peer's UID
  `TS` datetime NOT NULL,
  PRIMARY KEY (`ID`),
  UNIQUE KEY `UQ_PKGHOLDERS` (`FILEID`,`UID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- CLIENTS: single-use P2P transfer grants (protocol p2p.md 5)
CREATE TABLE IF NOT EXISTS `P2PTOKENS` (
  `TOKEN` char(36) NOT NULL,
  `PKGID` int(20) NOT NULL,
  `REQUID` int(20) NOT NULL,
  `SRCUID` int(20) NOT NULL,         -- 0 = server seed
  `EXPIRES` datetime NOT NULL,
  `USED` datetime DEFAULT NULL,
  PRIMARY KEY (`TOKEN`),
  KEY `IDX_P2PTOKENS_EXPIRES` (`EXPIRES`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
```

Plus one column: `CLIENTS.STATUS.P2P` tinyint(1) default 0 (capability, §7.4).

Server-side file storage: `SVRPATH/content/packages/{pkgid}/{os}/{path}` (new
`content/` subtree under the server install root, mode 0750, owned by the broker
service account).

---

## 10. Protocol catalog additions (for protocol.md v1.1)

| Direction | lumy | action | `data` | Description |
|---|---|---|---|---|
| c→s (bootstrap) | core | `register` | + `tls_csr` (base64 PEM) | Existing, extended (§4.1) |
| s→c (bootstrap) | core | `register` | + `clientcert` (base64 PEM) | Existing, extended (§4.1) |
| c→s (bootstrap) | core | `certrenew` | `fingerprint` | Re-issue client certificate for an existing fingerprint (UID unchanged) |
| s→c | core | `p2pgrant` | `token`, `pkgid`, `os`, `files[]`, `src{uid,ip,port}`, `exp` | The transfer grant (§5.1); server-signed, forwarded to the source verbatim |
| c→s | core | `deploy` (resp) | — | Unchanged; the command's `ref` carries the grant |
| c→s | core | `report` | `event: "p2p_fetch_ok"` / `"p2p_fetch_fail"`, `pkgid`, `srcuid`, `files[]` (ok) or `err` (fail) | Transfer outcome; drives holder bookkeeping and re-routing |
| c→s (events) | core | `p2p/have` | `files` (array of fileids) | One-shot startup sync of the local manifest |
| peer | core | `p2pfetch` | req: `token`, `fileid`; resp: `token`, `fileid`, `status`, `size`/`err` | Per-file handshake inside a grant session (§6) |
| c→s | core | `checkin` | + `p2p` (boolean) | Capability advertisement (§7.4) |

New server config key: `P2PENABLED` (`Enabled`/`Disabled`, default `Enabled`) —
master switch; when `Disabled` the broker mints only server grants.

New client config DB values: none (certificates are files: `config/client.crt`,
`config/client.key`; the manifest is `config/p2p.db`).

---

## 11. Security analysis

| Threat | Mitigation |
|---|---|
| Client receives a file it was not directed to fetch | Impossible without a valid grant; grants are server-signed, single-use, 5-min expiry, name the exact file set (SHA-256 each) and the exact requester |
| Malicious peer serves tampered content | Receiver verifies size + SHA-256; the hashes are inside the server-signed grant, so substitution fails verification. Source-side manifest check (§5.3 item 6) stops a *corrupted holder* from poisoning others |
| Grant replay / forwarding to a third party | Single-use token (server table + local ring); channel identity binding — peer cert UID must equal grant `uid` (§4.2) |
| Impersonation of a peer | mTLS with CA-issued client certificates; both ends verify the full chain and the UID |
| Eavesdropping on transfers | TLS 1.2+ on 10464; no plaintext fallback (protocol §2 rule extended to P2P) |
| Deactivated client keeps serving | No CRL in v1 (documented limitation, §4.3); exposure bounded by grant lifetime, and the server stops minting grants for deactivated UIDs |
| Bandwidth abuse (one client DDoS'd by serving) | v1: 1 concurrent serving session per client; grants bound the total bytes to the named file set; `P2PENABLED` kills the feature fleet-wide |
| Path traversal via grant `path` | Server sanitizes at package upload; client re-validates (relative, no `..`) before writing (§8.2) |

---

## 12. Build phases

| Phase | Scope | Depends on |
|---|---|---|
| **0. Package file store** | Console upload flow: store per-OS files under `content/packages/`, compute SHA-256, fill `PKGFILES`; wire the existing (stub) package form | — |
| **1. Schema + config** | `PKGFILES`, `PKGHOLDERS`, `P2PTOKENS`, `STATUS.P2P`, `P2PENABLED`; protocol.md v1.1 section | 0 |
| **2. Client certificates** | Broker: CSR signing at registration + `certrenew`; client: keypair/CSR generation, `clientcert` storage, `certrenew` on upgrade | 1 |
| **3. Seed path (10704)** | Implement the existing TODO: client inbound data handler + broker push, using the grant form with `src.uid = 0`. This makes `deploy` work end-to-end before any peer is involved | 1 |
| **4. Client P2P (Linux)** | `PPORT` listener, fetcher, manifest, staging/install, `p2p/have` sync, `p2p` check-in flag | 2, 3 |
| **5. Broker P2P** | Source selection, grant minting, `p2p_fetch_ok/fail` handling, re-routing, token/holder sweeps | 4 |
| **6. Console deploy wiring** | Deploy action against selected clients (outbox already exists); per-endpoint transfer status in the action history | 5 |
| **7. macOS + Windows parity** | Same client components on the other two platforms | 6 |
| **8. Tests** | Extend `tests/deploy_test.sh`: two-client P2P transfer, tampered-hash rejection, grant replay rejection, seed fallback when peer offline | 7 (Linux-only variant after 5) |

Each phase is independently verifiable; Phases 3–5 give a working (server-seeded)
deploy before any peer-to-peer traffic exists.

---

## 13. Open items

1. **`certrenew` vs. forced re-registration on upgrade** — design recommends
   `certrenew` (§8.3); needs confirmation.
2. **Source selection policy** — v1 is least-recently-selected among online
   holders; same-subnet preference and per-client serving rate caps are v2.
3. **Serving concurrency** — v1 fixes 1 concurrent session per client; a config
   key (`P2PSEEDMAX`?) only if operators ask for more.
4. **Non-package files** — the grant mechanism is file-set-generic, but v1 mints
   grants only for package deploys. Ad-hoc "send this file to that client" would
   be a thin console feature on the same machinery, deferred.
5. **Grant lifetime** — 300 s matches §8.3; large packages on slow links may need
   the package Download Timeout to govern instead (the client-side session bound
   already does; the grant `exp` could be raised to the larger of the two).

---

*End of design.*
