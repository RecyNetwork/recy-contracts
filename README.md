# RecyReport

A protocol for reporting and validating recycling data on EVM blockchains.

## Usage

The RecyReport protocol allows recyclers to report recycling data, which can be validated by validators and used to generate reports. The protocol is designed to be modular and upgradeable, allowing for future enhancements and changes.

### Requirements

- The Foundry toolchain for building, testing, and deploying smart contracts on EVM-compatible blockchains.
- The OpenZeppelin contracts library to deploy battletested contracts, ensuring that the protocol meets the highest security standards.
- The OpenZeppelin upgradable contracts library to deploy upgradeable contracts, ensuring that the protocol can evolve without losing existing data or functionality.

### Fresh deployment required

Existing testnet deployments are obsolete. Deploy a new token, attributes, SVG, data contract,
report implementation, factory, and proxies; do not upgrade or reuse the historical proxies.
Contract and proxy addresses in `config/contracts.json` are reset to zero. Record each new address
before running dependent deployment scripts; keep protocol-wallet and role configuration separate.

`RecyToken` is a standard LayerZero V2 OFT (ERC-20 with multichain transfers), with constructor:
`(string name, string symbol, uint256 initialSupply, address lzEndpoint, address tokenOwner, uint256 issuanceChainId)`.
Initial supply is in whole tokens; `mint`, `burn`, `burnFrom`, and `totalIssued` use token wei.

Use one shared **EVM `issuanceChainId`** for every token in the OFT network. Only that chain
permits initial issuance, owner minting, and report initialization. Satellite deployments must
start with zero supply; they support ordinary transfers, burns, and OFT bridging, not new issuance.
`totalIssued` increases only for initial issuance and owner minting. Report reward epochs use
that counter, never chain-local `totalSupply()`: bridging or burning cannot roll an epoch backward.
No custom cross-chain reward messages or global-supply synchronization are used.

Each network configuration needs its local `addresses.lzEndpoint` and the shared `issuanceChainId`.
Sepolia is the configured testnet issuance chain (`11155111`); the local development network is
independent (`31337`). A satellite testnet must also use `11155111`, not its own EVM chain ID.
For local deployment, deploy a test Endpoint V2 and configure its address before running the token script.
Record newly deployed token addresses manually in `config/contracts.json`.

Deployment alone does not enable cross-chain transfers. Configure standard LayerZero send/receive
libraries, DVNs, confirmations, and executor options, then set the intended OFT peers in both
directions. `setPeer` takes a **LayerZero endpoint ID**, not an EVM chain ID. All peers must use
the same issuance chain configuration; review ownership/delegate permissions before opening routes.
Follow the [official OFT deployment and wiring guide](https://docs.layerzero.network/v2/developers/evm/oft/quickstart).

The report's configurable ERC-2771 forwarder uses the ERC-7201 namespace
`recy.storage.RecyReport.Forwarder` and starts disabled. Only an admin can enable it.
Before any future upgrade, validate storage compatibility against that deployment's build artifacts.
Passing tests is not a security audit or a guarantee of security.

### Build

```sh
forge build
```

### Test

```sh
forge test
```

### Deploy locally with Anvil

#### Anvil

- make sure you have run `anvil` in a separate terminal window to start a local EVM node.

```sh
# Deploy RecyToken (ERC20 for testing/rewards)
forge script script/deploy/RecyTokenDeploy.s.sol:RecyTokenDeploy --rpc-url 127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast

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

#### Sepolia

- make sure you have the `deployer` account set up in your wallets using `cast wallet import [name] --private-key [private-key]` with `[name]` being `deployer` and `[private-key]` being the private key of the sepolia funded deployer account.
- make sure you have set up the `sepolia` network in `foundry.toml` with the correct RPC URL.

##### Deploy on Sepolia

```sh
forge script script/deploy/RecyTokenDeploy.s.sol:RecyTokenDeploy --account deployer --verify --broadcast --rpc-url sepolia

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

The project uses a configuration system to manage contract addresses across different networks. Configuration is stored in `config/contracts.json` and automatically updated by deployment scripts.

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
