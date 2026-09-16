#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/hiddify-release-gate.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

fixture_baseline="$work_dir/analyzer-baseline.txt"
analyzer_output="$work_dir/analyzer.txt"
printf '%s\n' \
  'analyzer-baseline-v1' \
  'INFO|LINT|OLD_INFO|lib/old.dart' \
  'WARNING|STATIC_WARNING|OLD_WARNING|lib/old.dart' > "$fixture_baseline"
printf '%s\n' \
  'INFO|LINT|OLD_INFO|lib/old.dart|1|1|1|fixture' \
  'WARNING|STATIC_WARNING|OLD_WARNING|lib/old.dart|1|1|1|fixture' > "$analyzer_output"
ANALYZER_BASELINE_FILE="$fixture_baseline" \
  bash "$repo_root/scripts/check_analyzer_ratchet.sh" --input "$analyzer_output"

printf '%s\n' \
  'INFO|LINT|NEW_INFO|lib/new.dart|1|1|1|fixture' \
  'WARNING|STATIC_WARNING|OLD_WARNING|lib/old.dart|1|1|1|fixture' > "$analyzer_output"
if ANALYZER_BASELINE_FILE="$fixture_baseline" \
  bash "$repo_root/scripts/check_analyzer_ratchet.sh" --input "$analyzer_output"; then
  echo "analyzer ratchet accepted a same-count replacement diagnostic" >&2
  exit 1
fi

printf 'INFO|LINT|OLD_INFO|lib/old.dart|1|1|1|fixture\n' > "$analyzer_output"
if ANALYZER_BASELINE_FILE="$fixture_baseline" \
  bash "$repo_root/scripts/check_analyzer_ratchet.sh" --input "$analyzer_output"; then
  echo "analyzer ratchet accepted removed debt without a baseline update" >&2
  exit 1
fi

printf 'ERROR|COMPILE_TIME_ERROR|fixture|lib/fixture.dart|1|1|1|fixture\n' > "$analyzer_output"
if ANALYZER_BASELINE_FILE="$fixture_baseline" \
  bash "$repo_root/scripts/check_analyzer_ratchet.sh" --input "$analyzer_output"; then
  echo "analyzer ratchet accepted an error diagnostic" >&2
  exit 1
fi

expected_artifacts=(
  Hiddify-Android-arm64.apk
  Hiddify-Android-arm7.apk
  Hiddify-Android-x86_64.apk
  Hiddify-Android-universal.apk
  hiddify-android-market.aab
  Hiddify-Windows-Setup-x64.exe
  Hiddify-Windows-x64.msix
  Hiddify-Windows-Portable-x64.zip
  Hiddify-Debian-x64.deb
  Hiddify-Linux-x64-AppImage.tar.gz
  Hiddify-Linux-x64-AppImage.AppImage
  Hiddify-MacOS.dmg
  Hiddify-MacOS-Installer.pkg
)
manifest_names="$(awk 'NF && $1 !~ /^#/ { sub(/\r$/, ""); print }' "$repo_root/.github/release-artifacts.txt" | LC_ALL=C sort)"
hardcoded_names="$(printf '%s\n' "${expected_artifacts[@]}" | LC_ALL=C sort)"
if [[ "$manifest_names" != "$hardcoded_names" ]]; then
  echo "release artifact manifest differs from the independently expected set" >&2
  exit 1
fi

artifact_dir="$work_dir/out"
mkdir -p "$artifact_dir"
for expected in "${expected_artifacts[@]}"; do
  printf 'fixture\n' > "$artifact_dir/$expected"
done
bash "$repo_root/scripts/check_release_artifacts.sh" "$artifact_dir"

rm "$artifact_dir/Hiddify-MacOS.dmg"
if bash "$repo_root/scripts/check_release_artifacts.sh" "$artifact_dir"; then
  echo "release artifact check accepted an incomplete artifact set" >&2
  exit 1
fi
printf 'fixture\n' > "$artifact_dir/Hiddify-MacOS.dmg"

