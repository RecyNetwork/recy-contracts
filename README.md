# RecyReport

A protocol for reporting and validating recycling data on EVM blockchains.

## Usage

The RecyReport protocol allows recyclers to report recycling data, which can be validated by validators and used to generate reports. The protocol is designed to be modular and upgradeable, allowing for future enhancements and changes.

### Requirements

- The Foundry toolchain for building, testing, and deploying smart contracts on EVM-compatible blockchains.
- The OpenZeppelin contracts library to deploy battletested contracts, ensuring that the protocol meets the highest security standards.
- The OpenZeppelin upgradable contracts library to deploy upgradeable contracts, ensuring that the protocol can evolve without losing existing data or functionality.

### Build

```sh
forge build
```

### Test

```sh
forge test
```

### Deploy

#### Anvil

- make sure you have run `anvil` in a separate terminal window to start a local Ethereum node.

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
```

#### Sepolia

- make sure you have the `deployer` account set up in your wallets using `cast wallet import [name] --private-key [private-key]` with `[name]` being `deployer` and `[private-key]` being the private key of the sepolia funded deployer account.
- make sure you have set up the `sepolia` network in `foundry.toml` with the correct RPC URL.

##### Deploy

```sh
forge script script/RecyReport.s.sol:RecyReportTestnetScript --account deployer --verify --broadcast --rpc-url sepolia
```

#### Alfajores

- make sure you have the `deployer` account set up in your wallets using `cast wallet import [name] --private-key [private-key]` with `[name]` being `deployer` and `[private-key]` being the private key of the alfajores funded deployer account.
- make sure you have set up the `alfajores` network in `foundry.toml` with the correct RPC URL.

##### Deploy

```sh
forge script script/deploy/RecyTokenDeploy.s.sol:RecyTokenDeploy --account deployer --verify --broadcast --rpc-url alfajores

forge script script/deploy/RecyReportAttributesDeploy.s.sol:RecyReportAttributesDeploy --account deployer --verify --broadcast --rpc-url alfajores

forge script script/deploy/RecyReportSvgDeploy.s.sol:RecyReportSvgDeploy --account deployer --verify --broadcast --rpc-url alfajores

forge script script/deploy/RecyReportDataDeploy.s.sol:RecyReportDataDeploy --account deployer --verify --broadcast --rpc-url alfajores


forge script script/deploy/RecyReportDeploy.s.sol:RecyReportDeploy --account deployer --verify --broadcast --rpc-url alfajores

forge script script/deploy/RecyReportFactoryDeploy.s.sol:RecyReportFactoryDeploy --account deployer --verify --broadcast --rpc-url alfajores

proxy=default forge script script/deploy/RecyReportProxyDeploy.s.sol:RecyReportProxyDeploy --account deployer --verify --broadcast --rpc-url alfajores
```

##### Role management

###### Apply all roles from config to the default proxy

```sh
forge script script/ManageRoles.s.sol:ManageRoles --sig "applyAllRolesFromConfig()" --rpc-url alfajores --account deployer --broadcast
```

###### Grant auditor role

```sh
 forge script script/ManageRoles.s.sol:ManageRoles \
   --sig "grantAuditor(address,address)" <PROXY_ADDRESS> <AUDITOR_ADDRESS> \
   --rpc-url alfajores --account deployer --broadcast
```

###### Revoke auditor role

```sh
 forge script script/ManageRoles.s.sol:ManageRoles \
   --sig "revokeAuditor(address,address)" <PROXY_ADDRESS> <AUDITOR_ADDRESS> \
   --rpc-url alfajores --account deployer --broadcast
```

###### Check if address has auditor role

```sh
 forge script script/ManageRoles.s.sol:ManageRoles \
   --sig "checkAuditor(address,address)" <PROXY_ADDRESS> <AUDITOR_ADDRESS> \
   --rpc-url alfajores
```

###### Grant recycler role

```sh
forge script script/ManageRoles.s.sol:ManageRoles \
  --sig "grantRecycler(address,address)" <PROXY_ADDRESS> <RECYCLER_ADDRESS> \
  --rpc-url alfajores --account deployer --broadcast
```

###### Revoke recycler role

```sh
 forge script script/ManageRoles.s.sol:ManageRoles \
   --sig "revokeRecycler(address,address)" <PROXY_ADDRESS> <RECYCLER_ADDRESS> \
   --rpc-url alfajores --account deployer --broadcast
```

###### Check if address has recycler role

```sh
 forge script script/ManageRoles.s.sol:ManageRoles \
   --sig "checkRecycler(address,address)" <PROXY_ADDRESS> <RECYCLER_ADDRESS> \
   --rpc-url alfajores
```

##### List all deployed proxies

```sh
 forge script script/ManageRoles.s.sol:ManageRoles \
   --sig "listProxies()" \
   --rpc-url alfajores
```

##### Populate

```sh
forge script script/PopulateRecyReport.s.sol:PopulateRecyReportScript --account deployer --broadcast --rpc-url alfajores
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
forge script script/deploy/RecyReportProxyUpgrade.s.sol:RecyReportProxyUpgrade --sig 'upgradeProxy(address,address)' --rpc-url alfajores --account deployer --broadcast <proxy> <implementation>
```

#### List All Proxies

```sh
forge script script/deploy/RecyReportProxyUpgrade.s.sol:RecyReportProxyUpgrade --sig 'listAllProxiesWithImplementations()' --rpc-url alfajores --account deployer --broadcast
```
