# Compatibility harness

Ruby 원본 v1의 출력을 **골든 파일로 동결**하고, Crystal 바이너리가 동일 출력을 내는지 검증하는 블랙박스 테스트다.

## 구조

```
spec/compat/
├── fixtures/
│   └── server.rb         # 최소 HTTP fixture 서버 (Ruby stdlib only)
├── golden/
│   └── <case>.{json,yaml,toml,csv}   # 기대 출력. {{BASE}} 플레이스홀더
├── run.rb                # 드라이버: 서버 기동 → 바이너리 실행 → 비교
└── README.md
```

## 실행

```bash
shards install
crystal build src/cli_main.cr -o deadfinder --release
BIN="./deadfinder" ruby spec/compat/run.rb
```

## 케이스 추가

1. `fixtures/server.rb`의 `ROUTES`에 필요한 경로 추가
2. `golden/<name>.<format>`에 기대 출력 작성 (`{{BASE}}`로 origin 표현)
3. `run.rb` 맨 아래 `run_case(...)` 한 줄 추가

## 비교 규칙

- 배열은 정렬 후 비교 (링크 추출 순서 비결정성 흡수)
- `{{BASE}}` 플레이스홀더는 실행 시 동적 포트로 치환
- 출력은 `-o <tmpfile>`로 받아 파일에서 파싱

## 왜 Ruby 드라이버?

골든 파일은 v1 Ruby 출력의 스냅샷이고, 비교 로직에 `toml-rb` 같은 파서가 필요해서 그대로 Ruby 드라이버를 유지했다. Crystal로 포팅할 수도 있지만 CI 복잡도 대비 이득이 적다.
