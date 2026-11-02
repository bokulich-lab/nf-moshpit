#!/usr/bin/env python3
"""Losslessly deduplicate identical provenance files in offline QIIME 2 caches.

Dry run by default. Stop every job using the selected caches before --apply.
Only regular files below data/<artifact UUID>/provenance/ are candidates.
Scientific payloads, artifact UUIDs, cache keys, and provenance bytes are preserved.
The SQLite index lives in a temporary directory, preferably on local scratch.
"""
import argparse
from contextlib import closing, contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import signal
import sqlite3
import stat
import sys
import tempfile
import uuid


class Audit:
    def __init__(self, path):
        self.handle = Path(path).open('x', encoding='utf-8') if path else None

    def write(self, event, **values):
        if self.handle:
            self.handle.write(json.dumps({'event': event,
                                          'time_utc': datetime.now(timezone.utc).isoformat(),
                                          **values}, sort_keys=True) + '\n')
            self.handle.flush()

    def close(self):
        if self.handle:
            self.handle.close()


def directories(path):
    with os.scandir(path) as entries:
        return sorted(Path(entry.path) for entry in entries
                      if entry.is_dir(follow_symlinks=False))


def find_caches(roots, excluded):
    seen = set()
    pending = list(roots)
    while pending:
        path = pending.pop()
        if path in seen or any(path == p or p in path.parents for p in excluded):
            continue
        seen.add(path)
        version = path / 'VERSION'
        if version.is_file() and not version.is_symlink():
            lines = version.read_text().splitlines()
            if len(lines) >= 2 and lines[0] == 'QIIME 2' and lines[1].startswith('cache:'):
                if lines[1] != 'cache: 1':
                    raise ValueError(f'Unsupported cache format: {path}: {lines[1]}')
                if not all((path / name).is_dir() and not (path / name).is_symlink()
                           for name in ['data', 'keys', 'pools', 'processes']):
                    raise ValueError(f'Incomplete or symlinked cache layout: {path}')
                yield path
                continue
        pending.extend(directories(path))


def provenance_roots(cache):
    for artifact in directories(cache / 'data'):
        try:
            if str(uuid.UUID(artifact.name)) != artifact.name:
                continue
        except ValueError:
            continue
        provenance = artifact / 'provenance'
        if provenance.is_dir() and not provenance.is_symlink():
            yield provenance


def count_cache_inodes(caches, database):
    """Count all unique cache inodes without following symlinks or filling RAM."""
    database.execute('''CREATE TEMP TABLE IF NOT EXISTS inode_inventory (
        device TEXT, inode TEXT, PRIMARY KEY(device, inode)) WITHOUT ROWID''')
    database.execute('DELETE FROM inode_inventory')

    def inode_ids():
        for cache in caches:
            info = cache.lstat()
            yield str(info.st_dev), str(info.st_ino)
            pending = [cache]
            while pending:
                with os.scandir(pending.pop()) as entries:
                    for entry in entries:
                        info = entry.stat(follow_symlinks=False)
                        yield str(info.st_dev), str(info.st_ino)
                        if stat.S_ISDIR(info.st_mode):
                            pending.append(Path(entry.path))

    database.executemany('INSERT OR IGNORE INTO inode_inventory VALUES (?, ?)', inode_ids())
    total = database.execute('SELECT COUNT(*) FROM inode_inventory').fetchone()[0]
    database.commit()
    return total


def walk_provenance(root, summary):
    pending = [root]
    while pending:
        directory = pending.pop()
        summary['provenance_directories'] += 1
        with os.scandir(directory) as iterator:
            entries = sorted(iterator, key=lambda entry: entry.name)
        for entry in entries:
            if entry.is_dir(follow_symlinks=False):
                pending.append(Path(entry.path))
            elif entry.is_file(follow_symlinks=False):
                summary['provenance_file_paths'] += 1
                yield Path(entry.path)
            else:
                summary['nonregular_entries_skipped'] += 1


def signature(info):
    # Link count and ctime necessarily change as links are added/removed.
    return (info.st_dev, info.st_ino, info.st_size, info.st_mode,
            info.st_uid, info.st_gid, info.st_mtime_ns, getattr(info, 'st_flags', 0))


