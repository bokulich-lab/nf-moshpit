#!/bin/bash
# restore_cache.sh - Restore archived QIIME 2 sample caches for workflow resume
#
# Usage:
#   ./bin/restore_cache.sh <archive_dir> <caches_dir> [sample_id ...]
#
# Arguments:
#   archive_dir   Directory containing .zip archives (e.g. results/archives)
#   caches_dir    Directory where caches should be restored (e.g. results/caches)
#   sample_id     Optional: one or more sample IDs to restore (default: all)
#
# Examples:
#   # Restore all archived samples, then resume
#   ./bin/restore_cache.sh results/archives results/caches
#   nextflow run main.nf -resume
#
#   # Restore specific samples only
#   ./bin/restore_cache.sh results/archives results/caches SRR123456 SRR789012

set -euo pipefail

if [ $# -lt 2 ]; then
    echo "Usage: $0 <archive_dir> <caches_dir> [sample_id ...]"
    echo ""
    echo "Arguments:"
    echo "  archive_dir   Directory containing .zip archives"
    echo "  caches_dir    Directory where caches should be restored to"
    echo "  sample_id     Optional: specific sample IDs to restore (default: all)"
    exit 1
fi

ARCHIVE_DIR="$1"
CACHES_DIR="$2"
shift 2

if [ ! -d "$ARCHIVE_DIR" ]; then
    echo "ERROR: Archive directory does not exist: $ARCHIVE_DIR"
    exit 1
fi

mkdir -p "$CACHES_DIR"

# Determine which samples to restore
if [ $# -gt 0 ]; then
    SAMPLES=("$@")
else
    SAMPLES=()
    for archive in "$ARCHIVE_DIR"/*.zip; do
        [ -f "$archive" ] || continue
        sample=$(basename "$archive" .zip)
        SAMPLES+=("$sample")
    done
fi

if [ ${#SAMPLES[@]} -eq 0 ]; then
    echo "No archives found in $ARCHIVE_DIR"
    exit 0
fi

echo "Restoring ${#SAMPLES[@]} sample cache(s)..."
echo ""

restored=0
failed=0
skipped=0

for sample_id in "${SAMPLES[@]}"; do
    archive="$ARCHIVE_DIR/${sample_id}.zip"
    echo "Archive: $archive"

    if [ ! -f "$archive" ]; then
        echo "  WARNING: Archive not found for sample ${sample_id}: $archive"
        failed=$((failed + 1))
        continue
    fi

    if [ -d "$CACHES_DIR/${sample_id}" ]; then
        echo "  SKIP: Cache already exists for sample ${sample_id}"
        skipped=$((skipped + 1))
        continue
    fi

    echo "  Restoring ${sample_id}..."

    # Verify archive integrity before extracting
    if ! unzip -tq "$archive" > /dev/null 2>&1; then
        echo "  ERROR: Archive integrity check failed for ${sample_id}"
        failed=$((failed + 1))
        continue
    fi

    # Extract archive
    unzip -q "$archive" -d "$CACHES_DIR/"

    if [ -d "$CACHES_DIR/${sample_id}" ]; then
        echo "  OK: Restored ${sample_id}"
        restored=$((restored + 1))
    else
        echo "  ERROR: Extraction failed for ${sample_id}"
        failed=$((failed + 1))
    fi
done

echo ""
echo "=== Restore Summary ==="
echo "Restored: ${restored}"
echo "Skipped:  ${skipped}"
echo "Failed:   ${failed}"
echo "======================="

if [ $failed -gt 0 ]; then
    echo "ERROR: Failed to restore some caches"
    exit 1
fi
