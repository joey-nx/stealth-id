# 개발 환경 셋업 가이드

StealthID 컨트랙트 로컬 개발/테스트 환경 구성 가이드.

## 사전 요구사항

| 도구 | 설치 |
|------|------|
| **Foundry** (forge, cast, anvil) | `curl -L https://foundry.paradigm.xyz \| bash && foundryup` |
| **Python 3** | JSON 파싱용 (macOS 기본 포함) |

```bash
# 설치 확인
forge --version    # forge 0.3.x 이상
anvil --version
cast --version
```

## 프로젝트 클론 및 의존성 설치

```bash
git clone https://github.com/joey-nx/stealth-id.git
cd stealth-id/contracts

# Foundry 의존성 설치 (forge-std, OpenZeppelin)
forge install
```

### 디렉토리 구조

```
contracts/
├── src/erc8004/                          # ERC-8004 레퍼런스 컨트랙트
│   ├── IdentityRegistryUpgradeable.sol   # Agent 등록 + 메타데이터 (ERC-721)
│   ├── ReputationRegistryUpgradeable.sol # 평판 피드백
│   ├── ValidationRegistryUpgradeable.sol # 검증 요청/응답
│   ├── HardhatMinimalUUPS.sol            # 프록시 초기 구현체 (placeholder)
│   └── ERC1967Proxy.sol                  # UUPS 프록시
├── script/
│   ├── DeployERC8004.s.sol               # Forge 배포 스크립트
│   └── alias-vanity.sh                   # 공식 vanity 주소로 alias
├── test/
│   └── ERC8004Integration.t.sol          # 통합 테스트
├── deployments/
│   └── local.json                        # 배포된 컨트랙트 주소 (자동 생성)
├── foundry.toml
└── Makefile
```

## 빌드 및 테스트

```bash
# 컴파일
make build

# 테스트 실행
make test

# 가스 리포트
make gas
```

## 로컬 Anvil 배포

### 1. Anvil 노드 시작

터미널을 열고 Anvil을 실행합니다:

```bash
make anvil
```

Anvil이 `http://127.0.0.1:8545`에서 실행됩니다. 기본 계정 10개와 각각 10,000 ETH가 제공됩니다.

### 2. 컨트랙트 배포

새 터미널에서:

```bash
# 배포 + vanity 주소 alias (한 번에)
make local
```

또는 단계별로:

```bash
# Step 1: 컨트랙트 배포 (staging 주소)
make deploy

# Step 2: 공식 0x8004... vanity 주소로 alias
make alias
```

### 3. 배포 확인

```bash
# 배포된 주소 조회
make addresses

# 직접 호출 테스트
cast call 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432 \
    "getVersion()(string)" --rpc-url http://127.0.0.1:8545
# → "2.0.0"
```

## 배포 주소

`make local` 실행 후 공식 ERC-8004 메인넷 vanity 주소로 사용 가능:

| Contract | Address | 역할 |
|----------|---------|------|
| **IdentityRegistry** | `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432` | Agent 등록, 메타데이터, ERC-721 NFT |
| **ReputationRegistry** | `0x8004BAa17C55a88189AE136b182e5fdA19dE9b63` | 서비스의 Agent 평판 피드백 |
| **ValidationRegistry** | `0x8004Cc8439f36fd5F9F049D9fF86523Df6dAAB58` | Agent 검증 요청/응답 |

> **참고**: 로컬 Anvil에서는 실제 배포 후 `anvil_setCode`로 vanity 주소에 코드를 복사하는 방식입니다.
> 실제 테스트넷/메인넷에서는 SAFE Singleton Factory + CREATE2를 통해 동일 주소에 배포됩니다.

## 배포 아키텍처

UUPS 프록시 패턴으로 배포됩니다:

```
ERC1967Proxy ──→ HardhatMinimalUUPS (placeholder)
                        │
                  upgradeToAndCall()
                        │
                        ▼
              실제 Registry 구현체
              (Identity/Reputation/Validation)
```

배포 순서:
1. **구현체 배포**: MinimalUUPS + 3개 Registry 구현체
2. **프록시 배포**: 각 Registry에 대해 ERC1967Proxy → MinimalUUPS로 초기화
3. **업그레이드**: 각 프록시를 MinimalUUPS → 실제 Registry로 업그레이드
4. **Alias**: `anvil_setCode`로 vanity 주소에 복사 + 내부 참조 수정

## Anvil 기본 계정

| # | Address | Private Key |
|---|---------|-------------|
| 0 | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |
| 1 | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d` |
| 2 | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | `0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a` |

- Account #0: 컨트랙트 배포자 (owner)
- Account #1~9: 테스트용 (agent owner, service, validator 등)

> **주의**: 이 키들은 공개된 Anvil 기본 키입니다. 절대 실제 네트워크에서 사용하지 마세요.

## 사용 예시

### Agent 등록

```bash
# Account #1로 Agent 등록
cast send 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432 \
    "register(string)(uint256)" "https://example.com/agent-metadata.json" \
    --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d \
    --rpc-url http://127.0.0.1:8545
```

### Agent 조회

```bash
# Agent ID 0의 owner 조회
cast call 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432 \
    "ownerOf(uint256)(address)" 0 \
    --rpc-url http://127.0.0.1:8545

# Agent의 메타데이터 URI 조회
cast call 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432 \
    "tokenURI(uint256)(string)" 0 \
    --rpc-url http://127.0.0.1:8545
```

### 평판 피드백

```bash
# Account #2(서비스)가 Agent 0에 평판 피드백
cast send 0x8004BAa17C55a88189AE136b182e5fdA19dE9b63 \
    "giveFeedback(uint256,int128,uint8,string,string,string,string,bytes32)" \
    0 85 0 "reliability" "stealth-id" "https://service.com" "" 0x0000000000000000000000000000000000000000000000000000000000000000 \
    --private-key 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a \
    --rpc-url http://127.0.0.1:8545
```

## Makefile 명령어 요약

| 명령 | 설명 |
|------|------|
| `make build` | 컨트랙트 컴파일 |
| `make test` | 전체 테스트 실행 |
| `make anvil` | Anvil 노드 시작 (foreground) |
| `make deploy` | Anvil에 컨트랙트 배포 |
| `make alias` | vanity 주소로 alias |
| `make local` | deploy + alias (전체 셋업) |
| `make addresses` | 배포된 주소 조회 |
| `make gas` | 가스 리포트 |
| `make clean` | 빌드 아티팩트 삭제 |

## 트러블슈팅

### Anvil 연결 실패

```
Error: server returned an error response: error code -32000
```

Anvil이 실행 중인지 확인:
```bash
curl -s http://127.0.0.1:8545 -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

### Nonce 오류

Anvil을 재시작하면 nonce가 초기화되지만 MetaMask 등 지갑의 nonce 캐시는 남아있을 수 있습니다:
```bash
# Anvil 재시작
pkill anvil && make anvil

# 또는 MetaMask에서 "Reset Account" (Settings → Advanced)
```

### 배포 주소가 달라짐

Anvil은 **매번 동일한 상태로 시작**하므로, 같은 deployer + 같은 nonce 순서 = 같은 주소입니다.
주소가 달라졌다면 Anvil을 재시작한 후 `make local`을 다시 실행하세요.