def xattrs(path):
    if not hasattr(os, 'listxattr'):
        raise OSError('This platform cannot compare extended file attributes')
    return tuple((name, os.getxattr(path, name, follow_symlinks=False))
                 for name in sorted(os.listxattr(path, follow_symlinks=False)))


def digest(path, expected):
    result = hashlib.sha256()
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, 'rb') as handle:
        if signature(os.fstat(handle.fileno())) != signature(expected):
            raise RuntimeError(f'File changed while scanning: {path}')
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            result.update(block)
        if signature(os.fstat(handle.fileno())) != signature(expected):
            raise RuntimeError(f'File changed while hashing: {path}')
    return result.hexdigest()


def group_key(info, attributes, checksum, ignore_mtime=False, ignore_lustre_layout=False):
    # Preserve owner, group, mode, mtime, flags, and ACLs/xattrs. Never cross devices.
    values = [info.st_dev, info.st_size, info.st_mode, info.st_uid, info.st_gid,
              None if ignore_mtime else info.st_mtime_ns, getattr(info, 'st_flags', 0),
              [(name, value.hex()) for name, value in attributes
               if not (ignore_lustre_layout and name == 'lustre.lov')], checksum]
    return json.dumps(values, separators=(',', ':'))


def equal_bytes(first, second):
    # Byte comparison as well as SHA-256 grouping, with no symlink following.
    with os.fdopen(os.open(first, os.O_RDONLY | os.O_NOFOLLOW), 'rb') as a:
        with os.fdopen(os.open(second, os.O_RDONLY | os.O_NOFOLLOW), 'rb') as b:
            while True:
                left, right = a.read(1024 * 1024), b.read(1024 * 1024)
                if left != right:
                    return False
                if not left:
                    return True


def diagnose_provenance(caches, audit, limit):
    """Bounded read-only comparison of contents first, then metadata.

    Compare each distinct inode with the first file having the same size/hash.
    Counts describe those pairs, not independent or additive inode savings.
    Never expose file contents or extended-attribute values in the report.
    """
    summary = dict(mode='diagnose', caches=[str(p) for p in caches],
                   scan_limit_files=limit, scan_stopped_at_limit=False,
                   provenance_directories=0, provenance_file_paths=0,
                   nonregular_entries_skipped=0, attribute_or_owner_skips=0,
                   distinct_file_inodes_scanned=0, duplicate_content_inodes=0,
                   metadata_difference_counts={}, xattr_difference_counts={},
                   examples=[])
    seen, contents = set(), {}
    names = ['device', 'size', 'mode', 'uid', 'gid', 'mtime_ns', 'stat_flags']
    for cache in caches:
        for root in provenance_roots(cache):
            for path in walk_provenance(root, summary):
                info = path.lstat()
                if not stat.S_ISREG(info.st_mode):
                    raise RuntimeError(f'File changed during scan: {path}')
                inode = (info.st_dev, info.st_ino)
                if inode not in seen:
                    seen.add(inode)
                    try:
                        if info.st_uid != os.geteuid():
                            raise PermissionError('File belongs to another user')
                        attributes = xattrs(path)
                    except OSError as error:
                        summary['attribute_or_owner_skips'] += 1
                        audit.write('skipped', path=str(path), reason=str(error))
                    else:
                        checksum = digest(path, info)
                        summary['distinct_file_inodes_scanned'] += 1
                        content_key = (info.st_size, checksum)
                        metadata = json.loads(group_key(info, attributes, checksum))
                        first = contents.get(content_key)
                        if first is None:
                            contents[content_key] = (path, metadata)
                        else:
                            first_path, first_metadata = first
                            if not equal_bytes(first_path, path):
                                raise RuntimeError(f'Matching hashes but different bytes: {first_path}, {path}')
                            summary['duplicate_content_inodes'] += 1
                            differences = {name: [left, right] for name, left, right
                                           in zip(names, first_metadata[:7], metadata[:7])
                                           if left != right}
                            left_attrs, right_attrs = dict(first_metadata[7]), dict(metadata[7])
                            differing_attrs = sorted(name for name in left_attrs.keys() | right_attrs.keys()
                                                     if left_attrs.get(name) != right_attrs.get(name))
                            if differing_attrs:
                                differences['xattrs'] = differing_attrs
                            for name in differences:
                                counts = summary['metadata_difference_counts']
                                counts[name] = counts.get(name, 0) + 1
                            for name in differing_attrs:
                                counts = summary['xattr_difference_counts']
                                counts[name] = counts.get(name, 0) + 1
                            if differences and len(summary['examples']) < 5:
                                summary['examples'].append(dict(first_path=str(first_path),
                                                               other_path=str(path), sha256=checksum,
                                                               differences=differences))
                if summary['provenance_file_paths'] >= limit:
                    summary['scan_stopped_at_limit'] = True
                    return summary
    return summary


