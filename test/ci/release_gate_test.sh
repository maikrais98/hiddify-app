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
release_ios_digest="$(awk -F= '$1 == "core.release.sha256.ios" { print $2 }' "$repo_root/dependencies.properties")"
draft_ios_digest="$(awk -F= '$1 == "core.draft.sha256.ios" { print $2 }' "$repo_root/dependencies.properties")"
release_core_recipe="$(make --no-print-directory -n -C "$repo_root" CHANNEL=dev CORE_CHANNEL=release ios-libs)"
draft_core_recipe="$(make --no-print-directory -n -C "$repo_root" CHANNEL=dev CORE_CHANNEL=draft ios-libs)"
[[ "$release_core_recipe" == *"/v$core_version/hiddify-lib-ios.tar.gz"* && "$release_core_recipe" == *"$release_ios_digest"* ]] || {
  echo "release core override does not select the versioned archive and digest" >&2
  exit 1
}
[[ "$draft_core_recipe" == *"/draft/hiddify-lib-ios.tar.gz"* && "$draft_core_recipe" == *"$draft_ios_digest"* ]] || {
  echo "draft core override does not select the draft archive and digest" >&2
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

ios_build = jobs.fetch("ios-build")
raise "iOS build must wait for test gate" unless ios_build.fetch("needs") == "test"
ios_commands = ios_build.fetch("steps").map { |step| step["run"] }.compact.join("\n")
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
