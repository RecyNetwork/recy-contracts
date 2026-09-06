# RecyReport

A protocol for reporting and validating recycling data on EVM blockchains.

## Usage

The RecyReport protocol allows recyclers to report recycling data, which can be validated by validators and used to generate reports. The protocol is designed to be modular and upgradeable, allowing for future enhancements and changes.

### Requirements

- Foundry `v1.8.1` for building, testing, and deploying EVM smart contracts.
- Solidity `0.8.36`, selected by the exact `solc` pin in `foundry.toml`; compatible source
  pragmas remain unchanged.
- `forge-std` `v1.16.2`.
- OpenZeppelin Contracts `v5.7.0` and OpenZeppelin Contracts Upgradeable `v5.7.0`.
  The libraries are vendored under `lib/`.
- Unchanged vendored dependencies: LayerZero V2 `2.0.2`, `@layerzerolabs/oft-evm`
  `4.0.1`, `@layerzerolabs/oapp-evm` `0.4.1`,
  `@layerzerolabs/test-devtools-evm-foundry` `8.0.1`,
  `@layerzerolabs/test-devtools-evm-hardhat` `0.5.3`, and `solidity-bytes-utils`
  `0.8.4`.
- The interface-only `@layerzerolabs/lz-evm-v1-0.7` test dependency is pinned to npm
  `3.0.148` for LayerZero's test mocks. It is not a runtime dependency, and its upstream
  `BUSL-1.1` license is preserved.

Install the reproducible local Foundry version and confirm the active toolchain:

```sh
foundryup --install v1.8.1
forge --version
```

The `foundryup --install <version>` form is the installer's supported syntax. The repository's
compiler pin determines the precise Solidity version used by Forge.

The Forge suite uses LayerZero's full Foundry OFT harness in place of the former Hardhat mock.
The only vendored compatibility patches replace deprecated `DoubleEndedQueue.at` calls with the
existing `pos` API and rename a mock signature-recovery error local; they do not change behavior.

### Fresh deployment required

Historical testnet deployments are obsolete. Fresh OFTs are already recorded for Sepolia and Base
Sepolia; the token rollout reuses those addresses. Deploy the report implementation, factory, and
proxies on Sepolia only; do not upgrade or reuse historical proxies. Base Sepolia is an OFT satellite
and needs no report or proxy deployment. The token script records its addresses automatically;
other deployment scripts still require manually recording addresses before dependent deployments.

The recorded OFT token contracts are immutable deployments and are reused by the rollout.
Updating the compiler, Foundry, or vendored dependencies changes only bytecode newly compiled
for future deployments; it never changes or upgrades those live contracts. These version pins
do not claim that the updated stack has already been exercised against live contracts.

`RecyToken` is a standard LayerZero V2 OFT (ERC-20 with multichain transfers), with constructor:
`(string name, string symbol, uint256 initialSupply, address lzEndpoint, address tokenOwner, uint256 issuanceChainId)`.
Initial supply is in whole tokens; `mint`, `burn`, `burnFrom`, and `totalIssued` use token wei.

Report initialization and proxy deployment require a nonzero protocol recipient even when the
protocol share is zero. Numeric proxy and OFT configuration values reject overflowing downcasts
instead of silently wrapping.

Use one shared **EVM `issuanceChainId`** for every token in the OFT network. Sepolia is the issuance
chain (`11155111`), so both public-testnet deployments use `issuanceChainId = 11155111`. Both fresh
deployments start with zero supply. Only Sepolia permits later owner minting and report initialization;
the Base Sepolia satellite supports ordinary transfers, burns, and OFT bridging, not new issuance.
`totalIssued` increases only for initial issuance and owner minting. Report reward epochs use that
counter, never chain-local `totalSupply()`: bridging or burning cannot roll an epoch backward.
No custom cross-chain reward messages or global-supply synchronization are used.

Localhost remains an independent `31337` issuance domain and has no public OFT route. Entries
without an `oft` object are excluded from the multichain token rollout.

#### Sepolia ↔ Base Sepolia OFT rollout

| Network | EVM chain ID | LayerZero EID | Foundry RPC alias | Role |
| --- | ---: | ---: | --- | --- |
| Sepolia | `11155111` | `40161` | `sepolia` | issuance chain |
| Base Sepolia | `84532` | `40245` | `base-sepolia` | zero-issuance satellite |

The configured token owner and LayerZero delegate on both chains is
`0x3402ce3b5f88c852c0d6992C69A03095d1345BBd`. The `deployer` account used for configuration and
wiring must resolve to that address and must be funded on both chains. Keep the encrypted account
and its password local:

```sh
cast wallet import deployer --interactive
cast wallet address --account deployer
```

Run every command containing `--broadcast` yourself in a local terminal so Foundry unlocks the
encrypted keystore locally. Do not put a private key or keystore password in a command, repository,
chat, or remote session. The scripts contain no private-key handling.

##### Deploy and wire all configured OFTs

Run one command; Foundry unlocks the selected keystore once for the entire multichain invocation:

```sh
forge script script/deploy/RecyTokenDeploy.s.sol:RecyTokenDeploy \
  --account deployer --broadcast --slow
```

No `--rpc-url` is needed. Every network entry with an `oft` object participates, using its
`oft.rpcAlias` from `foundry.toml`. The script validates RPC chain IDs, a shared owner and issuance
chain, unique EIDs, and reciprocal `oft.peerChainIds`; it supports multiple configured peers.
It reuses compatible recorded tokens and deploys zero-supply tokens only where needed.
It then configures every route's libraries, DVNs, executor, and receive options, opens the
configured peers, and checks the complete simulated result. Peer mappings use LayerZero EIDs,
not EVM chain IDs. Unrelated existing peers and security changes on already-open routes are rejected.

To simulate the same rollout without signing or changing the address registry:

```sh
forge script script/deploy/RecyTokenDeploy.s.sol:RecyTokenDeploy \
  --sender 0x3402ce3b5f88c852c0d6992C69A03095d1345BBd
```

During `--broadcast`, new token addresses are automatically written to
`config/contracts.json` after successful local execution. **Foundry runs Solidity scripts before
broadcasting:** these addresses are planned until their deployment receipts succeed.
Dry-runs never write them. Do not run report, factory, or proxy deployments until the token
broadcast succeeds, and never run those deployments on Base Sepolia.

Cross-chain broadcasts are not atomic. Foundry broadcasts per-chain transaction sequences;
a later failure does not undo deployments or configuration transactions already confirmed.
Wait for the entire invocation to succeed before minting or bridging. If broadcasting fails,
keep the registry and Foundry broadcast artifacts and resume the saved transactions:

```sh
forge script script/deploy/RecyTokenDeploy.s.sol:RecyTokenDeploy \
  --account deployer --broadcast --resume --multi --slow
```

Do not use that signer for other transactions before resuming: saved nonces must still match.
A normal rerun reuses confirmed deployments and skips matching settings. A recorded address with
no code is deployable only if it matches the owner's next CREATE address; otherwise the script
refuses to replace it.

##### Pathway security and execution choices

Both chains use Endpoint V2 `0x6edce65403992e310a62460808c4b910d972f10f`. Each direction uses
ULN 302, a `10000` byte maximum message size, the chain-local executor, and **both** LayerZero Labs
and Nethermind as required DVNs.

The chain-local library, executor, and numerically sorted DVN addresses are recorded under each
network's `oft` object in `config/contracts.json`; keep that file as the address source of truth.

The explicit ULN configuration has `requiredDVNCount = 2`, `optionalDVNCount = 255` (LayerZero's NIL
value, so defaults are **not inherited**), `optionalDVNThreshold = 0`, and an empty optional-DVN
list. The local network's two DVN addresses are used in both its send and receive ULN settings.

`confirmations = 2` belongs to the network **as a message source**. A local send ULN therefore uses
the local network's value, while a local receive ULN uses the remote source network's value. Both
values happen to be `2` for this testnet route. Two confirmations is a testnet-only choice, not a
production security recommendation.

The enforced Type 3 `lzReceive` option supplies `100000` destination gas and zero native value for
both OFT message types (`SEND = 1` and `SEND_AND_CALL = 2`). Configuration of a source pathway uses
the **remote destination's** `lzReceiveGas`. For `SEND_AND_CALL`, the caller remains responsible for
supplying suitable `lzCompose` option(s); the enforced receive option does not budget compose
execution.

##### Check the complete multichain rollout

After the broadcast succeeds, verify every configured token and route without unlocking a wallet:

```sh
forge script script/deploy/RecyTokenDeploy.s.sol:RecyTokenDeploy --sig "check()"
```

Deployment, security configuration, and peer wiring share the token deploy entrypoint; there are
no separate configuration or wiring commands.

This OFT rollout requires no token or report ownership transfer: the token constructor assigns the
configured owner/delegate, and the configuration scripts do not deploy or modify report contracts.

