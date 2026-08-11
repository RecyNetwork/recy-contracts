# Recy Protocol — Security Remediation Runbook

**Operator-facing companion to** [`security-audit-remediation.md`](./security-audit-remediation.md). That document says *what* is wrong and *why*; this one says *what to type, in what order*. Section references below (§3.1, §5a, …) point back to it.

**Target deployment:** Sepolia, chain `11155111`.
**Live state verified:** 2026-08-11, read-only `eth_call` / `eth_getStorageAt` against `https://ethereum-sepolia.publicnode.com`.

---

## ⛔ THE ORDERING CONSTRAINT — READ THIS BEFORE ANYTHING ELSE

> ### Phase 1 (`RecyReportData` + `setDataContract`) MUST complete before Phase 2 (implementation upgrade).
>
> The Phase 2 `RecyReport` implementation validates material ids on every write by calling
> **`data.materialsCount()`** (`src/RecyReport.sol:280`). That function **does not exist** on the
> currently deployed `RecyReportData` at `0x7CF63765aaFA47BadA0374c23b10EB91F00d46f4` —
> verified live, the call reverts:
>
> ```
> $ cast call 0x7CF63765aaFA47BadA0374c23b10EB91F00d46f4 "materialsCount()(uint256)" --rpc-url $RPC
> Error: execution reverted, data: "0x"
> ```
>
> **Upgrading the implementation first bricks both write paths.** `mintRecyReportResult` and
> `setRecyReportResult` would revert for every caller, for every report, until `setDataContract`
> lands. Reports could not be created or completed at all.
>
> ```mermaid
> graph LR
>   P0[Phase 0<br/>revoke role overlap<br/>no deployment] --> P1[Phase 1<br/>deploy RecyReportData<br/>+ setDataContract]
>   P1 --> P2[Phase 2<br/>deploy + upgrade<br/>RecyReport impl]
>   P2 --> P2b[setUnlockDelay 86400]
>   P1 -.->|SKIP THIS EDGE<br/>and every write path reverts| P2
> ```

`script/deploy/RecyReportImplementationUpgrade.s.sol` enforces this: it reads the proxy's installed
data contract out of storage slot 0 and aborts if it cannot answer `materialsCount()`. Run the
script as a dry run at any time to check where you stand — it sends nothing.

---

## Live state snapshot

| Item | Value |
|---|---|
| Proxy (`default`) | `0x91e3E6F9672E985100b8F0798d2cB55fa53c66Da` |
| Proxy implementation (EIP-1967 slot) | `0xc2b9a91fD9789ebe93C22b5a4981c2d643C9e6B1` |
| Proxy data contract (storage slot 0, `data` is private) | `0x7CF63765aaFA47BadA0374c23b10EB91F00d46f4` |
| Factory | `0x957C90a7E568349005772072Cb75C3dfd3460B51` |
| Factory `owner()` | `0x3402ce3b5f88c852c0d6992C69A03095d1345BBd` |
| Factory `implementation()` (immutable) | `0x3a36aDA04BDAE0D574b3E96f14f870Bf58EB162a` ⚠ **not** the proxy's |
| Factory `dataContract()` (immutable) | `0x1C00BBB839Cb45Aa2b273Cc53B248D7B80d04a1b` ⚠ **not** the proxy's |
| Attributes | `0x8a4B4c0919ab22EdF285326e012f623e850A9Ef0` (13 materials) |
| SVG | `0x5529c9CD2869c6abc51523d411Bc0D8500b71227` |
| cRECY token | `0xCAAb4DbD52901bac2CF5a02Fa2041F512C839072` |
| `unlockDelay` | **60** seconds |
| Shares (recycler/validator/generator/protocol) | 60 / 10 / 20 / 10 |
| `nftNextId` | 66 |
| `tokenURI(1)` | **fails `jq -e .`** — malformed JSON (§3.4) |

### Role holders (verified with `hasRole`)

| Principal | RECYCLER | AUDITOR | EMERGENCY | DEFAULT_ADMIN |
|---|:--:|:--:|:--:|:--:|
| `0x3402ce3b…5BBd` (factory owner, `addresses.protocol`) | ✅ | ✅ | ✅ | ✅ |
| `0xBdF566d0…c4FC` | ✅ | ❌ | ❌ | ❌ |
| `0xcC57F5c5…9530` | ✅ | ❌ | ❌ | ❌ |
| `0x607AAD17…140A` | ✅ | ❌ | ❌ | ❌ |
| `0x5f3CD352…0b64` | ✅ | ✅ | ❌ | ❌ |
| `0x20BAe19A…8FD9` | ❌ | ✅ | ❌ | ❌ |
| `0x37EE01FF…C1e8` | ❌ | ✅ | ❌ | ❌ |
| `0xF62DaAe4…6C89` | ✅ | ✅ | ✅ | ✅ |
| `0x957C90a7…0B51` (the factory) | ✅ | ✅ | ✅ | ✅ |

