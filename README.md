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

Historical testnet report deployments are obsolete. The recorded Sepolia and Base Sepolia OFTs are
reused unchanged; Base Sepolia remains an OFT satellite and gets no report stack. On Sepolia,
`RecyReportDeploy` is the fresh-only, one-command report-stack orchestrator: it deploys and wires the
complete stack, applies configured roles, removes the factory's operational roles, and records all
six planned addresses. Those addresses are not live deployments until every broadcast receipt
succeeds. Standalone component deployment scripts still require their addresses to be recorded
manually before dependent scripts run.

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

Start `anvil` in a separate terminal, deploy a local LayerZero Endpoint V2, and export the endpoint,
RPC URL, and one Anvil account whose public test key may sign the local deployment:

```sh
export ANVIL_RPC_URL=http://127.0.0.1:8545
export ANVIL_DEPLOYER=<ANVIL_ACCOUNT_ADDRESS>
export ANVIL_PRIVATE_KEY=<CORRESPONDING_PUBLIC_ANVIL_PRIVATE_KEY>
export LOCAL_LZ_ENDPOINT=<DEPLOYED_LOCAL_ENDPOINT_ADDRESS>

# Deploy the standalone local token used by the report stack.
forge create src/RecyToken.sol:RecyToken \
  --rpc-url "$ANVIL_RPC_URL" \
  --private-key "$ANVIL_PRIVATE_KEY" \
  --broadcast \
  --constructor-args RecyToken cRECY 0 "$LOCAL_LZ_ENDPOINT" "$ANVIL_DEPLOYER" 31337
```

Before deploying the report stack, update the `31337` entry in `config/contracts.json` so
`addresses.tokenOwner` is `$ANVIL_DEPLOYER`, `addresses.lzEndpoint` is `$LOCAL_LZ_ENDPOINT`, and
`contracts.token` is the newly deployed token. Leave `issuanceChainId` as `31337`. For a fresh run,
all six report-stack fields must be zero: `contracts.reportAttributes`, `contracts.reportSvg`,
`contracts.reportData`, `contracts.reportImplementation`, `contracts.factory`, and
`proxies.default.address`.

Dry-run the same orchestrator first. It checks the local token, endpoint, owner, proxy settings, and
role separation, exercises the complete deployment, and leaves `config/contracts.json` unchanged:

```sh
forge script script/deploy/RecyReportDeploy.s.sol:RecyReportDeploy \
  --rpc-url "$ANVIL_RPC_URL" \
  --sender "$ANVIL_DEPLOYER"
```

Then broadcast the local deployment:

```sh
forge script script/deploy/RecyReportDeploy.s.sol:RecyReportDeploy \
  --rpc-url "$ANVIL_RPC_URL" \
  --private-key "$ANVIL_PRIVATE_KEY" \
  --broadcast --slow
```

The fresh proxy deliberately has no trusted forwarder. A standalone forwarder can be deployed
separately for development, but this is outside the fresh flow and does not wire it into the proxy:

```sh
forge script script/deploy/RecyReportTrustedForwarderDeploy.s.sol:RecyReportTrustedForwarderDeploy \
  --rpc-url "$ANVIL_RPC_URL" \
  --private-key "$ANVIL_PRIVATE_KEY" \
  --broadcast
```

#### Sepolia report-stack deployment

The recorded OFTs must already be deployed and configured by the separate two-chain rollout. These
instructions deploy only a fresh Sepolia report stack; they do not deploy on Base Sepolia and do not
claim that a public-chain report stack already exists.

The `proxy` environment selector defaults to the config key `default`. That key remains `default`;
the factory registry identity comes from the separate configured `name` (`RecyReport`), while the
proxy's token identity uses the configured `name` and `symbol` (`RecyReport`/`cRECYr`).

##### Preflight and dry run

Before signing:

1. Keep the six Sepolia report-stack fields listed above at zero. A fresh run rejects any nonzero
   field; this protects a partial deployment from being overwritten.
2. Confirm that the configured Sepolia token and LayerZero endpoint contain code, and that the token
   is `RecyToken`/`cRECY` with issuance chain `11155111` and owner
   `0x3402ce3b5f88c852c0d6992C69A03095d1345BBd`.
3. Review the `default` proxy's `name`, `symbol`, reward shares, unlock delay, protocol recipient,
   and role arrays. Role entries must be nonzero and unique, and no recycler or auditor may also be
   an admin, emergency account, or member of the opposite operational role.
4. Ensure the encrypted Foundry account named `deployer` resolves to
   `0x3402ce3b5f88c852c0d6992C69A03095d1345BBd` and has enough Sepolia ETH for deployment gas.

The unsigned simulation uses the configured token owner as `--sender` and does not modify the
registry:

```sh
forge script script/deploy/RecyReportDeploy.s.sol:RecyReportDeploy \
  --sender 0x3402ce3b5f88c852c0d6992C69A03095d1345BBd \
  --rpc-url sepolia
```

##### Sign and broadcast

Live signing starts only with the following command. Foundry opens the encrypted `deployer`
keystore in this terminal:

```sh
forge script script/deploy/RecyReportDeploy.s.sol:RecyReportDeploy \
  --rpc-url sepolia \
  --account deployer \
  --broadcast --slow
```

To request explorer verification in the same invocation, set the explorer credential and override
the repository's legacy Sepolia verifier URL with Etherscan V2:

```sh
forge script script/deploy/RecyReportDeploy.s.sol:RecyReportDeploy \
  --rpc-url sepolia \
  --account deployer \
  --broadcast --slow \
  --verify \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  --verifier-url 'https://api.etherscan.io/v2/api?chainid=11155111'
```

The invocation deploys `RecyReportAttributes`, `RecyReportSvg`, `RecyReportData`, the `RecyReport`
implementation, `RecyReportFactoryV2`, and the `default` `RecyReport` proxy. Foundry may also deploy
the linked `RecyReward` library and records it in its broadcast artifacts; it is not a seventh
report-stack registry field. Do not rely on an exact transaction count.

During broadcast preparation, the script executes locally and records all six planned addresses in
`config/contracts.json` before Foundry sends the transactions. Planned addresses are not evidence
of live contracts. They become the deployment record only after every receipt succeeds and the
signerless readback passes:

```sh
forge script script/deploy/RecyReportDeploy.s.sol:RecyReportDeploy \
  --rpc-url sepolia \
  --sig 'check()'
```

If sending is interrupted, keep both `config/contracts.json` and Foundry's broadcast artifacts.
Resume the saved broadcast with the same target, RPC, account, and pacing options:

```sh
forge script script/deploy/RecyReportDeploy.s.sol:RecyReportDeploy \
  --rpc-url sepolia \
  --account deployer \
  --resume --broadcast --slow
```

Keep any verification options used by the original invocation, wait for every receipt, and run
`check()` afterward. `--resume` reuses the saved transactions without rerunning the Solidity
deployment code; after the broadcast is complete, another resume has nothing to send. Never zero
the registry and blindly start a new deployment after a partial send.

The configured token owner is the broadcaster and becomes the owner of the attributes, SVG
metadata, and factory contracts. The orchestrator grants the configured admin, emergency,
recycler, and auditor roles, then revokes the factory's `RECYCLER_ROLE` and `AUDITOR_ROLE`; the
factory retains its required admin and emergency authority. The initial
`applyAllRolesFromConfig()` call is therefore unnecessary.

The fresh flow does not mint reports or tokens, move or fund cRECY, deploy a Distribution contract,
change OFT ownership or peers, or configure a trusted forwarder. It also does not register fund
wallets on behalf of role holders.
An unfunded report proxy cannot validate reports with a nonzero payout. Report submission,
principal self-registration, and separately authorized funding must be performed later by their
proper recycler, role-holder, and funding signers; possession of the deployment key alone does not
authorize report submission.

##### Role management

`ManageRoles` selects `proxies.default.address` and the factory from the current chain's config, so
these methods take only the principal address. Mutating calls must be signed by the configured
factory owner.

###### Grant auditor role

```sh
forge script script/ManageRoles.s.sol:ManageRoles \
  --sig "grantAuditor(address)" <AUDITOR_ADDRESS> \
  --rpc-url sepolia --account deployer --broadcast
```

###### Revoke auditor role

```sh
forge script script/ManageRoles.s.sol:ManageRoles \
  --sig "revokeAuditor(address)" <AUDITOR_ADDRESS> \
  --rpc-url sepolia --account deployer --broadcast
```

###### Check if address has auditor role

```sh
forge script script/ManageRoles.s.sol:ManageRoles \
  --sig "checkAuditor(address)" <AUDITOR_ADDRESS> \
  --rpc-url sepolia
```

###### Grant recycler role

```sh
forge script script/ManageRoles.s.sol:ManageRoles \
  --sig "grantRecycler(address)" <RECYCLER_ADDRESS> \
  --rpc-url sepolia --account deployer --broadcast
```

###### Revoke recycler role

```sh
forge script script/ManageRoles.s.sol:ManageRoles \
  --sig "revokeRecycler(address)" <RECYCLER_ADDRESS> \
  --rpc-url sepolia --account deployer --broadcast
```

###### Check if address has recycler role

```sh
forge script script/ManageRoles.s.sol:ManageRoles \
  --sig "checkRecycler(address)" <RECYCLER_ADDRESS> \
  --rpc-url sepolia
```

##### List all deployed proxies

```sh
forge script script/ManageRoles.s.sol:ManageRoles \
  --sig "listProxies()" \
  --rpc-url sepolia
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
addresses. `RecyTokenDeploy` automatically records planned token addresses during broadcast
preparation. `RecyReportDeploy` likewise records all six planned report-stack addresses for its
selected proxy (`proxy=default` unless overridden); its dry run preserves the file, and an
interrupted broadcast must retain those values for `--resume`. Addresses written during preparation
are not live until their receipts succeed. Standalone component deployment scripts only log their
addresses, which must be copied into the matching JSON fields manually.

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
