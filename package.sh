#!/usr/bin/env bash
# Zip a skill directory into release/<skill-name>.skill for upload to Claude
# Desktop or a GitHub release.
# Usage: ./package.sh <skill-dir>
set -euo pipefail

skill_dir="${1:?Usage: ./package.sh <skill-dir>}"
skill_dir="${skill_dir%/}"
skill_name="$(basename "$skill_dir")"

if [ ! -f "$skill_dir/SKILL.md" ]; then
  echo "error: $skill_dir/SKILL.md not found" >&2
  exit 1
fi

mkdir -p release
out="release/${skill_name}.skill"
rm -f "$out"

if command -v zip >/dev/null 2>&1; then
  (cd "$skill_dir" && zip -r "../$out" . -x '.*')
else
  # Windows fallback: PowerShell's Compress-Archive stores entry paths with
  # backslashes, which violates the ZIP spec and gets rejected by stricter
  # readers (Claude Desktop's uploader among them). Build the archive via
  # .NET's ZipArchive API directly instead, forcing forward-slash entries.
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    \$srcRoot = (Resolve-Path '$skill_dir').Path
    \$outPath = Join-Path (Get-Location) '$out'
    if (Test-Path \$outPath) { Remove-Item \$outPath }
    \$fs = [System.IO.File]::Open(\$outPath, [System.IO.FileMode]::Create)
    \$archive = New-Object System.IO.Compression.ZipArchive(\$fs, [System.IO.Compression.ZipArchiveMode]::Create)
    Get-ChildItem -Path \$srcRoot -Recurse -File | ForEach-Object {
      \$relPath = \$_.FullName.Substring(\$srcRoot.Length + 1).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
      \$entry = \$archive.CreateEntry(\$relPath, [System.IO.Compression.CompressionLevel]::Optimal)
      \$entryStream = \$entry.Open()
      \$fileStream = [System.IO.File]::OpenRead(\$_.FullName)
      \$fileStream.CopyTo(\$entryStream)
      \$fileStream.Close()
      \$entryStream.Close()
    }
    \$archive.Dispose()
    \$fs.Close()
  "
fi

echo "wrote $out"