**Four principals hold `RECYCLER` + `AUDITOR`.** That pair on one key is the complete-treasury-drain
path of §3.1: mint your own report, validate your own report, collect recycler + validator +
generator = **90%** of the payout. `0x5f3CD352…` holds the pair with *no* admin role, so the drain
needs no privileged key at all.

Note that `config/contracts.json` previously **understated** this — it listed `0xF62DaAe4…` under
`admins`/`emergency` only. The config has been corrected.

---

## Ground rules for every step below

- `export RPC=<your sepolia rpc>` before running anything here.
- Every `forge script` in this repo is a **dry run** unless you add `--broadcast`. The two new
  remediation scripts additionally require `CONFIRM_DEPLOY=true` before they will even enter
  `vm.startBroadcast()`, so `--broadcast` alone cannot fire them.
- **Never call `factory.revokeAdminRole(proxy, factory)` and never call `factory.renounceOwnership()`.**
  Both are single, unguarded, **irreversible** transactions that permanently sever factory control of
  the proxy (§3.7). No step in this runbook needs either.
- Revoking the factory's own `RECYCLER`/`AUDITOR` grants is safe: the factory uses only its
  `DEFAULT_ADMIN_ROLE` (grant/revoke/`upgradeToAndCall`, `src/RecyReportFactory.sol:241-434`) and
  exposes **no** passthrough to `mintRecyReport`, `setRecyReportResult` or `validateRecyReport`.

---

## Phase 0 — Role separation (no deployment, do immediately)

Removes the Critical without shipping a line of Solidity.

### The split, and why

`config/contracts.json` now encodes this. No address appears in both lists.

| Principal | Before | After | Reason |
|---|---|---|---|
| `0x3402ce3b…5BBd` | RECYCLER + AUDITOR + ADMIN + EMERGENCY | ADMIN + EMERGENCY | **Admin keys are not operators.** A key that can grant roles, upgrade the implementation and pause claiming must not also produce or authorise a payout. This address is additionally `addresses.protocol`, so it already receives the 10% protocol leg — leaving it the recycler and validator legs concentrates **100%** of a payout on one key. |
| `0xF62DaAe4…6C89` | RECYCLER + AUDITOR + ADMIN + EMERGENCY | ADMIN + EMERGENCY | Same rule. Its operational grants were never even recorded in config. |
| `0x957C90a7…0B51` (factory) | RECYCLER + AUDITOR + ADMIN + EMERGENCY | ADMIN + EMERGENCY | Least privilege. The grants come from `initialize` (`src/RecyReport.sol:138-141`) and are inert — the factory has no code path that uses them. |
| `0x5f3CD352…0b64` | RECYCLER + AUDITOR | **RECYCLER** | The one non-admin key holding the pair, i.e. the least supervised. It keeps the *production* capability and loses the *authorisation* capability: `validateRecyReport` is what creates the reward obligation and inflates `rewardTotal`, which in turn drives `RecyDistribution` minting (§3.1, §3.5). Give the unsupervised key the side that cannot mint money. |
| `0xBdF566d0…`, `0xcC57F5c5…`, `0x607AAD17…` | RECYCLER | RECYCLER | unchanged |
| `0x20BAe19A…`, `0x37EE01FF…` | AUDITOR | AUDITOR | unchanged |

Result: **4 recyclers, 2 auditors, 0 overlap, 0 admin key with an operational role.**
Two independent auditors remain, so validation is not a single point of failure, and neither of them
is a recycler — which means the §3.1 self-deal is structurally impossible *before* the Phase 2
dual-control code even ships.

### ⚠ Two blocking pre-checks

1. **Does any automation sign with `0x3402ce3b…` or `0xF62DaAe4…`?** Both lose `RECYCLER` and
   `AUDITOR` here. If `recy-api` (or any bot) uses either key to call `mintRecyReport`,
   `mintRecyReportResult`, `setRecyReportResult`, `validateRecyReport` or `invalidateRecyReport`,
   **those calls start reverting with `AccessControlUnauthorizedAccount`.** Re-point the automation
   at a dedicated operational key first, and grant that key exactly one side of the split.
2. **Does the organisation still control `0x20BAe19A…8FD9` and `0x37EE01FF…C1e8`?** After this phase
   they are the only two keys that can validate or invalidate a report. If either is lost, grant a
   replacement auditor **before** revoking, using a key that is not a recycler.

