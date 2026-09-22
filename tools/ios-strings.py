#!/usr/bin/env python3
# i18n/*.json 14벌 → ios/KidCare/Localizable.xcstrings (설계서 §7, 6단계 계획서 공통 절차 A).
# 같은 원본의 app_name 으로 ios/KidCare/InfoPlist.xcstrings(CFBundleDisplayName)도 만든다(7단계 판정 기록 13).
#
#   python3 tools/ios-strings.py              생성한다. 빈 칸이 기록과 다르면 쓰지 않고 멈춘다.
#   python3 tools/ios-strings.py --check      쓰지 않는다. 카탈로그가 지금 생성 결과와 다르면 종료 코드 1.
#   python3 tools/ios-strings.py --write-gaps 빈 칸 기록(tools/i18n-untranslated.json)도 새로 쓴다.
#
# 번역을 짓지 않는다. 어떤 언어에 키가 없으면 그 칸에 영어 값을 넣고 needs_review 로 표시한다 —
# 안드로이드도 values-<언어>/ 에 없는 키는 기본 values/(영어)로 나온다(values/strings.xml:2).
# iOS 는 개발 언어가 ko 라서 칸을 비워 두면 독일어 폰에 한국어가 뜬다.
#
# 출력은 원본에서만 정해진다(키·언어 정렬, 기록은 정렬된 목록). 그래서 두 번 돌려도 diff 가 없고,
# 다른 갈래에서 원본 키를 더한 뒤 합쳐도 이 명령 한 번으로 카탈로그가 다시 맞춰진다.
#
# 서식 변환은 5단계까지 쓰던 손 옮김 도구와 LocalizableCatalogTests.카탈로그_값 과 같다:
# %1$s → %1$@, 숫자 서식(%1$d, %1$02d, %1$.1f)은 그대로, 서식이 아닌 % 는 %%.
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, 'ios/KidCare/Localizable.xcstrings')
GAPS = os.path.join(ROOT, 'tools/i18n-untranslated.json')
INFOPLIST = os.path.join(ROOT, 'ios/KidCare/InfoPlist.xcstrings')
# Info.plist 키 → i18n 키. 안드로이드 런처 이름이 app_name 이다.
# 위치 설명 둘은 아이 역할(iOS 아이 1단계 Task 3)이 더한 것이고, 앱스토어 심사가 직접 읽는
# 문장이다(설계서 §8.5·§17-10). 여기 매핑이 있어야 InfoPlist.xcstrings 에 14개 언어로 실린다.
INFOPLIST_KEYS = {
    'CFBundleDisplayName': 'app_name',
    'NSLocationWhenInUseUsageDescription': 'ios_perm_location_when_in_use',
    'NSLocationAlwaysAndWhenInUseUsageDescription': 'ios_perm_location_always',
}
# (i18n 파일 이름, 카탈로그 언어 태그). 태그는 안드로이드 AppLanguage.kt:23-36 의 tag 와 같다.
LANGS = [
    ('ko', 'ko'), ('en', 'en'), ('ja', 'ja'), ('zh', 'zh-Hans'), ('zh_Hant', 'zh-Hant'),
    ('es', 'es'), ('pt', 'pt'), ('de', 'de'), ('fr', 'fr'), ('it', 'it'),
    ('ru', 'ru'), ('id', 'id'), ('vi', 'vi'), ('th', 'th'),
]
FULL = ('ko', 'en')
FORMAT = re.compile(r'%(\d+\$)?(\d+)?(\.\d+)?([sdf])')


def scan(value):
    """(iOS 값, 서식 인자 목록[(위치, 변환 문자)])."""
    out, specs, i = [], [], 0
    while i < len(value):
        if value[i] != '%':
            out.append(value[i])
            i += 1
            continue
        m = FORMAT.match(value, i)
        if m:
            c = m.group(4)
            out.append('%' + (m.group(1) or '') + (m.group(2) or '') + (m.group(3) or '') + ('@' if c == 's' else c))
            specs.append((m.group(1) or '', c))
            i = m.end()
        elif value.startswith('%%', i):
            out.append('%%')
            i += 2
        else:
            out.append('%%')
            i += 1
    return ''.join(out), specs


def conv(value):
    return scan(value)[0]


# 변환 규칙이 조용히 바뀌지 않게 실행할 때마다 확인한다(5단계 손 옮김 도구의 세 줄 그대로).
assert conv('%1$.1fkm') == '%1$.1fkm'
assert conv('배터리 %1$d%\n%2$s 기준') == '배터리 %1$d%%\n%2$@ 기준'
assert conv('%1$02d:%2$02d') == '%1$02d:%2$02d'


def fail(message):
    sys.exit('ios-strings: ' + message)


def load():
    src = {}
    for name, _ in LANGS:
        with open(os.path.join(ROOT, 'i18n', name + '.json'), encoding='utf-8') as f:
            d = json.load(f)
        if not all(isinstance(k, str) and isinstance(v, str) for k, v in d.items()):
            fail(name + '.json 에 문자열이 아닌 값이 있다')
        src[name] = d
    return src


