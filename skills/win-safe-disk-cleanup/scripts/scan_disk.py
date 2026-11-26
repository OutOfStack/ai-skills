import argparse
import json
import os
import shutil
from datetime import datetime, timezone
from pathlib import Path

GIB = 1024 ** 3
MIB = 1024 ** 2
REPARSE = 0x400


def scan(root):
    folders, files, errors = {}, {}, []
    skipped = count = 0

    def visit(path):
        nonlocal skipped, count
        total = 0
        try:
            with os.scandir(path) as entries:
                for entry in entries:
                    try:
                        st = entry.stat(follow_symlinks=False)
                        if entry.is_symlink() or getattr(st, 'st_file_attributes', 0) & REPARSE:
                            skipped += 1
                            continue
                        if entry.is_dir(follow_symlinks=False):
                            total += visit(entry.path)
                        elif entry.is_file(follow_symlinks=False):
                            total += st.st_size
                            count += 1
                            if st.st_size >= 256 * MIB:
                                files[entry.path] = st.st_size
                    except OSError as exc:
                        errors.append({'path': entry.path, 'error': str(exc)})
        except OSError as exc:
            errors.append({'path': path, 'error': str(exc)})
        if total >= 64 * MIB:
            folders[path] = total
        return total

    total = visit(str(root))
    disk = shutil.disk_usage(root)
    return {'schema': 1, 'root': os.path.abspath(root),
            'time': datetime.now(timezone.utc).isoformat(), 'free_bytes': disk.free,
            'drive_bytes': disk.total, 'logical_bytes_scanned': total,
            'folders': folders, 'files': files, 'file_count': count,
            'skipped_links': skipped, 'errors': errors}


def compare(current, previous):
    if previous is None:
        return {'baseline_created': True, 'changes': [], 'space_alerts': []}
    if current['root'].casefold() != previous['root'].casefold():
        raise ValueError('Baseline belongs to a different scan root')
    changes = []
    for kind, minimum, delta in [('files', GIB, GIB), ('folders', 2 * GIB, 2 * GIB)]:
        for path, size in current[kind].items():
            before = previous[kind].get(path, 0)
            if size >= minimum and size - before >= delta:
                changes.append({'kind': kind[:-1], 'path': path, 'bytes': size,
                                'growth_bytes': size-before, 'new': path not in previous[kind]})
    # Retain a specific changed entity rather than also listing its parent totals.
    changes.sort(key=lambda x: len(x['path']), reverse=True)
    distinct = []
    for item in changes:
        prefix = item['path'].rstrip('\\/') + os.sep
        if item['kind'] != 'folder' or not any(x['path'].startswith(prefix) for x in distinct):
            distinct.append(item)
    distinct.sort(key=lambda x: x['growth_bytes'], reverse=True)
    alerts = []
    drop = previous['free_bytes'] - current['free_bytes']
    if drop >= 5 * GIB:
        alerts.append({'reason': 'free_space_fell', 'bytes': drop})
    if current['free_bytes'] < 20 * GIB <= previous['free_bytes']:
        alerts.append({'reason': 'below_20_GiB', 'bytes': current['free_bytes']})
    return {'baseline_created': False, 'changes': distinct[:30], 'space_alerts': alerts}


def main():
    parser = argparse.ArgumentParser(description='On-demand, read-only Windows disk scan; no scheduling or cleanup.')
    parser.add_argument('--root', default='C:\\')
    parser.add_argument('--state-dir', required=True)
    args = parser.parse_args()
    state = Path(args.state_dir)
    state.mkdir(parents=True, exist_ok=True)
    latest = state / 'latest.json'
    previous = json.loads(latest.read_text(encoding='utf-8')) if latest.exists() else None
    print('Scanning file metadata; no files will be deleted.', flush=True)
    current = scan(args.root)
    if not current['file_count'] and current['errors']:
        raise RuntimeError('Scan root could not be read; preserving baseline')
    report = compare(current, previous)
    report.update({'scanned_at': current['time'], 'free_GiB': round(current['free_bytes']/GIB, 2),
                   'previous_scan': previous['time'] if previous else None,
                   'files_scanned': current['file_count'], 'inaccessible_count': len(current['errors']),
                   'skipped_links': current['skipped_links'],
                   'largest_folders': sorted(current['folders'].items(), key=lambda x:x[1], reverse=True)[:25],
                   'largest_files': sorted(current['files'].items(), key=lambda x:x[1], reverse=True)[:25]})
    if previous:
        (state/'previous.json').write_text(json.dumps(previous), encoding='utf-8')
    temporary = state / 'latest.tmp'
    temporary.write_text(json.dumps(current), encoding='utf-8')
    temporary.replace(latest)
    (state/'latest-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2), flush=True)


if __name__ == '__main__':
    main()
