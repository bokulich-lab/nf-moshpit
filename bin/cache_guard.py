#!/usr/bin/env python3
"""Refuse unsafe reuse of persistent QIIME caches and marker outputs.

Fingerprints are immutable for an output directory. SHA256 reads input bytes,
not mtimes, so replacing a file at its original path is detected. Cache receipts
record artifact UUIDs after each run; markers alone never authorize a resume.
"""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile

IGNORED = {'timestamp', 'traceDir', 'archiveDir', 'containerCacheDir', 'tmpDir',
           'overall_cpu_scale', 'overall_mem_scale', 'overall_time_scale',
           'cpu_intensive_task_multiplier', 'mem_intensive_task_multiplier',
           'cpu_multiplier', 'mem_multiplier', 'time_multiplier', 'archive',
           'provenance_dedup'}


def digest(path):
    result = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def identity(path):
    path = Path(path).expanduser().resolve(strict=True)
    if path.is_file():
        return {'path': str(path), 'sha256': digest(path)}
    return {'path': str(path), 'files': {str(p.relative_to(path)): digest(p)
            for p in sorted(path.rglob('*')) if p.is_file()}}


def artifact(key):
    text = key.read_text()
    match = re.search(r'^\s*data\s*:\s*[\'\"]?([a-zA-Z0-9-]+)', text, re.M)
    if not match:
        raise ValueError(f'Invalid artifact key metadata: {key}')
    uuid = match[1]
    artifact_dir = key.parent.parent / 'data' / uuid
    if not (artifact_dir / 'data').is_dir() or not any((artifact_dir / 'data').rglob('*')):
        raise ValueError(f'Cache key {key} has no artifact data at {artifact_dir}; restore the cache before resuming')
    return uuid


def cache_keys(params):
    # Output caches belong to this run. Shared database caches may contain
    # unrelated entries and pools; inspect only configured database keys there.
    roots = {Path(params[k]).resolve() for k in ['q2cacheDir', 'q2TemporaryCachesDir']}
    candidates = set()
    for root in roots:
        if root.exists():
            candidates.update(root.rglob('keys/*'))
    for db in params.get('databases', {}).values():
        if isinstance(db, dict) and db.get('cache') and db.get('key'):
            candidates.add(Path(db['cache']).resolve() / 'keys' / db['key'])
    keys = {}
    for key in candidates:
        if key.is_file() and re.search(r'^\s*data\s*:', key.read_text(), re.M):
            keys[str(key.resolve())] = artifact(key)
    return keys


def signature(params, source):
    config = {k: v for k, v in params.items() if k not in IGNORED}
    inputs = {}
    for name in ['inputReadsManifest', 'metadata', 'fondueAccessionIds']:
        value = params.get(name)
        if value and str(value).lower() != 'null':
            inputs[name] = identity(value)
    manifest = params.get('inputReadsManifest')
    if manifest:
        with open(manifest, newline='') as stream:
            for row in csv.DictReader(stream):
                for column in ['forward', 'reverse']:
                    if row.get(column, '').strip():
                        inputs[row[column]] = identity(row[column])
    samples = params.get('read_simulation', {}).get('samples')
    if samples:
        inputs['simulation'] = identity(samples)
        with open(samples, newline='') as stream:
            for row in csv.DictReader(stream):
                for column in ['genomesPath']:
                    if row.get(column, '').strip():
                        inputs[row[column]] = identity(row[column])
    if params.get('inputReads') and params.get('inputReadsCache'):
        key = Path(params['inputReadsCache']) / 'keys' / params['inputReads']
        uuid = artifact(key)
        inputs['cached_reads'] = {'uuid': uuid, 'artifact': identity(key.parent.parent / 'data' / uuid)}
    files = [p for p in source.rglob('*') if p.is_file() and
             '.git' not in p.parts and p.relative_to(source).parts[0] in {'main.nf', 'nextflow.config', 'modules', 'subworkflows', 'conf', 'bin'} and (p.suffix in {'.nf', '.config'} or p.parent == source / 'bin')]
    payload = {'config': config, 'inputs': inputs,
               'workflow': {str(p.relative_to(source)): digest(p) for p in sorted(files)}}
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()


def atomic_json(path, data):
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as stream:
        json.dump(data, stream, sort_keys=True, indent=2)
        temp = stream.name
    os.replace(temp, path)


def guard(params, source, finish=False):
    output = Path(params['outputDir']).resolve()
    state_path = output / '.moshpit-cache-identity.json'
    if finish:
        if state_path.exists():
            state = json.loads(state_path.read_text())
            state['artifacts'] = cache_keys(params)
            atomic_json(state_path, state)
        return
    current = signature(params, source)
    if state_path.exists():
        state = json.loads(state_path.read_text())
        if state['signature'] != current:
            raise ValueError('Input bytes, effective configuration or workflow source changed. Use a new outputDir (and new storeDir/cache paths) to recompute; do not delete the guard file.')
        for name, uuid in state.get('artifacts', {}).items():
            key = Path(name)
            if not key.is_file() or artifact(key) != uuid:
                raise ValueError(f'Previously completed cache artifact changed or is missing: {key}. Restore the original caches or use a new outputDir.')
        cache_keys(params)  # Also validate any artifacts left by an interrupted run.
    else:
        persistent = [output, Path(params['storeDir']), Path(params['q2cacheDir']), Path(params['q2TemporaryCachesDir'])]
        if any(root.exists() and any(p.resolve() != Path(params.get('traceDir', output / 'pipeline_info')).resolve() for p in root.iterdir()) for root in persistent):
            raise ValueError('Existing outputs have no cache identity guard. Use a new empty outputDir and empty storeDir/cache paths; legacy markers cannot prove compatible results.')
        output.mkdir(parents=True, exist_ok=True)
        atomic_json(state_path, {'signature': current, 'artifacts': {}})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--params', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--finish', action='store_true')
    args = parser.parse_args()
    try:
        guard(json.loads(args.params.read_text()), args.source, args.finish)
    except (ValueError, OSError, KeyError) as error:
        sys.exit(f'Unsafe cache reuse: {error}')


if __name__ == '__main__':
    main()