def build(src, version):
    ko, en = src['ko'], src['en']
    if set(ko) != set(en):
        fail('ko·en 키가 다르다: ko 에만 %s / en 에만 %s' % (sorted(set(ko) - set(en)), sorted(set(en) - set(ko))))
    gaps, problems = {}, []
    for name, _ in LANGS:
        d = src[name]
        extra = sorted(set(d) - set(ko))
        if extra:
            problems.append('%s.json 에만 있는 키: %s' % (name, extra))
        for key, value in d.items():
            if '%@' in value:
                problems.append('%s.json %s 에 %%@ 가 있다 — 원본은 안드로이드 서식만 쓴다' % (name, key))
            # 번역이 ko 에 없는 인자를 읽으면 String(format:) 이 없는 인자를 읽어 앱이 죽는다.
            # 인자를 덜 쓰는 것은 안전하다(2026-09-13 원본 14벌 전부 이 검사를 통과한다).
            if key in ko and not set(scan(value)[1]) <= set(scan(ko[key])[1]):
                problems.append('%s.json %s 가 ko 에 없는 서식 인자를 쓴다' % (name, key))
        if name not in FULL:
            gaps[name] = sorted(set(ko) - set(d))
    if problems:
        fail('\n'.join(problems))

    strings = {}
    for key in sorted(ko):
        localizations = {}
        for name, tag in LANGS:
            if key in src[name]:
                unit = {'state': 'translated', 'value': conv(src[name][key])}
            else:
                unit = {'state': 'needs_review', 'value': conv(en[key])}
            localizations[tag] = {'stringUnit': unit}
        strings[key] = {'extractionState': 'manual', 'localizations': localizations}
    catalog = {'sourceLanguage': 'ko', 'strings': strings, 'version': version}
    # sort_keys + indent=2 + ensure_ascii=False + 끝 줄바꿈: 5단계까지의 카탈로그와 같은 모양이다
    # (2026-09-13 확인 — 기존 파일을 이 방식으로 다시 쓰면 바이트까지 같다).
    return json.dumps(catalog, indent=2, ensure_ascii=False, sort_keys=True) + '\n', gaps


def build_infoplist(src):
    """InfoPlist.xcstrings. Info.plist 값은 서식 문자열이 아니므로 conv() 를 거치지 않는다 — 거치면 % 가 %% 로 남는다."""
    en = src['en']
    strings = {}
    for plist_key, key in sorted(INFOPLIST_KEYS.items()):
        if key not in en:
            fail('en.json 에 %s 가 없다' % key)
        localizations = {}
        for name, tag in LANGS:
            if key in src[name]:
                unit = {'state': 'translated', 'value': src[name][key]}
            else:
                unit = {'state': 'needs_review', 'value': en[key]}
            localizations[tag] = {'stringUnit': unit}
        strings[plist_key] = {'extractionState': 'manual', 'localizations': localizations}
    catalog = {'sourceLanguage': 'ko', 'strings': strings, 'version': '1.0'}
    return json.dumps(catalog, indent=2, ensure_ascii=False, sort_keys=True) + '\n'


def report(gaps):
    for name, keys in sorted(gaps.items()):
        print('번역 대기 %-8s %3d개' % (name, len(keys)))
    if gaps:
        common = sorted(set.intersection(*(set(v) for v in gaps.values())))
        if common:
            print('12개 언어 모두 영어로 물러나는 키: ' + ' '.join(common))


def main(args):
    with open(CATALOG, encoding='utf-8') as f:
        current = f.read()
    version = json.loads(current).get('version', '1.0')
    src = load()
    text, gaps = build(src, version)
    plist_text = build_infoplist(src)
    plist_current = ''
    if os.path.exists(INFOPLIST):
        with open(INFOPLIST, encoding='utf-8') as f:
            plist_current = f.read()
    report(gaps)

    if '--write-gaps' in args:
        with open(GAPS, 'w', encoding='utf-8') as f:
            f.write(json.dumps(gaps, indent=2, ensure_ascii=False, sort_keys=True) + '\n')
    else:
        with open(GAPS, encoding='utf-8') as f:
            recorded = json.load(f)
        if recorded != gaps:
            for name in sorted(set(recorded) | set(gaps)):
                before, after = set(recorded.get(name, [])), set(gaps.get(name, []))
                if before != after:
                    print('%s: 새 빈 칸 %s / 채워진 칸 %s' % (name, sorted(after - before), sorted(before - after)))
            fail('빈 칸이 tools/i18n-untranslated.json 과 다르다. 의도한 변화면 --write-gaps 로 다시 쓴다')

    if '--check' in args:
        if current != text:
            fail('카탈로그가 원본에서 생성한 결과와 다르다. python3 tools/ios-strings.py 를 돌린다')
        if plist_current != plist_text:
            fail('InfoPlist.xcstrings 가 원본에서 생성한 결과와 다르다. python3 tools/ios-strings.py 를 돌린다')
        return
    if current != text:
        with open(CATALOG, 'w', encoding='utf-8') as f:
            f.write(text)
    if plist_current != plist_text:
        with open(INFOPLIST, 'w', encoding='utf-8') as f:
            f.write(plist_text)
    print('카탈로그 %d키 × %d개 언어, InfoPlist %d키' % (len(src['ko']), len(LANGS), len(INFOPLIST_KEYS)))


if __name__ == '__main__':
    main(sys.argv[1:])