### Execute

Scripted, config-driven (recommended). Only ever revokes, only ever `RECYCLER`/`AUDITOR`, never
touches `DEFAULT_ADMIN_ROLE` or `EMERGENCY_ROLE`:

```bash
# dry run first — prints exactly what it would revoke, sends nothing
forge script script/ManageRoles.s.sol:ManageRoles \
  --sig 'revokeUnauthorizedOperationalRoles()' \
  --rpc-url $RPC --sender 0x3402ce3b5f88c852c0d6992C69A03095d1345BBd

# then, from the factory owner key
forge script script/ManageRoles.s.sol:ManageRoles \
  --sig 'revokeUnauthorizedOperationalRoles()' \
  --rpc-url $RPC --account <factory-owner> --broadcast
```

The seven transactions it issues, in order (also the manual equivalent — all sent to the **factory**
from its `owner()`; `$P` is the proxy):

```bash
export F=0x957C90a7E568349005772072Cb75C3dfd3460B51
export P=0x91e3E6F9672E985100b8F0798d2cB55fa53c66Da

cast send $F "revokeAuditorRole(address,address)"  $P 0x5f3CD35206c0526b837766d48D022522a9910b64
cast send $F "revokeRecyclerRole(address,address)" $P 0x3402ce3b5f88c852c0d6992C69A03095d1345BBd
cast send $F "revokeAuditorRole(address,address)"  $P 0x3402ce3b5f88c852c0d6992C69A03095d1345BBd
cast send $F "revokeRecyclerRole(address,address)" $P 0xF62DaAe4c3f9Fadf689F767716a82dFEe5026C89
cast send $F "revokeAuditorRole(address,address)"  $P 0xF62DaAe4c3f9Fadf689F767716a82dFEe5026C89
cast send $F "revokeRecyclerRole(address,address)" $P 0x957C90a7E568349005772072Cb75C3dfd3460B51
cast send $F "revokeAuditorRole(address,address)"  $P 0x957C90a7E568349005772072Cb75C3dfd3460B51
```

### Verify

```bash
forge script script/ManageRoles.s.sol:ManageRoles \
  --sig 'checkSeparationOnChain()' --rpc-url $RPC
```

Reverts while any audited principal still holds both roles, and prints which. It audits every
address named anywhere in the proxy's config plus the factory. It must print
`PASS: no audited address holds both RECYCLER_ROLE and AUDITOR_ROLE.`

`script/ManageRoles.s.sol` also refuses to run at all if `config/contracts.json` ever re-introduces
the overlap, and `grantAuditor` / `grantRecycler` abort if the target already holds the opposite
role on chain. The dangerous pairing cannot be re-applied silently by a future ops run.

### Also in Phase 0

- **`unlockDelay` stays 60 seconds until Phase 2.** There is no setter at the currently deployed
  implementation. `config/contracts.json` has been raised to `86400`, which governs **new** proxies
  only. Retuning the live proxy is a Phase 2 follow-up step.
- Begin the factory-ownership transfer to a multisig (§3.7). Out of scope for this runbook, but it
  is the other half of the Phase 0 risk reduction: `owner()` can upgrade the proxy to arbitrary
  logic with no timelock.

---

## Phase 1 — `RecyReportData` redeploy + `setDataContract`

**A single deployment.** The new `RecyReportData` is constructed against the **existing, already
deployed** `RecyReportAttributes` (`0x8a4B4c09…9Ef0`) and `RecyReportSvg` (`0x5529c9CD…1227`).

> **Do not redeploy `RecyReportAttributes`.** An earlier draft of this work required it, because the
> material-bounds check was going to depend on a `getMaterialsCount()` function that does not exist
> on the live attributes contract (verified: it reverts). That dependency was removed —
> `RecyReportData.materialsCount()` now derives the count from `getMaterials()`, which the live
> contract does implement — so the live attributes contract is reused as-is. Redeploying it would
> have forced a data migration that destroyed two real SVG entries.

Fixes shipped by this phase, none of which need a proxy upgrade:

1. Malformed `tokenURI` JSON (§3.4).
2. `getStatus` default branch for unknown statuses (§3.8).
3. Read-time tolerance for out-of-range material ids (§3.3 part 2) — the **only** way to un-brick a
   token that has already been poisoned.
4. Constructor zero-checks plus a non-empty-catalogue check.

### Execute

