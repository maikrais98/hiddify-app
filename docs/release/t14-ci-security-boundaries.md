# T-14: CI and release trust boundaries

The CI workflow runs `build.yml` with `contents: read`, no inherited secrets and
no environment. Tests, unsigned iOS and the unsigned platform matrix cannot sign
or publish. Retaining CI artifacts does not enable signing; unsigned Windows
continues to skip MSIX. Checkout credentials are not persisted.

Tag releases call `signed-release.yml`. Its `unsigned-gates` job first runs the
same CI checks without secrets. Only a successful tag push can start the signed
matrix. That matrix uses the `release-signing` environment with a read-only
GitHub token. Release mutation and store uploads run on separate runners in
`release-publish`, after signed packages and unsigned checks succeed.

The release caller intentionally passes no secrets. Each called job obtains
secrets from its own named environment; `workflow_call.secrets` and
`secrets: inherit` are unnecessary for these environment-scoped credentials.
GitHub documents this distinction in
[Reuse workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows#using-inputs-and-secrets-in-a-reusable-workflow).
Repository-only credentials therefore need the explicit environment migration
below; a repository secret with the same name is not the intended fallback.

All active external `uses:` references are pinned to full commit SHAs, resolved
from upstream Git refs on 2026-09-16. Comments retain the source version/ref;
annotated tags were peeled to the commit. WinGet's former `@2` ref did not exist;
the pinned commit is upstream `v2`.

## Required repository configuration before release

This change does not configure GitHub environments. Until configured, sensitive
jobs fail at `Require protected ... environment` before accessing credentials.
A maintainer must create `release-signing` and `release-publish`, restrict them
to approved release tags, require reviewers, prevent self-review, and then set
`RELEASE_ENVIRONMENT_READY=true` **inside each environment**. Do not set this
variable at repository or organization scope. This variable is a fail-closed
configuration guard, not a substitute for GitHub's reviewer protection.

Move the following credentials to the environment that consumes them; do not
restore `secrets: inherit` or pass repository secrets to unsigned CI:

- `release-signing`: Apple signing certificate/password and mobile provisioning
  archive; Android signing key/store password/key password/alias; Windows
  signing key/password/SHA1; Sentry DSN and symbol-upload token/org/project.
  Existing signing and symbol-upload step names identify the exact secret keys.
- `release-publish`: cross-repository release token, Google Play service-account
  JSON, Apple upload certificate/password, App Store issuer/API credentials,
  distribution provisioning archive, and WinGet token. GitHub's automatic
  `GITHUB_TOKEN` is not a credential to copy.

Scope the external tokens to only their intended repository/store/project.
Signed packaging still executes reviewed tag code and dependencies while its
signing environment is unlocked; approval must therefore review that code and
its dependency changes. SHA pins constrain action updates but do not verify all
transitive downloads or build dependencies.

## Remaining write permissions

| Job | Permission | Reason |
| --- | --- | --- |
| `release.yml / build-release` | `contents: write` | Upper bound required for the reusable workflow's release jobs; inner test/signing jobs explicitly reduce it to read. |
| `signed-release.yml / update-draft` | `contents: write` | Deletes/replaces draft assets and creates the repository draft release. |
| `signed-release.yml / upload-release` | `contents: write` | Uploads the tagged GitHub release assets. |
| `add_signed_microsft.yml / upload-store-msix-to-release` | `contents: write` | Attaches the Microsoft Store MSIX to a GitHub release. |
| `stale.yml / stale` | `issues: write`, `pull-requests: write` | Marks/closes stale issues and pull requests. |

WinGet has `contents: read` for source release inspection and uses its separately
scoped external token. TestFlight needs no GitHub token permissions. Artifact
upload/download inside a run does not require `actions: write`.

## Verification boundary

`actionlint 1.7.7 -shellcheck= -pyflakes= .github/workflows/*.yml` passes YAML,
expression and workflow-schema checks. ShellCheck/Pyflakes were disabled; this
is not a shell or Python code audit. `bash test/ci/release_gate_test.sh` passes
artifact/gate fixtures and checks every active action pin, explicit permission
map, unsigned secret/environment exclusion, signing tag gate and publication
ordering. A live PR run verifies unsigned builds; a signing/store release was
not dispatched. Environment protection and secret availability must be checked
in GitHub before treating signed release delivery as verified.
