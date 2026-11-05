# KB커넥트 홈페이지

소량 제작이 필요한 사업자(수요자)와 생산 여력이 있는 공장(공급자)을 연결하는 서비스의 홈페이지입니다.
서버 없이 돌아가는 정적 사이트이고, 휴대폰에서 **앱처럼 설치(PWA)** 할 수 있습니다.

## 파일 구성
| 파일 | 내용 |
|---|---|
| `index.html` | 홈페이지 (소개, 진행 방식, 비용, 찾는 중인 일, 의뢰서, 공급사 등록, FAQ) |
| `admin.html` | 관리자 페이지: 접수된 의뢰·공급사 목록 보기, 상태·메모 변경 |
| `js/config.js` | **상호, 연락처, 비용, 게시판 내용, 접수 주소** 설정 (대부분 여기만 고치면 됨) |
| `apps-script/Code.gs` | 접수 내용을 구글 시트에 저장하는 코드 |
| `manifest.webmanifest`, `sw.js`, `icons/` | 앱 설치용 파일 |

## 1. 미리 보기
```bash
cd connect && python3 -m http.server 8000
```
브라우저에서 `http://localhost:8000` 접속. (파일을 더블클릭해서 열어도 보이지만 앱 설치 기능은 꺼집니다.)

## 2. 접수 연결 (구글 시트) — 약 10분
연결 전에는 의뢰서를 보내면 **메일 앱이 열려** `info@kblogistics.kr`로 내용이 전달됩니다. 시트에 자동으로 쌓이게 하려면:

1. 구글 드라이브에서 새 스프레드시트 만들기 (이름: `KB커넥트 접수`)
2. 메뉴 **확장 프로그램 → Apps Script** → 기본 코드를 지우고 `apps-script/Code.gs` 내용 붙여넣기
3. 맨 위 `ADMIN_TOKEN`을 나만 아는 긴 문자열로 바꾸기, `NOTIFY_EMAIL` 확인
4. **배포 → 새 배포 → 유형: 웹 앱**, 실행 계정 `나`, 액세스 권한 `모든 사용자` → 배포 → 권한 허용
5. 나온 웹 앱 URL(`https://script.google.com/macros/s/.../exec`)을 `js/config.js`의 `endpoint`에 붙여넣기
6. 홈페이지에서 테스트 의뢰를 보내고 시트에 줄이 생기는지 확인

이후 `admin.html`에 들어가 `ADMIN_TOKEN`으로 로그인하면 접수 목록을 보고 진행상태(신규 → 확인중 → 업체수배 → 명함전달 → 연결완료 → 정산완료)를 바꿀 수 있습니다. 시트를 직접 열어 봐도 됩니다.

> Apps Script 코드를 고친 뒤에는 **배포 관리 → 수정 → 새 버전**으로 다시 배포해야 반영됩니다.

## 3. 배포 (무료)
아래 중 하나를 고르세요. `connect` 폴더 전체를 올리면 됩니다.
- **Netlify**: netlify.com → Add new site → Deploy manually → `connect` 폴더 끌어다 놓기
- **GitHub Pages**: 저장소 Settings → Pages → 브랜치 선택 (폴더는 `/connect`를 루트로 옮기거나 Actions 사용)
- **Cloudflare Pages**: 저장소 연결 → Build output directory `connect`

도메인은 `connect.kblogistics.kr`처럼 기존 도메인의 하위 주소를 연결하는 것을 추천합니다.

파일을 고쳐 다시 배포할 때는 `sw.js`의 `VERSION`을 `v2`, `v3`…로 올려 주세요. (설치한 앱이 새 내용을 받게 됩니다.)

## 4. 앱으로 배포하기
`사업모델.md`의 "앱 로드맵"을 참고하세요. 요약하면:
1. **지금**: 홈페이지 = 설치형 웹앱(PWA). 안드로이드 크롬/아이폰 사파리에서 "홈 화면에 추가"
2. **플레이스토어**: PWA를 그대로 감싸는 TWA(Bubblewrap / PWABuilder)로 등록 — 코드 수정 없이 가능
3. **앱스토어·푸시 알림**: Capacitor로 감싸서 iOS/Android 앱 빌드, 접수 알림 푸시 추가