printf 'fixture\n' > "$artifact_dir/unexpected.txt"
if bash "$repo_root/scripts/check_release_artifacts.sh" "$artifact_dir"; then
  echo "release artifact check accepted an unexpected top-level asset" >&2
  exit 1
fi
rm "$artifact_dir/unexpected.txt"

rm "$artifact_dir/Hiddify-MacOS.dmg"
ln -s Hiddify-MacOS-Installer.pkg "$artifact_dir/Hiddify-MacOS.dmg"
if bash "$repo_root/scripts/check_release_artifacts.sh" "$artifact_dir"; then
  echo "release artifact check accepted a symlink" >&2
  exit 1
fi
rm "$artifact_dir/Hiddify-MacOS.dmg"
mkdir "$artifact_dir/Hiddify-MacOS.dmg"
if bash "$repo_root/scripts/check_release_artifacts.sh" "$artifact_dir"; then
  echo "release artifact check accepted a directory" >&2
  exit 1
fi

core_version="$(awk -F= '$1 == "core.version" { print $2 }' "$repo_root/dependencies.properties")"
release_linux_digest="$(awk -F= '$1 == "core.release.sha256.linux-amd64" { print $2 }' "$repo_root/dependencies.properties")"
draft_linux_digest="$(awk -F= '$1 == "core.draft.sha256.linux-amd64" { print $2 }' "$repo_root/dependencies.properties")"
release_core_recipe="$(make --no-print-directory -n -C "$repo_root" CHANNEL=dev CORE_CHANNEL=release linux-amd64-libs)"
draft_core_recipe="$(make --no-print-directory -n -C "$repo_root" CHANNEL=dev CORE_CHANNEL=draft linux-amd64-libs)"
[[ "$release_core_recipe" == *"/v$core_version/hiddify-lib-linux-amd64.tar.gz"* && "$release_core_recipe" == *"$release_linux_digest"* ]] || {
  echo "release core override does not select the versioned archive and digest" >&2
  exit 1
}
[[ "$draft_core_recipe" == *"/draft/hiddify-lib-linux-amd64.tar.gz"* && "$draft_core_recipe" == *"$draft_linux_digest"* ]] || {
  echo "draft core override does not select the draft archive and digest" >&2
  exit 1
}

ios_core_recipe="$(make --no-print-directory -n -C "$repo_root" ios-libs)"
[[ "$ios_core_recipe" == *"scripts/build_ios_core.sh"* && "$ios_core_recipe" != *"download_core_archive"* ]] || {
  echo "iOS core recipe does not build the pinned source contract" >&2
  exit 1
}

core_patch="$work_dir/hiddify-core.patch"
gzip -dc "$repo_root/patches/hiddify-core-local-control.patch.gz" > "$core_patch"
for required_path in v2/localauth/auth.go v2/localauth/auth_test.go; do
  grep -Fq "diff --git a/$required_path b/$required_path" "$core_patch" || {
    echo "local-control patch is missing $required_path" >&2
    exit 1
  }
done
core_fixture="$work_dir/hiddify-core"
git clone --quiet --no-hardlinks --no-checkout "$repo_root/hiddify-core" "$core_fixture"
git -C "$core_fixture" checkout --quiet f2034de743b1ad775dba026f4e6e3c44cf7d9790
git -C "$core_fixture" apply --check "$core_patch"

bootstrap_root="$work_dir/bootstrap-repo"
mkdir -p "$bootstrap_root/scripts" "$bootstrap_root/patches"
cp "$repo_root/scripts/apply_hiddify_core_patch.sh" "$bootstrap_root/scripts/"
cp "$repo_root/patches/hiddify-core-local-control.patch.gz" "$bootstrap_root/patches/"
git clone --quiet --no-hardlinks --no-checkout "$repo_root/hiddify-core" "$bootstrap_root/hiddify-core"
git -C "$bootstrap_root/hiddify-core" checkout --quiet f2034de743b1ad775dba026f4e6e3c44cf7d9790
git -C "$bootstrap_root/hiddify-core" config \
  submodule.hiddify-sing-box.url "$repo_root/hiddify-core/hiddify-sing-box"

