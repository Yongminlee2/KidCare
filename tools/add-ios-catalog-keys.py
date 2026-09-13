#!/usr/bin/env python3
# i18n/ko.json 의 키를 ios/KidCare/Localizable.xcstrings 에 한국어 값으로 넣는다.
# 6단계의 tools/ios-strings.py 가 생기기 전까지 쓰는 손 옮김 도구다(계획서 공통 절차 A).
#
#   python3 tools/add-ios-catalog-keys.py control_find_hint control_lock_hint
#
# - 이미 카탈로그에 있는 키는 건너뛴다. 1단계에서 손으로 고친 "알려진 어긋남" 을 덮지 않기 위해서다.
# - 서식 변환은 LocalizableCatalogTests.카탈로그_값 과 같다: %1$s → %1$@, 숫자 서식
#   (%1$d, %1$02d, %1$.1f)은 그대로, 서식이 아닌 % 는 %%.
#   예전 인라인 명령의 정규식 %(\d+\$)?(\d+)?([sd]) 는 소수 서식을 %%1$.1f 로 망가뜨렸다.
# - 파일 전체를 json.dumps(indent=2, ensure_ascii=False) + "\n" 로 다시 쓴다. 기존 파일과 바이트 단위로
#   같은 모양이라 git diff 에는 새로 넣은 키만 나온다.
import json
import os
import re
import sys

FORMAT = re.compile(r'%(\d+\$)?(\d+)?(\.\d+)?([sdf])')


def conv(value):
    out, i = [], 0
    while i < len(value):
        if value[i] != '%':
            out.append(value[i])
            i += 1
            continue
        m = FORMAT.match(value, i)
        if m:
            c = m.group(4)
            out.append('%' + (m.group(1) or '') + (m.group(2) or '') + (m.group(3) or '') + ('@' if c == 's' else c))
            i = m.end()
        elif value.startswith('%%', i):
            out.append('%%')
            i += 2
        else:
            out.append('%%')
            i += 1
    return ''.join(out)


# 변환 규칙이 조용히 바뀌지 않게 실행할 때마다 확인한다.
assert conv('%1$.1fkm') == '%1$.1fkm'
assert conv('배터리 %1$d%\n%2$s 기준') == '배터리 %1$d%%\n%2$@ 기준'
assert conv('%1$02d:%2$02d') == '%1$02d:%2$02d'


def main(keys):
    if not keys:
        sys.exit('사용법: python3 tools/add-ios-catalog-keys.py <키> [<키> ...]')
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    with open(os.path.join(root, 'i18n/ko.json'), encoding='utf-8') as f:
        ko = json.load(f)
    missing = [k for k in keys if k not in ko]
    if missing:
        sys.exit('i18n/ko.json 에 없는 키: ' + ' '.join(missing))

    path = os.path.join(root, 'ios/KidCare/Localizable.xcstrings')
    with open(path, encoding='utf-8') as f:
        cat = json.load(f)
    added, skipped = [], []
    for k in keys:
        if k in cat['strings']:
            skipped.append(k)
            continue
        cat['strings'][k] = {
            "extractionState": "manual",
            "localizations": {"ko": {"stringUnit": {"state": "translated", "value": conv(ko[k])}}},
        }
        added.append(k)
    cat['strings'] = dict(sorted(cat['strings'].items()))
    with open(path, 'w', encoding='utf-8') as f:
        f.write(json.dumps(cat, indent=2, ensure_ascii=False) + '\n')
    print('넣음 %d: %s' % (len(added), ' '.join(added)))
    print('건너뜀(이미 있음) %d: %s' % (len(skipped), ' '.join(skipped)))


if __name__ == '__main__':
    main(sys.argv[1:])
