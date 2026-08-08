# R8 규칙 — 규칙 하나마다 "이게 없으면 무엇이 조용히 망가지는가"를 적는다.
#
# 설명할 수 없는 -keep 은 반년 뒤 "-keep 전부"가 된다. 여기 있는 두 규칙은
# 규칙을 뺀 채로 R8 을 한 번 돌려서 **실제로 무엇이 사라지는지 확인하고** 남긴
# 것이다. 확인 결과는 .superpowers/sdd/2026-08-08-kidcare-phase6/task-4-report.md
# 에 그대로 적어 뒀다 — 규칙을 지워도 되는지 다시 판단할 때 그 방법을 그대로
# 되풀이하면 된다(규칙을 비우고 :app:minifyReleaseWithR8 만 돌린 뒤 mapping.txt 를 본다).
#
# 이 앱에서 R8 이 조용히 부수는 것은 크래시가 아니라 **빈 화면**이다.
# Firestore 는 필드를 못 찾으면 예외를 던지지 않고 기본값(null·0·빈 리스트)을
# 넣어 준다 — 지도에 마커가 안 뜨고 타임라인이 비고 명령이 안 풀린다.
# 셋 다 "오늘 아무 일도 없었다"와 화면에서 구분되지 않는다.

# ---------------------------------------------------------------------------
# 1. Firestore 문서 클래스 (core/model/Documents.kt 전부)
# ---------------------------------------------------------------------------
# toObject() 는 리플렉션으로 동작한다. 문서의 필드 이름 문자열("lastSeenAt")을
# 클래스의 게터 이름(getLastSeenAt)과 **글자 그대로** 맞춰 보므로, 난독화로
# 이름이 바뀌는 순간 모든 필드가 기본값으로 들어온다. 예외는 안 난다.
#
# 규칙을 빼고 돌려 보니 실제로는 이름이 바뀌는 정도가 아니었다:
#   - 게터 20여 개가 통째로 **사라졌다**(전부 인라인됨). 읽을 프로퍼티가 0 이 된다.
#   - 인자 없는 생성자도 사라졌다. 전 필드에 기본값이 있어 코틀린이 합성해 두지만
#     직접 부르는 코드가 앱에 한 줄도 없어서, R8 이 보기에는 죽은 코드다.
#     이게 없으면 toObject 는 인스턴스를 만들 수조차 없다.
#   - ChildStatusDoc.lastSeenServerAt 은 **필드 자체가 지워졌다**(생성자 시그니처에서도
#     빠졌다). 앱 코드가 이 필드를 쓰지 않고 서버만 채우는 값이라 그렇다.
#
# 클래스 이름 자체는 난독화해도 안전하지만(Firestore 는 클래스 이름을 안 본다)
# 같이 남긴다 — 15개짜리 짧은 목록이고, Firestore 예외의 stack trace 가 읽히는
# 값이 그보다 크다.
-keep class com.kidcare.family.core.model.** { *; }

# 제네릭 타입 정보. TrailDoc.points 는 List<TrailPoint>, CommandDoc.payload 는
# Map<String,String> 인데, Signature 속성이 지워지면 Firestore 의
# CustomClassMapper 는 원소 타입을 알 방법이 없어 List<HashMap> 을 그대로 넣는다.
# 그러면 하루 경로와 명령 페이로드가 통째로 못 읽히고, 이것도 조용하다.
# RuntimeVisibleAnnotations 는 ChildStatusDoc.lastSeenServerAt 의
# @get:ServerTimestamp 를 살리는 것이다 — 지워지면 서버가 시각을 안 채워 주고
# 보호자 화면의 "마지막 신호"가 아이 폰 시계로 되돌아간다(known-issues 7번).
-keepattributes Signature, RuntimeVisibleAnnotations, AnnotationDefault

# ---------------------------------------------------------------------------
# 없는 규칙 하나 — Role enum. **넣지 말 것.**
# ---------------------------------------------------------------------------
# RoleStore 는 role 을 name()("CHILD")으로 저장하고 Role.valueOf(문자열) 로
# 되읽는다(core/Role.kt). 이게 깨지면 이미 페어링이 끝난 폰이 역할 선택 화면으로
# 되돌아간다 — 화면만 보면 페어링이 통째로 날아간 것과 똑같다. 그래서 처음에
# -keepclassmembers enum ... { *; } 를 넣었는데, 규칙을 빼고 확인해 보니 **필요
# 없었다.**
#   - values()/valueOf() 는 AGP 기본 규칙(proguard-android-optimize.txt)이 이미
#     이름 그대로 지킨다. 안드로이드의 Enum.valueOf 는 이 둘을 이름으로 찾으므로
#     여기가 끊기면 실제로 깨진다 — 지키는 주체가 우리가 아닐 뿐이다.
#   - 상수 필드는 a/b 로 바뀌지만, <clinit> 이 생성자에 넘기는 이름 문자열
#     ("GUARDIAN")은 R8 이 건드리지 않는다(dexdump 로 확인). name() 이 옛 문자열을
#     그대로 돌려주므로 valueOf 는 계속 맞는다.
# 지금 하는 일이 없는 규칙을 "혹시 몰라서" 남기면, 다음 사람은 그걸 지워도 되는지
# 확인할 방법이 없어 그냥 둔다. 그렇게 -keep 이 쌓인다.
