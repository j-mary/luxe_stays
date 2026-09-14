"""Reconstruct and analyze each build-along checkpoint (no repository imports).
Usage: python3 tool/check_handbook_stages.py /absolute/flutter/bin/flutter
"""
from html.parser import HTMLParser
from pathlib import Path
import subprocess
import sys
import tempfile

class Course(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stage=0;self.parts={};self.caption=False;self.code=False;self.label='';self.text='';self.path=None;self.pre=False
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if tag=='article': self.stage=int(a['id'].split('-')[1]); self.parts[self.stage]=[]
        if tag=='figcaption': self.caption=True;self.label=''
        if tag=='pre':self.pre=True
        if tag=='code' and self.stage and self.pre:
            self.code=True;self.text='';self.path=a.get('data-source')
    def handle_data(self,text):
        if self.caption:self.label+=text
        if self.code:self.text+=text
    def handle_endtag(self,tag):
        if tag=='figcaption':self.caption=False
        if tag=='pre':self.pre=False
        if tag=='code' and self.code:
            self.code=False
            path=self.path
            if not path and '— temporary' in self.label:
                path=self.label.split(' —')[0]
            if not path and '— complete search preview' in self.label:path='lib/main.dart'
            if path and (path.startswith(('lib/','test/','integration_test/','tool/mock_server/')) or path in ('pubspec.yaml','pubspec.lock','analysis_options.yaml')):
                self.parts[self.stage].append((path,self.text))
        if tag=='article':self.stage=0

root=Path(__file__).resolve().parents[1]
p=Course();p.feed((root.parent/'LuxeStays-Build-Handbook.html').read_text())
target=Path(tempfile.mkdtemp(prefix='luxe-stages-'))
flutter=sys.argv[1]
for stage,parts in p.parts.items():
    for name,text in parts:
        f=target/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(text)
    if stage==5:
        subprocess.run([flutter,'pub','get'],cwd=target,check=True,stdout=subprocess.DEVNULL)
    if stage==7:
        f=target/'lib/main.dart';s=f.read_text().replace("import 'package:flutter/material.dart';","import 'package:flutter/material.dart';\nimport 'app/theme.dart';").replace('const MaterialApp(home: Welcome())','MaterialApp(theme: AppTheme.light(), darkTheme: AppTheme.dark(), home: const Welcome())');f.write_text(s)
    if stage in range(6,21):
        result=subprocess.run([flutter,'analyze','--fatal-infos'],cwd=target,text=True,capture_output=True)
        print(f'Stage {stage}: '+('PASS' if result.returncode==0 else result.stdout+result.stderr),flush=True)
        if result.returncode:sys.exit(result.returncode)
print('All implementation checkpoints analyze from embedded tutorial source:',target)