@contextmanager
def writable_parent(path):
    parent = path.parent
    info = parent.lstat()
    if not stat.S_ISDIR(info.st_mode):
        raise RuntimeError(f'Parent directory changed: {parent}')
    mode = stat.S_IMODE(info.st_mode)
    changed = not (mode & stat.S_IWUSR)
    if changed:
        if info.st_uid != os.geteuid():
            raise PermissionError(f'Cannot temporarily enable writes on {parent}')
        os.chmod(parent, mode | stat.S_IWUSR)
    try:
        yield
    finally:
        if changed:
            os.chmod(parent, mode)


def replace_with_link(source, destination, expected, key, audit, ignore_mtime=False,
                      ignore_lustre_layout=False):
    source_info = source.lstat()
    destination_info = destination.lstat()
    if signature(destination_info) != signature(expected):
        raise RuntimeError(f'Destination changed before linking: {destination}')
    source_attributes = xattrs(source)
    destination_attributes = xattrs(destination)
    if (not stat.S_ISREG(source_info.st_mode)
            or group_key(source_info, source_attributes, digest(source, source_info),
                         ignore_mtime, ignore_lustre_layout) != key
            or group_key(destination_info, destination_attributes, digest(destination, destination_info),
                         ignore_mtime, ignore_lustre_layout) != key
            or not equal_bytes(source, destination)):
        raise RuntimeError(f'Files no longer match: {source}, {destination}')
    temporary = destination.parent / f'.provenance-link-{uuid.uuid4()}'
    ignored_attributes = {}
    if ignore_lustre_layout:
        # Record which storage metadata was disregarded without logging raw values.
        source_layout = dict(source_attributes).get('lustre.lov')
        destination_layout = dict(destination_attributes).get('lustre.lov')
        ignored_attributes['lustre.lov'] = dict(
            old_sha256=hashlib.sha256(destination_layout).hexdigest() if destination_layout is not None else None,
            shared_sha256=hashlib.sha256(source_layout).hexdigest() if source_layout is not None else None)
    audit.write('link_intent', source=str(source), destination=str(destination),
                sha256=json.loads(key)[-1], old_inode=expected.st_ino,
                device=expected.st_dev, shared_inode=source_info.st_ino,
                old_mtime_ns=expected.st_mtime_ns, shared_mtime_ns=source_info.st_mtime_ns,
                ignored_xattrs=ignored_attributes)
    with writable_parent(destination):
        try:
            os.link(source, temporary, follow_symlinks=False)
            # A failed link or check leaves the original path intact.
            if (signature(temporary.lstat()) != signature(source_info)
                    or signature(destination.lstat()) != signature(expected)):
                raise RuntimeError(f'File changed during linking: {destination}')
            os.replace(temporary, destination)
        finally:
            if temporary.exists():
                temporary.unlink()
    audit.write('linked', source=str(source), destination=str(destination))