```bash
# dry run: prints the pre-flight checklist, builds the contract, and proves the fixes
forge script script/deploy/RecyReportDataRedeploy.s.sol:RecyReportDataRedeploy --rpc-url $RPC

# deploy
CONFIRM_DEPLOY=true forge script script/deploy/RecyReportDataRedeploy.s.sol:RecyReportDataRedeploy \
  --rpc-url $RPC --account <deployer> --broadcast
```

The script refuses to run if `reportAttributes` or `reportSvg` is missing from config or has no code
on the target chain, and it verifies against the freshly built contract that `tokenJson` /
`tokenUriAttributes` survive an out-of-range material id before printing the handover.

Then:

1. Update `config/contracts.json` → `11155111.contracts.reportData` to the new address.
2. Activate it on the live proxy, from a `DEFAULT_ADMIN_ROLE` key:
   ```bash
   cast send $P "setDataContract(address)" <new RecyReportData>
   ```
3. Verify. **`data` is a private variable** (`src/RecyReport.sol:29`), so there is no getter — read
   storage slot 0:
   ```bash
   cast storage $P 0 --rpc-url $RPC     # low 20 bytes must equal <new RecyReportData>
   ```
4. Confirm the metadata fix (see [Verification commands](#verification-commands) below):
   ```bash
   cast call $P "tokenURI(uint256)(string)" 1 --rpc-url $RPC \
     | sed 's#^"data:application/json;base64,##; s#"$##' | base64 -d | jq -e . >/dev/null \
     && echo "VALID JSON" || echo "STILL BROKEN"
   ```
   This prints `STILL BROKEN` today and must print `VALID JSON` after `setDataContract`.

### Source / bytecode drift — informational, no action

The deployed `RecyReportAttributes` differs from repo `HEAD` **in data**, not in logic:

- live `material[12]` = `"Solid Inert Industrial Waste"`; `HEAD` said `"Inert Industrial Waste"`
- live `materialSvg` has **13** entries; `HEAD` had only 11
- live `materialSvg[11]` and `[12]` are real SVG paths (~1150 and ~1204 bytes); `HEAD` had placeholders

The repo source has been corrected to match the authoritative on-chain values. **This affects only
future attributes deployments. The live contract is untouched and needs no action.**

---

## Phase 2 — `RecyReport` implementation upgrade (UUPS)

**Prerequisite: Phase 1 is live on the proxy.** See the warning at the top. The deploy script
enforces it.

Bundled into this one upgrade: dual control in `validateRecyReport`, validation-time solvency check,
`_wasteAmount` cap, status guard + `_ownerOf` existence check on `setRecyReportResult`, write-time
material-id validation, self-service `setFundsWallet`, `SafeERC20`, `setUnlockDelay`,
`setProtocolAddress`.

### 1. Run the OZ upgrade-safety validator first

```bash
forge clean && forge build --build-info
npx @openzeppelin/upgrades-core validate out/build-info \
  --contract src/RecyReport.sol:RecyReport \
  --requireReference --reference <previous build-info>:RecyReport
```

Storage-layout facts the validator is checking, restated so a human can sanity-check the diff:

- **`RecyReport` reserves no `__gap`.** New state variables may only be **appended** after
  `mapping(address => address) public funds;` (`src/RecyReport.sol:63`).
- **`uint256 public rewardMinted` (`:55`) must keep its slot.** Deleting it shifts `rewardClaimed`
  and every mapping below it and corrupts the live proxy. It is retained and documented as reserved.
- `_storedTrustedForwarder` sits mid-layout; do not disturb it.
- **`initialize` must keep its 10 parameters and its selector.** The factory is immutable and
  hardcodes `RecyReport.initialize.selector` (`src/RecyReportFactory.sol:107`); changing it
  permanently breaks `deployProxy` for all future proxies.

### 2. Deploy the implementation

```bash
# dry run — also performs the Phase-1-before-Phase-2 ordering check; safe to run any time
forge script script/deploy/RecyReportImplementationUpgrade.s.sol:RecyReportImplementationUpgrade \
  --rpc-url $RPC

CONFIRM_DEPLOY=true forge script \
  script/deploy/RecyReportImplementationUpgrade.s.sol:RecyReportImplementationUpgrade \
  --rpc-url $RPC --account <deployer> --broadcast
```

This script **only deploys**. It never upgrades — the upgrade is a separate, deliberate transaction.

### 3. Upgrade the proxy

From the factory owner key:

```bash
forge script script/deploy/RecyReportProxyUpgrade.s.sol:RecyReportProxyUpgrade \
  --sig 'upgradeProxy(address,address)' $P <new implementation> \
  --rpc-url $RPC --account <factory-owner> --broadcast
```

Or directly, from a `DEFAULT_ADMIN_ROLE` key on the proxy:

```bash
cast send $P "upgradeToAndCall(address,bytes)" <new implementation> 0x
```

Then update `config/contracts.json` → `11155111.contracts.reportImplementation`.

### 4. Immediately after: retune `unlockDelay`

```bash
cast send $P "setUnlockDelay(uint64)" 86400          # DEFAULT_ADMIN_ROLE
```

**Why 86400 (24 h), up from 60 s.** The only in-protocol brake on a fraudulent payout is
`pauseRewardClaiming()` (`EMERGENCY_ROLE`, `src/RecyReport.sol:163`), which blocks
`claimRecyReportReward` via `whenNotPaused` (`:410`). The delay's entire job is to give a human
holding `EMERGENCY_ROLE` time to see a `ReportValidated` event and pause before the claim window
opens. 60 seconds is shorter than an alerting round-trip, i.e. effectively no delay at all. 24 hours
covers an overnight gap with a single on-call rotation and costs an honest claimant one day after a
step (validation) that is already manual. Choose **172800** (48 h) instead if there is no weekend
on-call.

`unlockDelay` is read at validation time (`:420`), so the change applies to reports validated after
it lands; already-validated reports keep their existing unlock date.

---

## Fund wallets — the self-service migration

`setFundsWallet` changes shape at the Phase 2 upgrade:

| | Before | After |
|---|---|---|
| Signature | `setFundsWallet(address _signatory, address _fundAddress)` | `setFundsWallet(address _fundAddress)` |
| Access | `onlyRole(DEFAULT_ADMIN_ROLE)` | anyone, for themselves only |
| Effect | `funds[_signatory] = _fundAddress` | `funds[_msgSender()] = _fundAddress` |

That admin passthrough **was** the §3.6 vulnerability: `funds[]` is resolved at *claim* time while
the reward is snapshotted at *validation* time, so an admin could redirect 90% of an already-earned
payout moments before the owner claimed it. Removing it is the point of the change.

**Consequences, in order of how likely they are to bite you:**

1. **No key can set a fund wallet on behalf of another account any more.** Each participant must
   send `setFundsWallet(address)` from its own key:
   ```bash
   cast send $P "setFundsWallet(address)" <my payout wallet>   # sent by the participant itself
   ```
2. **`RecyReportFactory.setRecyclerFund` and `setAuditorFund` are dead after the upgrade.** The
   factory is **not** upgradeable, so both functions remain in the deployed bytecode at
   `0x957C90a7…0B51` and will keep showing up on block explorers — but they call the deleted
   two-argument `setFundsWallet(address,address)`, whose selector no longer exists, so **they
   revert.** Do not try to use them. Factory v2 drops them entirely.
3. **`script/ManageRoles.s.sol` no longer sets fund wallets.** `applyAllRolesFromConfig()` grants
   roles only. `recyclerFunds` / `auditorFunds` in `config/contracts.json` are now **advisory
   records** of the intended mapping, not something any script can apply.
4. Use the read-only drift report to see who still owes a transaction. It prints the exact command
   for each, and can never fix anything itself:
   ```bash
   forge script script/ManageRoles.s.sol:ManageRoles --sig 'reportFundWalletDrift()' --rpc-url $RPC
   ```

**Good news — today this migration is a no-op.** Verified live: every principal remaining in the
config already has `funds[x] == x`, and an unset `funds[x]` pays to `x` anyway
(`funds[recycler] == address(0) ? recycler : funds[recycler]`, `src/RecyReport.sol:492-507`). Nobody
has to do anything unless they want their payout to go somewhere other than their own address.
`0xF62DaAe4…6C89` is the one address with `funds` unset, and it is being removed from all
operational roles.

**Sequencing:** the old two-argument form still works *until* the upgrade lands. If any fund wallet
must be set on behalf of someone else, that is the last window to do it.

---

## Verification commands

All read-only. None of these send a transaction.

```bash
export RPC=<your sepolia rpc>
export P=0x91e3E6F9672E985100b8F0798d2cB55fa53c66Da
export F=0x957C90a7E568349005772072Cb75C3dfd3460B51
```

### 1. `tokenURI(1)` decodes to valid JSON  *(after Phase 1)*

```bash
cast call $P "tokenURI(uint256)(string)" 1 --rpc-url $RPC \
  | sed 's#^"data:application/json;base64,##; s#"$##' | base64 -d | tee /tmp/t1.json | jq -e . >/dev/null \
  && echo "VALID JSON" || echo "INVALID JSON"

jq -c '.attributes[0]' /tmp/t1.json
```

Expected after Phase 1: `VALID JSON`, and the first attribute is
`{"trait_type":"Status","value":"Rewarded"}` — a single, properly closed trait object.

Today it prints `INVALID JSON`, because the Status trait is emitted twice, nested, with unescaped
quotes:

```
"attributes": [{"trait_type":"Status","value":"{"trait_type":"Status","value":"Rewarded"}"},…
```

Also confirm a token carrying an out-of-range material id renders instead of reverting — the
material trait reads `"Unknown Material"`.

### 2. Data contract is the new one  *(after Phase 1)*

```bash
cast storage $P 0 --rpc-url $RPC          # `data` is private; slot 0 holds it
```

### 3. Status guard reverts  *(after Phase 2)*

`setRecyReportResult` now requires the token to exist **and** to be in `RECYCLE_CREATED`.
Token 1 is `REWARDED` (status 4), so re-populating it must fail:

```bash
cast call $P \
  "setRecyReportResult(uint256,uint64,uint128,uint32[],uint128[],uint32[],uint32[],uint32)" \
  1 1773878400 1000000 "[0]" "[1000000]" "[0]" "[0]" 0 \
  --from 0xBdF566d020e206456534e873f5EF385A762aC4FC --rpc-url $RPC
```

Expected: revert `0x973bae08` — `RecyReportInvalidStatus()`.
Today this call **succeeds**, which is the bug (§3.2).

Existence check, on an id that was never minted (`nftNextId` is 66):

```bash
cast call $P \
  "setRecyReportResult(uint256,uint64,uint128,uint32[],uint128[],uint32[],uint32[],uint32)" \
  9999 1773878400 1000000 "[0]" "[1000000]" "[0]" "[0]" 0 \
  --from 0xBdF566d020e206456534e873f5EF385A762aC4FC --rpc-url $RPC
```

Expected: revert `0xc9fa7232` — `NftNotExists()`.

### 4. Dual control reverts  *(after Phase 2)*

After Phase 0 no key holds both roles, so this cannot be exercised against unmodified live state —
which is itself the point. Prove the guard with `cast`'s state overrides: put a token into
`COMPLETED` and set its recycler to the auditor doing the call.

```bash
AUD=0x20BAe19A7B6Faf0bFc0fd7F29548FB803F1E8FD9
TOKEN=1

# status[TOKEN]  -> mapping at slot 11
STATUS_SLOT=$(cast keccak $(cast concat-hex $(cast to-uint256 $TOKEN) $(cast to-uint256 11)))
# info[TOKEN]    -> mapping at slot 8; base+1 packs { recycler (bytes 0-19) | recycleDate (20-27) }
INFO_BASE=$(cast keccak $(cast concat-hex $(cast to-uint256 $TOKEN) $(cast to-uint256 8)))
INFO_1=$(cast to-uint256 $(python3 -c "print(int('$INFO_BASE',16)+1)"))
CUR=$(cast storage $P $INFO_1 --rpc-url $RPC)
NEW="${CUR:0:26}${AUD:2}"                    # keep recycleDate, swap the address in

cast call $P "validateRecyReport(uint256)" $TOKEN --from $AUD --rpc-url $RPC \
  --override-state-diff "$P:$STATUS_SLOT:$(cast to-uint256 2)" \
  --override-state-diff "$P:$INFO_1:$NEW"
```

Expected: revert `0x3fdc78d6` — `ValidatorCannotBeRecycler()`.
**Control:** drop the second override, leaving the token's real recycler in place, and re-run. The
call must get *past* the dual-control check — you will see a different error from further down
`validateRecyReport` (`0xf16eeebd` `InsufficientRewardBalance()` if the pool cannot cover the
reward, or success), never `0x3fdc78d6`. That is what proves the override is doing what you think.

### 5. Waste-amount cap and material-id range reject  *(after Phase 2)*

```bash
REC=0xBdF566d020e206456534e873f5EF385A762aC4FC

# 1e15 mg = 1000 t is the cap; one more must be rejected
cast call $P \
  "mintRecyReportResult(address,uint64,uint128,uint32[],uint128[],uint32[],uint32[],uint32)" \
  $REC 1773878400 1000000000000001 "[0]" "[1000]" "[0]" "[0]" 0 --from $REC --rpc-url $RPC
# expect 0xe21e2bba  WasteAmountExceedsCap()

# 13 materials in the catalogue, so id 13 and above must be rejected
cast call $P \
  "mintRecyReportResult(address,uint64,uint128,uint32[],uint128[],uint32[],uint32[],uint32)" \
  $REC 1773878400 1000 "[9999]" "[1000]" "[0]" "[0]" 0 --from $REC --rpc-url $RPC
# expect 0x31889f1c  MaterialIdOutOfRange()
```

### 6. Role separation holds

```bash
forge script script/ManageRoles.s.sol:ManageRoles --sig 'checkSeparationOnChain()' --rpc-url $RPC
```

### 7. Settings

```bash
cast call $P "unlockDelay()(uint64)" --rpc-url $RPC          # 86400 after Phase 2 step 4
cast storage $P 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc --rpc-url $RPC
```

---

## Deploying a new proxy — the §5a guardrail

**Do not deploy new plants through the existing factory until Phase 3 ships.**

`implementation` and `dataContract` are `immutable` on the factory (`src/RecyReportFactory.sol:15,18`)
and are baked into every proxy it creates — the data contract through the initializer payload
(`:107`), the implementation into the `ERC1967Proxy` itself (`:117`). Neither `setDataContract` nor a
UUPS upgrade of the live proxy touches them. **Any proxy deployed through this factory is born with
the old buggy data contract and the old vulnerable implementation, with every Phase 1/2 fix silently
absent.** `deployProxy` is permissionless (`:96`), so this needs no privileged mistake.

This is not hypothetical. The factory's immutables already diverge from the blessed pair **today**:

| | Factory immutable | Blessed (config / live proxy) |
|---|---|---|
| implementation | `0x3a36aDA04BDAE0D574b3E96f14f870Bf58EB162a` | `0xc2b9a91fD9789ebe93C22b5a4981c2d643C9e6B1` |
| dataContract | `0x1C00BBB839Cb45Aa2b273Cc53B248D7B80d04a1b` | `0x7CF63765aaFA47BadA0374c23b10EB91F00d46f4` |

`script/deploy/RecyReportProxyDeploy.s.sol` now turns that silent regression into a failed script:

- It asserts `factory.implementation()` and `factory.dataContract()` equal
  `contracts.reportImplementation` / `contracts.reportData` in config, and **aborts** otherwise.
  Because Phase 1 and Phase 2 update those config entries, this assertion gets *stricter* as the
  remediation proceeds: after Phase 1 the factory's stale `dataContract()` is compared against the
  **new** `RecyReportData`, so a post-Phase-1 deployment through the old factory fails loudly rather
  than quietly inheriting the old metadata contract.
- Its "reuse an existing proxy of this name" branch now **fails loudly**. Proxy names are
  first-come-first-served on a permissionless factory, so a pre-existing proxy under a given name is
  not necessarily yours — whoever registered it chose its token, protocol address and shares (§3.8).

Both behaviours can be overridden, deliberately and visibly:

| Flag | Meaning |
|---|---|
| `ALLOW_STALE_FACTORY=true` | Proceed despite the blessed-code mismatch. The script prints the two remediation calls and marks them **mandatory**. |
| `ALLOW_PROXY_REUSE=true` | Adopt the pre-existing proxy registered under this name. Verify its provenance first. |

If a new plant is genuinely unavoidable before Phase 3, then **immediately** after `deployProxy`,
as a required step and not a note:

```bash
# 1. Deploying a proxy grants YOU nothing. `initialize` gives all four roles to `_msgSender()`,
#    which during deployProxy is the FACTORY (src/RecyReport.sol:157-160), and the factory has no
#    setDataContract passthrough. Without this line, step 2 reverts
#    AccessControlUnauthorizedAccount(<you>, 0x00..00). Send from the factory owner.
cast send $F "grantAdminRole(address,address)" <new proxy> <operator>

# 2. Now callable by <operator>
cast send <new proxy> "setDataContract(address)" <blessed reportData>

# 3. Factory owner; needs no extra grant, the factory already holds DEFAULT_ADMIN on the new proxy
cast send $F "upgradeProxy(address,address)" <new proxy> <blessed reportImplementation>
```

…then re-run every check in [Verification commands](#verification-commands) against the new proxy.

> The same trap applies to **any** admin-gated call on a freshly deployed proxy —
> `setUnlockDelay`, `setProtocolAddress`, `setTrustedForwarder`, `grantRole`. Grant yourself
> `DEFAULT_ADMIN_ROLE` through the factory first. It does **not** apply to the live proxy
> `0x91e3…66Da`, where `0x3402ce3b…` and `0xF62DaAe4…` already hold `DEFAULT_ADMIN_ROLE`.

---

## Out of scope for this runbook

- **`RecyDistribution` is not deployed** and has no deploy script. Its mint path trusts `rewardTotal`
  (§3.1, §3.5), so it must not ship until those invariants hold. Nothing here deploys it.
- **Factory v2 (`RecyReportFactoryV2`) needs a separate migration**, and it is load-bearing, not
  cleanup — see §5a. Two hard requirements:
  1. It **must** ship `registerExistingProxy(address,string)`. Every one of the factory's privileged
     paths gates on `_isDeployedProxy`, and there is no registration entry point, so **a replacement
     factory can never adopt `0x91e3…66Da`** without it.
  2. It should read `implementation` / `dataContract` from owner-settable storage (with events)
     rather than `immutable`, so future fixes propagate without yet another factory migration.
  Until it exists, "the vulnerability is fixed" is true only of proxy `0x91e3…66Da`.
- **`recy-api` changes** are sequenced in §5b: `POST /set-result` starts returning
  409 `REPORT_INVALID_STATUS` for non-`CREATED` tokens at the Phase 2 upgrade, and status `2` may be
  added to `FENCEABLE_STATUSES` only *after* the upgrade is live, version-scoped per proxy.

---

## Appendix — error selectors

The Phase 2 guards deliberately reuse errors the backend already maps to typed HTTP responses
(§5b.2). A new error would fall through to a generic 409.

| Error | Selector | `recy-api` mapping |
|---|---|---|
| `RecyReportInvalidStatus()` | `0x973bae08` | `REPORT_INVALID_STATUS` → 409 |
| `NftNotExists()` | `0xc9fa7232` | `NFT_NOT_EXISTS` → 400 |
| `InsufficientRewardBalance()` | `0xf16eeebd` | → 409 |
| `ValidatorCannotBeRecycler()` | `0x3fdc78d6` | new |
| `WasteAmountExceedsCap()` | `0xe21e2bba` | new |
| `MaterialIdOutOfRange()` | `0x31889f1c` | new |
| `EmptyMaterialsArray()` | `0x078c300a` | new |
| `RecyReportNotCompleted()` | `0x2f6acf2b` | existing |

---

## Appendix — how the commands in this document were checked

Nothing here was written from memory. Recorded so the next operator knows what is proven and what
is not.

- **Live reads** (role table, `unlockDelay`, shares, `nftNextId`, factory `owner`/`implementation`/
  `dataContract`, proxy storage slots 0 and EIP-1967, `funds[x]` for every principal,
  `materialsCount()` reverting on the deployed data contract, `tokenURI(1)` failing `jq -e .`) were
  taken with read-only `cast call` / `cast storage` against Sepolia on 2026-08-11.
- **The scripts** were exercised against a **local `anvil` replica of live state** — the live
  bytecode of the factory, proxy, implementation, data, attributes, SVG and token copied in with
  `anvil_setCode`, plus the relevant storage slots (roles, `funds`, `info`, `status`, `_owners`,
  the material catalogue, factory registry) copied with `anvil_setStorageAt`. On that replica:
  `checkSeparationOnChain()` reported exactly the four overlap principals and reverted;
  `revokeUnauthorizedOperationalRoles()` simulated exactly the seven revocations listed in Phase 0;
  the blessed-code guard and the Phase-1-before-Phase-2 ordering guard each aborted, and the
  ordering guard passed once a data contract answering `materialsCount()` was installed.
- **The verification commands in the previous section** were run against that same replica with the
  Phase 2 implementation installed, and returned the documented selectors: `0x973bae08`
  (status guard), `0xc9fa7232` (existence), `0x3fdc78d6` (dual control), `0xe21e2bba` (waste cap),
  `0x31889f1c` (material range). The Phase 1 data contract's `tokenUriAttributes` output decoded
  and passed `jq -e .`, with an out-of-range material id rendering as `"Unknown Material"`.
- **Also checked on the replica:** `setDataContract` reverts `0xe2517d3f`
  `AccessControlUnauthorizedAccount` for a caller without `DEFAULT_ADMIN_ROLE` and succeeds after
  `factory.grantAdminRole`, which is why the new-proxy remediation sequence has three steps and
  not two.
- **Not checked on the replica:** the `upgradeToAndCall` call itself. Injected runtime bytecode has
  unset immutables, so UUPS's `onlyProxy` context check (`__self`) fires first and returns
  `0xe07c8dba` `UUPSUnauthorizedCallContext()` for admin and non-admin alike. Its authorisation
  gate is `_authorizeUpgrade(...) onlyRole(DEFAULT_ADMIN_ROLE)` (`src/RecyReport.sol:167`), read
  from source. Prefer the factory route (`factory.upgradeProxy`, `onlyOwner`), which the factory
  performs while holding `DEFAULT_ADMIN_ROLE` on the proxy.
- **Not checked:** anything requiring a broadcast. No transaction was sent to any public network
  while preparing this document.
