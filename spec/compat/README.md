# Cross-implementation compatibility harness

이 디렉토리는 Ruby 원본과 Crystal 포팅 구현이 **사용자에게 동일한 출력을 낸다**는 것을 검증하는 블랙박스 테스트다.

## 구조

```
spec/compat/
├── fixtures/
│   └── server.rb         # 최소 HTTP fixture 서버 (stdlib only)
├── golden/
│   └── <case>.json       # 기대 출력. {{BASE}} 플레이스홀더 사용
├── run.rb                # 드라이버: 서버 기동 → 바이너리 실행 → 비교
└── README.md
```

## 실행

```bash
# 기본: Ruby 구현
ruby spec/compat/run.rb

# Crystal 구현
cd crystal && shards install && crystal build src/cli_main.cr -o deadfinder --release
cd ..
BIN="./crystal/deadfinder" ruby spec/compat/run.rb
```

## 케이스 추가

1. `fixtures/server.rb`의 `ROUTES`에 필요한 경로 추가
2. `golden/<name>.json`에 기대 출력 작성 (`{{BASE}}`로 origin 표현)
3. `run.rb` 맨 아래 `run_case(...)` 한 줄 추가

## 비교 규칙

- 배열은 정렬 후 비교 (링크 추출 순서 비결정성 흡수)
- `{{BASE}}` 플레이스홀더는 실행 시 동적 포트로 치환
- 출력은 `-o <tmpfile>`로 받아 파일에서 파싱 (stdout에는 구조화 출력 없음)