bootstrap_git_env=(
  GIT_CONFIG_COUNT=6
  GIT_CONFIG_KEY_0=protocol.file.allow
  GIT_CONFIG_VALUE_0=always
  GIT_CONFIG_KEY_1=url.file://$repo_root/hiddify-core/hiddify-sing-box/replace/tailscale.insteadOf
  GIT_CONFIG_VALUE_1=https://github.com/hiddify/tailscale
  GIT_CONFIG_KEY_2=url.file://$repo_root/hiddify-core/hiddify-sing-box/replace/psiphon-quic-go.insteadOf
  GIT_CONFIG_VALUE_2=https://github.com/hiddify/psiphon-quic-go
  GIT_CONFIG_KEY_3=url.file://$repo_root/hiddify-core/hiddify-sing-box/replace/psiphon-tls.insteadOf
  GIT_CONFIG_VALUE_3=https://github.com/hiddify/psiphon-tls
  GIT_CONFIG_KEY_4=url.file://$repo_root/hiddify-core/hiddify-sing-box/replace/wireguard-go.insteadOf
  GIT_CONFIG_VALUE_4=https://github.com/hiddify/wireguard-go
  GIT_CONFIG_KEY_5=url.file://$repo_root/hiddify-core/ray2sing.insteadOf
  GIT_CONFIG_VALUE_5=https://github.com/hiddify/ray2sing.git
  GIT_SSH_COMMAND=false
  SSH_AUTH_SOCK=
  GIT_TERMINAL_PROMPT=0
)

env "${bootstrap_git_env[@]}" bash "$bootstrap_root/scripts/apply_hiddify_core_patch.sh"
first_bootstrap_diff="$(git -C "$bootstrap_root/hiddify-core" diff --binary)"
env "${bootstrap_git_env[@]}" bash "$bootstrap_root/scripts/apply_hiddify_core_patch.sh"
second_bootstrap_diff="$(git -C "$bootstrap_root/hiddify-core" diff --binary)"
[[ "$first_bootstrap_diff" == "$second_bootstrap_diff" ]] || {
  echo "repeated local-control bootstrap changed the patched sources" >&2
  exit 1
}

[[ -e "$bootstrap_root/hiddify-core/ray2sing/.git" ]] || {
  echo "local-control bootstrap did not initialize ray2sing" >&2
  exit 1
}
actual_ray2sing_commit="$(git -C "$bootstrap_root/hiddify-core/ray2sing" rev-parse HEAD)"
[[ "$actual_ray2sing_commit" == "caf5e9ac03eaba54dc339319670748d32a073a39" ]] || {
  echo "ray2sing is at $actual_ray2sing_commit instead of its pinned commit" >&2
  exit 1
}
git -C "$bootstrap_root/hiddify-core" diff --exit-code -- .gitmodules

while read -r path commit; do
  actual_commit="$(git -C "$bootstrap_root/hiddify-core/hiddify-sing-box/$path" rev-parse HEAD)"
  [[ "$actual_commit" == "$commit" ]] || {
    echo "$path is at $actual_commit instead of pinned $commit" >&2
    exit 1
  }
done <<'COMMITS'
replace/tailscale 788aa623edebf3e9918919cee4c590b177c61ec4
replace/psiphon-quic-go 47042a7c2475c081b370b8c9da2c22525774b27b
replace/psiphon-tls 4af85c2fb9f25576c15ccdb71d8299581dcd47fd
replace/wireguard-go b12022450359150cfb54790bc7316dee899e2336
COMMITS
git -C "$bootstrap_root/hiddify-core/hiddify-sing-box" diff --exit-code -- .gitmodules

