"""Tambah intent "Buka dengan Leaf", izin TTS & buka link ke AndroidManifest."""
import sys

p = sys.argv[1]
s = open(p).read()

filters = '''            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="content"/>
                <data android:scheme="file"/>
                <data android:mimeType="application/pdf"/>
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.SEND"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <data android:mimeType="application/pdf"/>
            </intent-filter>
'''
if 'application/pdf' not in s:
    s = s.replace('        </activity>', filters + '        </activity>', 1)
if 'application/pdf' not in s:
    s = s.replace('</activity>', filters + '</activity>', 1)

q = ('        <intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>\n'
     '        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>\n')
if 'TTS_SERVICE' not in s:
    if '<queries>' in s:
        s = s.replace('<queries>', '<queries>\n' + q, 1)
    else:
        s = s.replace('</manifest>', '    <queries>\n' + q + '    </queries>\n</manifest>')

open(p, 'w').write(s)
print('manifest patched')
