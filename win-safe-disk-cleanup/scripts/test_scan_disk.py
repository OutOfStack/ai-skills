import os
import tempfile
import unittest
from pathlib import Path
from scan_disk import GIB, compare, scan


class ScanTests(unittest.TestCase):
    def test_metadata_and_no_content_mutation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/'nested').mkdir()
            personal = root/'nested'/'personal.txt'
            personal.write_bytes(b'preserve this')
            before = personal.stat()
            result = scan(root)
            self.assertEqual(result['file_count'], 1)
            self.assertEqual(result['logical_bytes_scanned'], len(b'preserve this'))
            self.assertEqual(personal.read_bytes(), b'preserve this')
            self.assertEqual(before.st_mtime_ns, personal.stat().st_mtime_ns)
            try:
                (root/'loop').symlink_to(root, target_is_directory=True)
            except OSError:
                pass
            else:
                result = scan(root)
                self.assertEqual(result['file_count'], 1)
                self.assertEqual(result['skipped_links'], 1)

    def test_new_growth_alerts_and_parent_deduplication(self):
        root = os.path.abspath('disk-test-root')
        file = os.path.join(root, 'cache', 'new.bin')
        parent = os.path.dirname(file)
        old = {'root': root, 'files': {}, 'folders': {parent: GIB}, 'free_bytes': 30*GIB}
        now = {'root': root, 'files': {file: 3*GIB}, 'folders': {parent: 4*GIB}, 'free_bytes': 19*GIB}
        result = compare(now, old)
        self.assertEqual([x['path'] for x in result['changes']], [file])
        self.assertEqual(len(result['space_alerts']), 2)
        self.assertEqual(compare(now, now)['changes'], [])
        self.assertTrue(compare(now, None)['baseline_created'])
        changed_root = dict(old, root='different-root')
        with self.assertRaises(ValueError):
            compare(now, changed_root)


if __name__ == '__main__':
    unittest.main()