wrong_sha_root="$work_dir/wrong-sha-repo"
mkdir -p "$wrong_sha_root/scripts" "$wrong_sha_root/patches"
cp "$repo_root/scripts/apply_hiddify_core_patch.sh" "$wrong_sha_root/scripts/"
cp "$repo_root/patches/hiddify-core-local-control.patch.gz" "$wrong_sha_root/patches/"
git clone --quiet --no-hardlinks "$repo_root/hiddify-core" "$wrong_sha_root/hiddify-core"
wrong_sha="$(printf 'wrong bootstrap base\n' | env \
  GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
  GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
  git -C "$wrong_sha_root/hiddify-core" commit-tree \
    f2034de743b1ad775dba026f4e6e3c44cf7d9790^{tree} \
    -p f2034de743b1ad775dba026f4e6e3c44cf7d9790)"
git -C "$wrong_sha_root/hiddify-core" checkout --quiet --detach "$wrong_sha"
if env "${bootstrap_git_env[@]}" \
  bash "$wrong_sha_root/scripts/apply_hiddify_core_patch.sh" \
  >"$work_dir/wrong-sha.stdout" 2>"$work_dir/wrong-sha.stderr"; then
  echo "local-control bootstrap accepted an unexpected hiddify-core commit" >&2
  exit 1
fi
grep -Fq "expected hiddify-core commit f2034de743b1ad775dba026f4e6e3c44cf7d9790" \
  "$work_dir/wrong-sha.stderr" || {
    echo "local-control bootstrap rejected the wrong commit without the expected diagnostic" >&2
    cat "$work_dir/wrong-sha.stderr" >&2
    exit 1
  }

ruby - "$repo_root/.github/workflows/build.yml" "$repo_root" <<'RUBY'
require "yaml"
require "json"