def deduplicate(roots, *, apply=False, report=None, scratch_dir=None,
                excluded=(), max_links=10000, ignore_mtime=False,
                diagnose=False, diagnostic_limit=1000, ignore_lustre_layout=False):
    if diagnose and apply:
        raise ValueError('--diagnose cannot be combined with --apply')
    if diagnostic_limit < 1:
        raise ValueError('--diagnostic-limit must be at least 1')
    if apply and report is None:
        raise ValueError('--apply requires a new --report path')
    if max_links < 2:
        raise ValueError('--max-links must be at least 2')
    roots = [Path(root).resolve(strict=True) for root in roots]
    excluded = [Path(path).resolve() for path in excluded]
    for root in roots:
        if not root.is_dir():
            raise ValueError(f'Not a directory: {root}')
    caches = list(find_caches(roots, excluded))
    if not caches:
        raise ValueError('No supported QIIME 2 caches found')
    if report:
        resolved = Path(report).resolve()
        if any(cache == resolved or cache in resolved.parents for cache in caches):
            raise ValueError('Write the audit report outside the selected caches')
    audit = Audit(report)
    summary = dict(mode='apply' if apply else 'dry-run', caches=[str(p) for p in caches],
                   ignore_mtime=ignore_mtime,
                   ignore_lustre_layout=ignore_lustre_layout,
                   ignored_xattrs=['lustre.lov'] if ignore_lustre_layout else [],
                   provenance_directories=0, provenance_file_paths=0,
                   nonregular_entries_skipped=0, attribute_or_owner_skips=0,
                   candidate_paths=0, linked_paths=0)
    try:
        if diagnose:
            audit.write('start', mode='diagnose', scan_limit_files=diagnostic_limit, tool_version=4)
            summary = diagnose_provenance(caches, audit, diagnostic_limit)
            audit.write('complete', **summary)
            return summary
        audit.write('start', **summary, max_links=max_links, tool_version=4)
        with tempfile.TemporaryDirectory(prefix='provenance-dedup-', dir=scratch_dir) as temporary:
            with closing(sqlite3.connect(str(Path(temporary) / 'index.sqlite'))) as database:
                database.executescript('''
                    CREATE TABLE inodes (
                        device TEXT, inode TEXT, links INTEGER, replaced INTEGER DEFAULT 0,
                        fingerprint TEXT, checksum TEXT, content_fingerprint TEXT,
                        PRIMARY KEY(device, inode));
                    CREATE TABLE canonical (
                        fingerprint TEXT PRIMARY KEY, path TEXT, device TEXT, inode TEXT, links INTEGER);
                ''')
                summary['inode_count_scope'] = 'selected_caches'
                summary['total_inodes_before'] = count_cache_inodes(caches, database)
                audit.write('inode_count_before', total_inodes=summary['total_inodes_before'])
                for cache in caches:
                    audit.write('cache', path=str(cache))
                    candidates_before = summary['candidate_paths']
                    for root in provenance_roots(cache):
                        for path in walk_provenance(root, summary):
                            info = path.lstat()
                            if not stat.S_ISREG(info.st_mode):
                                raise RuntimeError(f'File changed during scan: {path}')
                            # Some HPC filesystems expose unsigned 64-bit inode IDs,
                            # which exceed SQLite's signed INTEGER range.
                            inode_id = (str(info.st_dev), str(info.st_ino))
                            row = database.execute('SELECT fingerprint, checksum FROM inodes WHERE device=? AND inode=?',
                                                   inode_id).fetchone()
                            if row:
                                key, checksum = row
                            else:
                                # Do not consolidate files belonging to other users.
                                try:
                                    if info.st_uid != os.geteuid():
                                        raise PermissionError('File belongs to another user')
                                    attributes = xattrs(path)
                                except OSError as error:
                                    summary['attribute_or_owner_skips'] += 1
                                    audit.write('skipped', path=str(path), reason=str(error))
                                    continue
                                checksum = digest(path, info)
                                key = group_key(info, attributes, checksum, ignore_mtime, ignore_lustre_layout)
                                content_key = group_key(info, attributes, checksum, True, ignore_lustre_layout)
                                database.execute('INSERT INTO inodes VALUES (?, ?, ?, 0, ?, ?, ?)',
                                                 inode_id + (info.st_nlink, key, checksum, content_key))
                            canonical = database.execute('SELECT path, device, inode, links FROM canonical WHERE fingerprint=?',
                                                         (key,)).fetchone()
                            if canonical and canonical[1:3] == inode_id:
                                continue
                            if canonical and canonical[3] < max_links:
                                summary['candidate_paths'] += 1
                                if apply:
                                    replace_with_link(Path(canonical[0]), path, info, key, audit,
                                                      ignore_mtime, ignore_lustre_layout)
                                    summary['linked_paths'] += 1
                                database.execute('UPDATE inodes SET replaced=replaced+1 WHERE device=? AND inode=?',
                                                 inode_id)
                                database.execute('UPDATE canonical SET links=links+1 WHERE fingerprint=?', (key,))
                            else:
                                database.execute('INSERT OR REPLACE INTO canonical VALUES (?, ?, ?, ?, ?)',
                                                 (key, str(path)) + inode_id + (info.st_nlink,))
                    database.commit()
                    audit.write('cache_complete', path=str(cache),
                                candidate_paths=summary['candidate_paths'] - candidates_before)
                summary['eligible_file_inodes_seen'] = database.execute('SELECT COUNT(*) FROM inodes').fetchone()[0]
                # Inventory diagnostic, not a savings estimate: external links
                # and link caps can prevent these duplicate inodes being freed.
                summary['duplicate_file_inodes_ignoring_mtime'] = database.execute(
                    'SELECT COUNT(*) - COUNT(DISTINCT content_fingerprint) FROM inodes').fetchone()[0]
                # External hard links can keep an old inode alive. Count only inodes
                # for which every original link is among the replacements.
                summary['file_inodes_reclaimable' if not apply else 'file_inodes_released'] = database.execute(
                    'SELECT COUNT(*) FROM inodes WHERE replaced=links').fetchone()[0]
                summary['total_inodes_after'] = count_cache_inodes(caches, database)
                summary['total_inodes_reduced'] = summary['total_inodes_before'] - summary['total_inodes_after']
        audit.write('complete', **summary)
        return summary
    except Exception as error:
        audit.write('error', reason=str(error), **summary)
        raise
    finally:
        audit.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('paths', nargs='+', help='Cache directories or parent directories containing caches')
    parser.add_argument('--apply', action='store_true', help='Apply links; all jobs using these caches must be stopped')
    parser.add_argument('--report', help='New JSONL audit file outside the caches; required with --apply')
    parser.add_argument('--scratch-dir', help='Local scratch for the temporary SQLite index')
    parser.add_argument('--exclude', action='append', default=[], help='Cache or directory to exclude; repeatable')
    parser.add_argument('--max-links', type=int, default=10000, help='Conservative per-inode link cap (default: 10000)')
    parser.add_argument('--ignore-mtime', action='store_true',
                        help='Allow identical files with different mtimes to share an inode; '
                             'the source filesystem mtime is retained, and both times are audited')
    parser.add_argument('--diagnose', action='store_true',
                        help='Read-only bounded scan comparing contents first, then metadata; cannot apply')
    parser.add_argument('--ignore-lustre-layout', action='store_true',
                        help='Disregard only the lustre.lov storage layout xattr when matching; '
                             'linked paths share the source inode and its layout; all other xattrs must match')
    parser.add_argument('--diagnostic-limit', type=int, default=1000,
                        help='Maximum regular file paths to inspect with --diagnose (default: 1000)')
    args = parser.parse_args()
    if not hasattr(os, 'listxattr') or not hasattr(os, 'getxattr'):
        parser.exit(1, 'Run this utility with a Linux Python that supports os.listxattr/getxattr.\n')
    # Let normal scheduler termination unwind temporary links and directory modes.
    def terminate(signum, frame):
        raise RuntimeError('Termination requested; stopping compaction')

    signal.signal(signal.SIGTERM, terminate)
    try:
        summary = deduplicate(args.paths, apply=args.apply, report=args.report,
                              scratch_dir=args.scratch_dir, excluded=args.exclude,
                              max_links=args.max_links, ignore_mtime=args.ignore_mtime,
                              diagnose=args.diagnose, diagnostic_limit=args.diagnostic_limit,
                              ignore_lustre_layout=args.ignore_lustre_layout)
    except (OSError, ValueError, RuntimeError, sqlite3.Error) as error:
        parser.exit(1, f'Error: {error}\n')
    print(json.dumps(summary, indent=2))
    if args.diagnose:
        print('Read-only diagnostic sample; metadata differences are compared with the first '
              'content match, not projected inode savings. No paths changed.', file=sys.stderr)
        return
    print(f"Total unique inodes in selected caches (including directories and symlinks): "
          f"{summary['total_inodes_before']:,} before; {summary['total_inodes_after']:,} after; "
          f"{summary['total_inodes_reduced']:,} fewer.", file=sys.stderr)
    if args.apply:
        print(f"Applied: {summary['linked_paths']:,} paths linked; "
              f"{summary['file_inodes_released']:,} original file inodes released during this run.", file=sys.stderr)
    else:
        print(f"Dry run: {summary['file_inodes_reclaimable']:,} file inodes reclaimable; "
              'no paths changed.', file=sys.stderr)
    print('eligible_file_inodes_seen is the scanned inventory, not remaining savings.',
          file=sys.stderr)


if __name__ == '__main__':
    main()
