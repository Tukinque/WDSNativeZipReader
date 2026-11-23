# Windows + iPad 무료 빌드/설치 안내

이 파일은 기존 미컴파일 프로토타입에 GitHub Actions 빌드 파이프라인을 추가한 것입니다. 컴파일 성공이나 오프라인 재생은 아직 확인되지 않았습니다.

## 1. 준비
- GitHub 계정, Windows PC, iPad, 데이터 전송 가능한 USB 케이블, 무료 Apple 계정
- Windows에서 GitHub에 새 저장소 생성 (공개 저장소 사용 시 저작권/라이선스 확인. 개인 자료와 resources.zip은 업로드하지 마세요.)
- 프로젝트의 **내용물** (`project.yml`, `WDSNative/`, `.github/`, `scripts/` 등)을 저장소 루트에 업로드. `.github` 숨김 폴더 누락 주의.
- GitHub 웹에서 여러 파일 업로드가 어려우면 Git for Windows로 `git add -A; git commit -m "Initial iOS build"; git push` 실행.

## 2. GitHub Actions 빌드
- 저장소 → Actions → Build unsigned iPad IPA → Run workflow
- 성공 시 해당 실행의 Artifacts에서 `WDSNativeZipReader-unsigned` 다운로드 후 압축을 풀어 `.ipa` 확보
- 실패 시 `build-log` 아티팩트 또는 Actions 로그를 확인. 이 프로젝트는 아직 Xcode 컴파일 검증이 되지 않았으며 소스/API 수정이 필요할 수 있음.
- GitHub Actions macOS 러너 사용은 계정과 저장소 유형에 따라 무료 할당량/요금이 다름. 실행 전 GitHub Billing/Actions 사용량 확인.

## 3. Windows에서 설치
- Apple Devices(Windows) 설치, USB로 iPad 연결, 신뢰 허용
- Sideloadly(공식 사이트 https://sideloadly.io/) 등 서명 도구를 이용해 **직접 만든 unsigned IPA**를 무료 Apple 계정으로 서명하고 iPad에 설치
- iPad 설정에서 개발자 모드가 요구되면 활성화하고, VPN 및 기기 관리에서 해당 개발자 앱 신뢰
- 무료 서명은 보통 7일 후 만료되므로 재서명 필요. 앱 삭제/재설치 시 앱 Documents의 ZIP 데이터가 사라질 수 있으므로 데이터 백업 후 작업.

## 4. 리소스 가져오기
- `resources.zip`은 GitHub에 업로드하지 않음. iPad 파일 앱으로 별도 전송
- 앱에서 ZIP 선택. ZIP 루트에 `index.html`, `adv-player/index.html`, `data/manifest/Episode.json`이 있어야 함.
- 이 앱은 ZIP을 앱 Documents로 복사하므로 6GB 이상, 전송 방식에 따라 추가 여유 공간이 필요함.

## 문제 해결
- 앱 빌드 실패: Actions의 build-log를 공유하면 컴파일 오류를 기준으로 수정 가능
- 앱 실행 후 빈 화면: ZIP 구조/HTML의 JS 의존성, 파일 MIME 타입, 네트워크 요청, iOS WebKit 제한을 점검해야 함
- 오디오 재생 실패: Android JS 브리지 및 음성 처리 코드는 아직 iOS용으로 이식되지 않음
