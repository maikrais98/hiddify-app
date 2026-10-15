# Blizzard persistent iOS signing preparation

Status: the offline request/assembly tool and protected bootstrap workflow are
covered by offline checks. No persistent private key, Apple certificate, provisioning profile, P12,
GitHub secret, or Apple account resource was created by this repository change.
Keep `release-signing.RELEASE_ENVIRONMENT_READY=false`. Certificate creation,
profile creation, local assembly, and protected-secret installation form one
reviewed setup boundary. Removal of shared API credentials, enabling signing,
and any upload remain separately authorized operations.

The Apple Developer account and its certificate quota are shared. This process
must not revoke or delete a certificate/profile, change an App ID capability,
or replace another user's material. It is only for a new dedicated Blizzard
distribution certificate and the two exact App Store profiles after the account
step is approved.

## 1. Prepare one local request

Run this only after local private-key creation is approved. Choose a durable,
encrypted, non-synchronised location outside the repository and outside a
temporary directory:

```sh
umask 077
REQUEST_DIR="/absolute/private/path/blizzard-ios-signing-request"
ruby scripts/ios_baseline_signing_request.rb prepare "$REQUEST_DIR"
```

`prepare` creates the directory exclusively and refuses to use an existing
path. It creates:

| File | Classification | Purpose |
| --- | --- | --- |
| `request.csr.pem` | Public | Apple certificate signing request. |
| `request.json` | Public | CSR SHA-256, RSA-3072 SPKI SHA-256, non-personal Blizzard subject, and creation time. |
| `private-key.pem` | Private, mode `0600` | AES-256-encrypted RSA-3072 source key. The PEM is never attached to the public bootstrap; the approved protected P12 later contains this key. |
| `private-key-password.txt` | Secret, mode `0600` | Random password for the source PEM. It remains local and is distinct from the P12 password. |

The directory is mode `0700`. The command prints only the two public paths and
the public SPKI fingerprint. It never prints the key or password.
The encrypted PEM and its password are deliberately co-located, so the actual
custody boundary is access to the whole `0700` directory and its encrypted
backup, not the PEM encryption by itself.

Back up the encrypted key and its password to the separately approved encrypted
custody location before any Apple create request. A repeated attempt must reuse
the exact existing `request.csr.pem` and `request.json`. Do not run `prepare`
into another directory to recover from an Apple or network error: that would
create a second key and make reconciliation ambiguous.

Only `request.csr.pem` and `request.json` may be attached to a future bootstrap
request. Never attach, paste, commit, or upload the request directory itself.

## 2. Protected Apple account bootstrap

The `iOS baseline signing bootstrap` workflow receives only the public CSR and
matching manifest, each encoded as base64. It never receives the local private
key, its password, or a P12. Its modes are:

- `plan`: read the account and report missing materials, without writes;
- `resume`: reconcile already-created materials, without writes;
- `create`: after separate setup approval, create at most one Distribution
  certificate and the two missing App Store profiles in the initial attempt.

The account job runs only on manual dispatch from this repository's main
branch, after its secretless tests. It requires the protected publish
environment's readiness and a separate `SIGNING_BOOTSTRAP_READY=true` variable.
This change does not enable that variable. Create additionally requires the
literal confirmation `CREATE_ONE_BLIZZARD_DISTRIBUTION_IDENTITY` and run attempt
1. Signing remains independently paused in `release-signing`.

Before any POST it reads the complete paginated inventory for Team `M9D72QQJ79`
and the exact existing bundle IDs:

- `com.womaninred.baseline`
- `com.womaninred.baseline.HiddifyPacketTunnel`

Certificate identity is the CSR SPKI fingerprint, not a display name or date.
Zero matching certificates permits one explicitly approved initial create; one match
is reused after validation; more than one match stops. Each deterministic
profile may be reused only after its exact bundle, certificate relationship,
type, state, expiry, and entitlements are validated.

Before exposing Apple credentials for create, the workflow checks for a
previous intent artifact keyed by the full CSR public-key fingerprint and
uploads its own intent successfully. A previous intent or unavailable GitHub
history blocks create. The artifact is retained for seven days; an initial
create requires a CSR manifest no older than 24 hours, with five minutes of
clock skew allowed. Keep the intent record during recovery; deleting it is not
a retry mechanism. Global concurrency serializes bootstrap runs.

Certificate/profile POSTs do not retry automatically after a timeout, 429,
5xx, malformed success, runner loss, or unknown response. One GET reconciliation
may establish whether the resource exists, then the attempt stops. Use `resume`
for further reads. Missing resources after an interrupted attempt require a
separately reviewed scoped action; never issue a second certificate request or
generate a new local key as a recovery shortcut.

The result artifact contains a safe receipt and, when complete, the public DER
certificate and two signed profiles. It contains no private key, P12, password
or API credential. Partial failures retain a safe receipt; a lost runner is
reconciled from the saved request and prior intent. Certificate ownership or a
free Distribution quota slot is not inferred from the earlier Development
certificate inventory. Apple certificate issuance and profile acceptance have
not been exercised by offline tests.

