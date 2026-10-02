#!/usr/bin/env python
"""Export artifact-backed metadata without propagating its artifact ancestry."""
import argparse
import json
import os
from pathlib import Path
import tempfile

from qiime2 import Artifact, Cache, Metadata
from checkpoint_artifact import sha256


def export_metadata(cache_path, key, output_dir, archive_dir, sample_id, context):
    output_dir = Path(output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    tsv_name = f'{key}.tsv'
    archive_name = f'{key}.metadata-source.qza'
    record_name = f'{key}.metadata.json'
    cache = Cache(cache_path)
    with cache, tempfile.TemporaryDirectory(prefix='metadata-', dir=output_dir) as temporary:
        temporary = Path(temporary)
        artifact = cache.load(key)
        metadata = artifact.view(Metadata)
        metadata.save(str(temporary / tsv_name))
        restored = Metadata.load(str(temporary / tsv_name))
        if not restored.to_dataframe().equals(metadata.to_dataframe()):
            raise ValueError('Exported metadata values changed')
        if restored.columns != metadata.columns or restored.artifacts:
            raise ValueError('Exported metadata types changed or ancestry was retained')
        archived = artifact.save(str(temporary / archive_name))
        Artifact.load(archived).validate()
        record = {
            'schema_version': 1,
            'operation': 'artifact-metadata-to-tsv',
            'sample_id': sample_id,
            'context': context,
            'source_cache': str(Path(cache_path).resolve()),
            'source_key': key,
            'source_uuid': str(artifact.uuid),
            'source_type': str(artifact.type),
            'source_archive': str(Path(archive_dir) / archive_name),
            'source_archive_sha256': sha256(archived),
            'metadata_file': tsv_name,
            'metadata_sha256': sha256(temporary / tsv_name),
            'column_types': {name: properties.type for name, properties in metadata.columns.items()},
        }
        (temporary / record_name).write_text(json.dumps(record, indent=2) + '\n')
        for name in [tsv_name, archive_name, record_name]:
            os.replace(temporary / name, output_dir / name)
        return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', required=True)
    parser.add_argument('--key', required=True)
    parser.add_argument('--output-dir', default='.')
    parser.add_argument('--archive-dir', required=True)
    parser.add_argument('--sample-id', required=True)
    parser.add_argument('--context', required=True)
    args = parser.parse_args()
    export_metadata(args.cache, args.key, args.output_dir, args.archive_dir,
                    args.sample_id, args.context)


if __name__ == '__main__':
    main()
