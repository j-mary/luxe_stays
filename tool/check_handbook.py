"""Check source fidelity and internal links; optionally reconstruct embedded files."""
from html.parser import HTMLParser
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
class Handbook(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids = set(); self.links = []; self.sources = {}; self.path = None
        self.script = False; self.js = ''
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if 'id' in a:
            assert a['id'] not in self.ids, 'Duplicate id '+a['id']
            self.ids.add(a['id'])
        if tag == 'a' and a.get('href','').startswith('#'): self.links.append(a['href'][1:])
        if tag == 'code' and 'data-source' in a:
            self.path = a['data-source']; self.sources[self.path] = ''
        if tag == 'script': self.script = True
    def handle_data(self, text):
        if self.path: self.sources[self.path] += text
        if self.script: self.js += text
    def handle_endtag(self, tag):
        if tag == 'code': self.path = None
        if tag == 'script': self.script = False
p = Handbook(); p.feed((root.parent/'LuxeStays-Build-Handbook.html').read_text())
assert set(p.links) <= p.ids, 'Broken internal links'
for path, content in p.sources.items():
    assert content == (root/path).read_text(), 'Source drift: '+path
    if len(sys.argv)>1:
        target = Path(sys.argv[1])/path
        target.parent.mkdir(parents=True,exist_ok=True); target.write_text(content)
for folder in ['lib','test','integration_test','tool/mock_server']:
    for file in (root/folder).rglob('*.dart'):
        assert str(file.relative_to(root)) in p.sources, 'Missing file: '+str(file)
Path('/tmp/luxe-handbook-script.js').write_text(p.js)
print(f'PASS: {len(p.sources)} exact source files, {len(p.links)} valid internal links; all app/mock/test Dart files included.')
