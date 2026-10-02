#!/usr/bin/env python
"""Create a provenance checkpoint using the public QIIME 2 artifact/cache API."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile

import qiime2
from qiime2 import Artifact, Cache


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def payload_checksums(directory):
    return {path.relative_to(directory).as_posix(): sha256(path)
            for path in sorted(Path(directory).rglob('*')) if path.is_file()}


def checkpoint(cache_path, input_key, output_key, output_dir, archive_dir, run_id):
    if input_key == output_key:
        raise ValueError('A checkpoint must use a new cache key')
    output_dir = Path(output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    upstream_path = output_dir / f'{output_key}.upstream.qza'
    checkpoint_path = output_dir / f'{output_key}.qza'
    record_path = output_dir / f'{output_key}.json'
    cache = Cache(cache_path)
    with cache:
        original = cache.load(input_key)
        # A retry can restore the same verified checkpoint UUID from its real file.
        if record_path.exists() and checkpoint_path.exists() and upstream_path.exists():
            record = json.loads(record_path.read_text())
            if (record['original_uuid'] == str(original.uuid)
                    and record['checkpoint_key'] == output_key
                    and record['run_id'] == run_id
                    and record['archive_location'] == str(Path(archive_dir) / upstream_path.name)
                    and record['archive_sha256'] == sha256(upstream_path)
                    and record['checkpoint_sha256'] == sha256(checkpoint_path)):
                restored = Artifact.load(str(checkpoint_path))
                restored.validate()
                if str(restored.uuid) != record['checkpoint_uuid']:
                    raise ValueError('Checkpoint UUID does not match its record')
                cache.save(restored, output_key)
                (output_dir / output_key).write_text(record['checkpoint_uuid'] + '\n')
                return record
        with tempfile.TemporaryDirectory(prefix='checkpoint-', dir=output_dir) as temporary:
            temporary = Path(temporary)
            # Preserve a fully loadable artifact before changing the lineage.
            archived = original.save(str(temporary / upstream_path.name))
            Artifact.load(archived).validate()
            original.export_data(str(temporary / 'payload'))
            checksums = payload_checksums(temporary / 'payload')
            fresh = Artifact.import_data(original.type, temporary / 'payload',
                                         view_type=original.format)
            fresh.export_data(str(temporary / 'verified'))
            if fresh.type != original.type or fresh.format != original.format:
                raise ValueError('Checkpoint type or format changed')
            if checksums != payload_checksums(temporary / 'verified'):
                raise ValueError('Checkpoint payload changed')
            archive_location = str(Path(archive_dir) / upstream_path.name)
            if hasattr(qiime2, 'Note'):
                fresh.add_annotation(qiime2.Note(
                    'Upstream_provenance',
                    text=f'Original UUID: {original.uuid}; archive: {archive_location}; '
                         f'record: {Path(archive_dir) / record_path.name}'))
            saved = fresh.save(str(temporary / checkpoint_path.name))
            Artifact.load(saved).validate()
            record = {
                'schema_version': 1,
                'operation': 'export-import-provenance-checkpoint',
                'run_id': run_id,
                'original_cache': str(Path(cache_path).resolve()),
                'original_key': input_key,
                'original_uuid': str(original.uuid),
                'checkpoint_key': output_key,
                'checkpoint_uuid': str(fresh.uuid),
                'semantic_type': str(original.type),
                'directory_format': original.format.__name__,
                'archive_location': archive_location,
                'archive_sha256': sha256(archived),
                'checkpoint_sha256': sha256(saved),
                'payload_sha256': checksums,
            }
            (temporary / record_path.name).write_text(json.dumps(record, indent=2) + '\n')
            # Atomic file replacement; the marker is only written after cache-save succeeds.
            for destination in [upstream_path, checkpoint_path, record_path]:
                os.replace(temporary / destination.name, destination)
            cache.save(fresh, output_key)
            (output_dir / output_key).write_text(str(fresh.uuid) + '\n')
            return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', required=True)
    parser.add_argument('--input-key', required=True)
    parser.add_argument('--output-key', required=True)
    parser.add_argument('--output-dir', default='.')
    parser.add_argument('--archive-dir', required=True)
    parser.add_argument('--run-id', required=True)
    args = parser.parse_args()
    checkpoint(args.cache, args.input_key, args.output_key, args.output_dir,
               args.archive_dir, args.run_id)


if __name__ == '__main__':
    main()
