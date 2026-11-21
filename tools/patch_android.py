"""يعدّل AndroidManifest.xml لروابط الدعوة (Android App Links).

- رابط https://<WEB_HOST>/j/... يفتح التطبيق مباشرة إذا كان منصّب
  (autoVerify: أندرويد يتأكد من /.well-known/assetlinks.json بالويب، اللي ينحط بالـ CI
  بنفس بصمة ci/debug.keystore).
- نطفي الـ deep linking مال Flutter حتى الرابط ما يتحول لمسار بالـ Navigator؛ احنا نقراه بـ app_links.
- queries: حتى url_launcher يگدر يفتح روابط https (واتساب) على أندرويد 11+.
"""
import os, pathlib

host = os.environ.get("WEB_HOST", "lamma-dk0.pages.dev")
mp = pathlib.Path("android/app/src/main/AndroidManifest.xml")
m = mp.read_text(encoding="utf-8")

if "lamma-invite" not in m:
    links = f'''
            <!-- lamma-invite: روابط الدعوة تفتح التطبيق -->
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="https" android:host="{host}" android:pathPrefix="/j"/>
            </intent-filter>
            <meta-data android:name="flutter_deeplinking_enabled" android:value="false"/>
        </activity>'''
    m = m.replace("</activity>", links, 1)

if "lamma-https" not in m:
    q = '''<!-- lamma-https -->
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>'''
    if "<queries>" in m:
        m = m.replace("<queries>", "<queries>\n        " + q, 1)
    else:
        m = m.replace("</manifest>", f"    <queries>\n        {q}\n    </queries>\n</manifest>", 1)

mp.write_text(m, encoding="utf-8")
print("android patched")
print(m)