repo_root = ARGV.fetch(1)
project = File.read(File.join(repo_root, "ios/Runner.xcodeproj/project.pbxproj"))
raise "Runner does not select AppIcon" unless project.include?("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
app_icon_dir = File.join(repo_root, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
app_icon = JSON.parse(File.read(File.join(app_icon_dir, "Contents.json"))).fetch("images").find do |image|
  image["idiom"] == "universal" && image["platform"] == "ios" && image["size"] == "1024x1024"
end
raise "AppIcon catalog has no universal 1024x1024 iOS icon" unless app_icon
png = File.binread(File.join(app_icon_dir, app_icon.fetch("filename")), 24)
raise "AppIcon is not a 1024x1024 PNG" unless png.start_with?("\x89PNG\r\n\x1a\n".b) && png.byteslice(16, 8).unpack("NN") == [1024, 1024]

workflow = YAML.load_file(ARGV.fetch(0))
core_channel = workflow.fetch("env").fetch("CORE_CHANNEL")
raise "unsigned and production builds must use release core while uploaded dev builds use draft" unless core_channel.include?("!inputs.upload-artifact || inputs.channel == 'prod'")
jobs = workflow.fetch("jobs")
test_steps = jobs.fetch("test").fetch("steps")
raise "analyzer ratchet is not part of test gate" unless test_steps.any? { |step| step["run"] == "bash scripts/check_analyzer_ratchet.sh" }
core_step = test_steps.find { |step| step["name"] == "Verify authenticated local control core" }
raise "authenticated core verification is missing" unless core_step
core_commands = core_step.fetch("run")
raise "core checkout initializes unrelated nested submodules" if core_commands.include?("--recursive hiddify-core")
raise "core checkout is missing" unless core_commands.include?("git submodule update --init hiddify-core")
core_environment = core_step.fetch("env")
raise "authenticated core bootstrap can use SSH" unless core_environment.fetch("GIT_SSH_COMMAND") == "false"
raise "authenticated core bootstrap can use an SSH agent" unless core_environment.fetch("SSH_AUTH_SOCK") == ""
raise "authenticated core bootstrap can prompt for credentials" unless core_environment.fetch("GIT_TERMINAL_PROMPT") == "0"

ios_build = jobs.fetch("ios-build")
raise "iOS build must wait for test gate" unless ios_build.fetch("needs") == "test"
ios_commands = ios_build.fetch("steps").map { |step| step["run"] }.compact.join("\n")
raise "iOS build does not initialize the pinned source" unless ios_commands.include?("git submodule update --init hiddify-core")
raise "iOS build does not use the source-built core" unless ios_commands.include?("make ios-prepare")
raise "unsigned release iOS build is missing" unless ios_commands.include?("flutter build ios --release --no-codesign")

build = jobs.fetch("build")
raise "build failures are still tolerated" if build["continue-on-error"]
unsigned_windows = build.fetch("steps").find { |step| step["name"] == "Build unsigned Windows" }
raise "unsigned Windows builds must skip MSIX" unless unsigned_windows&.fetch("run")&.include?("make windows-zip-release windows-exe-release")
raise "unsigned Windows path must run independently of artifact retention" unless unsigned_windows.fetch("if") == "${{ matrix.platform == 'windows' }}"
signed_jobs = YAML.load_file(File.join(repo_root, ".github/workflows/signed-release.yml")).fetch("jobs")
signed_build = signed_jobs.fetch("build").fetch("steps").find { |step| step["name"] == "Build ${{ matrix.platform }}" }
raise "signed Windows path must still build MSIX" unless signed_build.fetch("if").include?("inputs.upload-artifact")
upload_step = build.fetch("steps").find { |step| step["name"] == "Upload Artifact" }
raise "empty artifact uploads are still tolerated" unless upload_step.dig("with", "if-no-files-found") == "error"

["update-draft", "upload-release", "upload-to-testflight"].each do |job_name|
  publish_job = signed_jobs.fetch(job_name)
  needs = publish_job.fetch("needs")
  raise "#{job_name} is not gated by build and ios-build" unless needs == ["build", "unsigned-gates"]
  raise "#{job_name} does not require successful gates" unless publish_job.fetch("if").include?("success()")
end

["update-draft", "upload-release"].each do |job_name|
  names = signed_jobs.fetch(job_name).fetch("steps").map { |step| step["name"] }.compact
  check_index = names.index("Check release artifact manifest")
  mutation_indexes = names.each_index.select do |index|
    names[index].include?("Release") || names[index] == "Delete Current Release Assets"
  end
  raise "#{job_name} does not check artifacts" unless check_index
  raise "#{job_name} mutates a release before artifact validation" unless mutation_indexes.all? { |index| check_index < index }
end

# Security boundaries are checked across every active workflow action/job.
Dir.glob(File.join(repo_root, ".github/workflows/*.yml")).each do |path|
  document = YAML.load_file(path)
  raise "#{path} has ambient token permissions" unless document.fetch("permissions") == {}
  document.fetch("jobs").each do |name, job|
    raise "#{path}:#{name} inherits every secret" if job["secrets"] == "inherit"
    permissions = job.fetch("permissions")
    raise "#{path}:#{name} grants write-all" unless permissions.is_a?(Hash)
    (job["steps"] || []).each do |step|
      action = step["uses"]
      next unless action
      raise "#{path}: mutable action #{action}" unless action.match?(/\A[^@]+@[0-9a-f]{40}\z/)
      if action.start_with?("actions/checkout@")
        raise "#{path}: persisted checkout credential" unless step.dig("with", "persist-credentials") == false
      end
    end
  end
end
unsigned_text = File.read(ARGV.fetch(0))
raise "unsigned CI references secrets" if unsigned_text.include?("secrets.")
jobs.each do |name, job|
  raise "unsigned #{name} can write" unless job.fetch("permissions") == {"contents" => "read"}
  raise "unsigned #{name} enters secret environment" if job.key?("environment")
end
raise "signing lacks separate environment" unless signed_jobs.fetch("build").fetch("environment") == "release-signing"
raise "signing token can write" unless signed_jobs.fetch("build").fetch("permissions") == {"contents" => "read"}
raise "signing can run on PRs" unless signed_jobs.fetch("build").fetch("if").include?("github.event_name == 'push' && github.ref_type == 'tag'")
raise "signing does not wait for unsigned gates" unless signed_jobs.fetch("build").fetch("needs") == "unsigned-gates"
["update-draft", "upload-release", "upload-to-testflight"].each do |name|
  raise "#{name} lacks publish environment" unless signed_jobs.fetch(name).fetch("environment") == "release-publish"
end
RUBY

echo "release gate checks passed"
