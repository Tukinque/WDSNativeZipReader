"""Windows에서도 실행 가능한 리소스 ZIP 사전 점검기 (Python 표준 라이브러리만 사용)."""
import sys, zipfile, collections
from pathlib import PurePosixPath

if len(sys.argv) != 2:
    print('Usage: python check_zip.py "C:\\path\\to\\resources.zip"')
    raise SystemExit(2)
required = ['index.html', 'assets/index-RGQwKqYa.js', 'adv-player/index.html',
            'adv-player/assets/index.1fd3600f.js',
            'adv-player/assets/vendor.7da41bff.js', 'data/manifest/Episode.json',
            'data/manifest/Comic.json']
with zipfile.ZipFile(sys.argv[1]) as z:
    names = {n.filename.replace('\\', '/') for n in z.infolist() if not n.is_dir()}
    roots = [''] + [p + '/' for p in sorted({n.split('/')[0] for n in names if '/' in n})]
    best = min(roots, key=lambda r: sum(r + f not in names for f in required))
    print('ZIP entries:', len(names), '| prefix:', repr(best))
    for f in required:
        print(('OK     ' if best + f in names else 'MISSING'), f)
    print('Uncompressed size (GB):', round(sum(n.file_size for n in z.infolist())/1e9, 2))
    print('Top directories:', collections.Counter(n.split('/')[0] for n in names).most_common(12))