Configuration values come from the
[LayerZero deployment metadata](https://metadata.layerzero-api.com/v1/metadata/deployments).
See the official [OFT quickstart](https://docs.layerzero.network/v2/developers/evm/oft/quickstart),
[DVN and executor configuration guide](https://docs.layerzero.network/v2/developers/evm/configuration/dvn-executor-config),
and [message execution options guide](https://docs.layerzero.network/v2/developers/evm/configuration/options).

The report's configurable ERC-2771 forwarder uses the ERC-7201 namespace
`recy.storage.RecyReport.Forwarder` and starts disabled. Only an admin can enable it.
Before any future upgrade, validate storage compatibility against that deployment's build artifacts.
Passing tests is not a security audit or a guarantee of security.

### Development and quality

Use the repository targets rather than assembling quality commands by hand:

```sh
make fmt           # Apply Forge formatting
make format-check  # Check formatting without changing files
make lint          # Enforce high, medium, and low correctness lints
make lint-all      # Also report info, gas, and code-size advisories
make build-check   # Build with compiler warnings denied and no cache
make test          # Run the full Forge test suite
make check         # Run format, lint, build, and test gates in order
make install-hooks # Install the repository pre-commit hook
```

`forge fmt` is the supported autofix, including thousands separators and import ordering.
There is no `forge lint --fix`; resolve lint findings in source. The default policy denies compiler
warnings and enforces high-, medium-, and low-severity correctness lints across contracts, scripts,
and tests without blanket exclusions. Information, gas, and code-size advisories are opt-in through
`make lint-all`. Intentional test or script patterns and proven invariant false positives use narrow,
documented inline waivers.

`make build-check` forces `--no-cache`, preventing a cached permissive build from bypassing compiler
warnings. The installed pre-commit gate checks the working tree without modifying, staging, or
restaging files. VS Code formats Solidity with Forge on save. CI pins Foundry `v1.8.1` and runs the
strict format, lint, warning-free build, and full-test gates.

### Deploy locally with Anvil

#### Anvil

- make sure you have run `anvil` in a separate terminal window to start a local EVM node.
- deploy a local Endpoint V2 first and set `LOCAL_LZ_ENDPOINT` to its address. The standalone
  local token below has issuance chain ID `31337`; record its address under `.31337.contracts.token`.
  The multichain rollout uses `oft.rpcAlias` and is **not** redirected to Anvil by `--rpc-url`.

```sh
# Deploy a standalone local RecyToken for report testing (public Anvil test key only)
forge create src/RecyToken.sol:RecyToken \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast \
  --constructor-args RecyToken cRECY 0 "$LOCAL_LZ_ENDPOINT" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 31337

# Deploy RecyReportAttributesDeploy
forge script script/deploy/RecyReportAttributesDeploy.s.sol:RecyReportAttributesDeploy --rpc-url 127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast

# Deploy RecyReportSvgDeploy
forge script script/deploy/RecyReportSvgDeploy.s.sol:RecyReportSvgDeploy --rpc-url 127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast

# Deploy RecyReportDataDeploy (depends on above contracts)
forge script script/deploy/RecyReportDataDeploy.s.sol:RecyReportDataDeploy --rpc-url 127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast

# Deploy complete upgradeable system
forge script script/deploy/RecyReportDeploy.s.sol:RecyReportDeploy --rpc-url 127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast

# Deploy RecyReportFactoryDeploy
forge script script/deploy/RecyReportFactoryDeploy.s.sol:RecyReportFactoryDeploy --rpc-url 127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast

# Deploy RecyReportProxyDeploy
forge script script/deploy/RecyReportProxyDeploy.s.sol:RecyReportProxyDeploy --rpc-url 127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast

# Deploy ERC2771 Trusted Forwarder (for gasless meta-transactions)
forge script script/deploy/RecyReportTrustedForwarderDeploy.s.sol:RecyReportTrustedForwarderDeploy --rpc-url 127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast
```

#### Sepolia report-stack deployment

Complete the two-chain OFT rollout above separately. The commands below deploy only the fresh
Sepolia report stack; there is no corresponding Base Sepolia report stack.

##### Deploy report contracts on Sepolia

```sh

forge script script/deploy/RecyReportAttributesDeploy.s.sol:RecyReportAttributesDeploy --account deployer --verify --broadcast --rpc-url sepolia

forge script script/deploy/RecyReportSvgDeploy.s.sol:RecyReportSvgDeploy --account deployer --verify --broadcast --rpc-url sepolia

forge script script/deploy/RecyReportDataDeploy.s.sol:RecyReportDataDeploy --account deployer --verify --broadcast --rpc-url sepolia

forge script script/deploy/RecyReportDeploy.s.sol:RecyReportDeploy --account deployer --verify --broadcast --rpc-url sepolia

forge script script/deploy/RecyReportFactoryDeploy.s.sol:RecyReportFactoryDeploy --account deployer --verify --broadcast --rpc-url sepolia

proxy=default forge script script/deploy/RecyReportProxyDeploy.s.sol:RecyReportProxyDeploy --account deployer --verify --broadcast --rpc-url sepolia
```

##### Role management

###### Apply all roles from config to the default proxy

```sh
forge script script/ManageRoles.s.sol:ManageRoles --sig "applyAllRolesFromConfig()" --rpc-url sepolia --account deployer --broadcast
```

###### Grant auditor role

```sh
 forge script script/ManageRoles.s.sol:ManageRoles \
   --sig "grantAuditor(address,address)" <PROXY_ADDRESS> <AUDITOR_ADDRESS> \
   --rpc-url sepolia --account deployer --broadcast
```

###### Revoke auditor role

```sh
 forge script script/ManageRoles.s.sol:ManageRoles \
   --sig "revokeAuditor(address,address)" <PROXY_ADDRESS> <AUDITOR_ADDRESS> \
   --rpc-url sepolia --account deployer --broadcast
```

###### Check if address has auditor role

```sh
 forge script script/ManageRoles.s.sol:ManageRoles \
   --sig "checkAuditor(address,address)" <PROXY_ADDRESS> <AUDITOR_ADDRESS> \
   --rpc-url sepolia
```

###### Grant recycler role

```sh
forge script script/ManageRoles.s.sol:ManageRoles \
  --sig "grantRecycler(address,address)" <PROXY_ADDRESS> <RECYCLER_ADDRESS> \
  --rpc-url sepolia --account deployer --broadcast
```

###### Revoke recycler role

```sh
 forge script script/ManageRoles.s.sol:ManageRoles \
   --sig "revokeRecycler(address,address)" <PROXY_ADDRESS> <RECYCLER_ADDRESS> \
   --rpc-url sepolia --account deployer --broadcast
```

###### Check if address has recycler role

```sh
 forge script script/ManageRoles.s.sol:ManageRoles \
   --sig "checkRecycler(address,address)" <PROXY_ADDRESS> <RECYCLER_ADDRESS> \
   --rpc-url sepolia
```

##### List all deployed proxies

```sh
 forge script script/ManageRoles.s.sol:ManageRoles \
   --sig "listProxies()" \
   --rpc-url sepolia
```

##### Populate

```sh
forge script script/PopulateRecyReport.s.sol:PopulateRecyReportScript --account deployer --broadcast --rpc-url sepolia
```

#### Mainnet

- make sure you have the `deployer` account set up in your wallets using `cast wallet import [name] --private-key [private-key]` with `[name]` being `deployer` and `[private-key]` being the private key of the mainnet funded deployer account.
- make sure you have set up the `mainnet` network in `foundry.toml` with the correct RPC URL.

```sh
forge script script/RecyReport.s.sol:RecyReportScript --account deployer --verify --broadcast --rpc-url mainnet
```

### Cast

```sh
cast --to-base 202 hex
```

### Help

```sh
forge --help
anvil --help
cast --help
```

## Configuration

The project uses `config/contracts.json` as the source of truth for per-network settings and contract
addresses. `RecyTokenDeploy` discovers networks through their `oft` objects and automatically records
planned token addresses during broadcast preparation, as described above. Other deployment scripts
log the address to record; update their matching JSON fields manually.

### Environment Variables

Before deploying, set up the required environment variables:

```sh
export ETHERSCAN_API_KEY=your_etherscan_api_key
export CELOSCAN_API_KEY=your_celoscan_api_key
```

## Troubleshooting

### Clean Build

If you encounter build artifacts issues:

```sh
forge clean
forge build
```

### Proxies

#### Upgrade Proxy

```sh
forge script script/deploy/RecyReportProxyUpgrade.s.sol:RecyReportProxyUpgrade --sig 'upgradeProxy(address,address)' --rpc-url sepolia --account deployer --broadcast <proxy> <implementation>
```

#### Update Data Contract

```sh
cast send <PROXY_ADDRESS> "setDataContract(address)" <NEW_DATA_CONTRACT_ADDRESS> --rpc-url sepolia --account deployer
```

#### List All Proxies

```sh
forge script script/deploy/RecyReportProxyUpgrade.s.sol:RecyReportProxyUpgrade --sig 'listAllProxiesWithImplementations()' --rpc-url sepolia --account deployer --broadcast
```