No DELETE, PATCH, revocation, App ID creation or capability change is permitted.
The actual account creates, local assembly and protected-material installation
remain one separately approved setup. Preparing or merging this workflow
performs none of those operations.

## 3. Assemble only the approved downloaded materials

After the approved bootstrap has completed and its public receipt has been
checked, download the dedicated certificate and exact app/extension profiles to
a private local directory. Keep that directory mode `0700` and its downloaded
files mode `0600`. Then run:

```sh
DOWNLOAD_DIR="/absolute/private/path/blizzard-ios-download"
ruby scripts/ios_baseline_signing_request.rb assemble \
  "$REQUEST_DIR" \
  "$DOWNLOAD_DIR/distribution.cer" \
  "$DOWNLOAD_DIR/app.mobileprovision" \
  "$DOWNLOAD_DIR/extension.mobileprovision"
```

Before writing output, `assemble` verifies that the certificate SPKI matches
both the saved CSR and encrypted key. It then uses the shared manual-signing
validator to require the exact Apple Distribution certificate, Team
`M9D72QQJ79`, validity window, profile certificate relationship, App Store
profile type, bundle IDs, App Group and packet-tunnel entitlements. Any mismatch
stops without creating `assembled/`.

Bootstrap also checks that the profiles cover every networking mode and VPN API
grant in the pinned source, and production push for the app. It does not reduce
source entitlements to fit a profile. The signed archive independently verifies
source preservation and the actual signing certificate.

On success, `assembled/` is created exclusively with mode `0700` and contains:

- `distribution.p12` — private, mode `0600`;
- `distribution-p12-password.txt` — a new random secret, mode `0600`;
- `certificate-sha256.txt` — the public DER certificate SHA-256.

The P12 and its password are never printed. A second `assemble` refuses to
replace an existing `assembled/` directory. Keep the two downloaded profiles in
the same approved local custody until secret installation is complete.

## 4. Install protected GitHub material later

This step is not performed by the tool. Run it only within the same reviewed
protected setup that produced the dedicated certificate and profiles. Use an
already authenticated `gh` session; do not create or paste a token into these
commands. First confirm the authenticated account and exact repository:

```sh
gh auth status --hostname github.com
gh repo view maikrais98/hiddify-app --json nameWithOwner --jq .nameWithOwner
```

With the approved downloaded paths still set, stream every secret through
stdin. No secret value appears in a command argument or terminal output:

```sh
base64 < "$REQUEST_DIR/assembled/distribution.p12" | tr -d '\n' | \
  gh secret set IOS_BASELINE_SIGNING_P12_BASE64 \
    --env release-signing --repo maikrais98/hiddify-app

gh secret set IOS_BASELINE_SIGNING_P12_PASSWORD \
  --env release-signing --repo maikrais98/hiddify-app \
  < "$REQUEST_DIR/assembled/distribution-p12-password.txt"

base64 < "$DOWNLOAD_DIR/app.mobileprovision" | tr -d '\n' | \
  gh secret set IOS_BASELINE_APP_PROFILE_BASE64 \
    --env release-signing --repo maikrais98/hiddify-app

base64 < "$DOWNLOAD_DIR/extension.mobileprovision" | tr -d '\n' | \
  gh secret set IOS_BASELINE_EXTENSION_PROFILE_BASE64 \
    --env release-signing --repo maikrais98/hiddify-app
```

The certificate SHA-256 is public metadata, so install it as an environment
variable after checking the file contains exactly one lowercase 64-hex digest:

```sh
grep -Eq '^[0-9a-f]{64}$' \
  "$REQUEST_DIR/assembled/certificate-sha256.txt"
gh variable set IOS_BASELINE_SIGNING_CERT_SHA256 \
  --env release-signing --repo maikrais98/hiddify-app \
  --body "$(tr -d '\n' < "$REQUEST_DIR/assembled/certificate-sha256.txt")"
```

Verify names and scopes without reading values:

```sh
gh secret list --env release-signing --repo maikrais98/hiddify-app
gh variable list --env release-signing --repo maikrais98/hiddify-app
```

A partial `gh secret set` sequence is not readiness. Leave
`RELEASE_ENVIRONMENT_READY=false` during setup. Before an approved first signing
attempt, require successful local assembly and validation, complete protected
secret installation, and removal of the obsolete Apple API credentials from
`release-signing` after confirming publishing access remains available. Check
repository/organization fallback secrets as well: an old workflow rerun must
not regain account access when the pause is lifted.

The first protected signing attempt revalidates all materials and requires a
trusted, usable private identity in its temporary keychain before archive.
Successful offline checks do not prove Apple accepts the certificate chain or
that a real archive/export succeeds. TestFlight readiness and physical-iPhone
VPN validation require their own evidence after the approved release attempt.

## CI scope for service changes

Release-only scripts, their checks and workflow selection changes use dedicated
secretless checks. They do not trigger an application build on their own. Any
mixed change touching application/native code, core preparation, dependencies,
the shared build workflow or an unknown path still runs general CI. Within a
thematic batch, keep separate commits and targeted tests; push the completed
batch for its required checks once, repeating after meaningful changes or
failures.
