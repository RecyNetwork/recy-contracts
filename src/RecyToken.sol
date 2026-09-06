// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RecyToken is OFT {
    error InvalidIssuanceChainId();
    error IssuanceUnavailableOnThisChain(uint256 currentChainId, uint256 issuanceChainId);

    /// @notice Shared EVM chain ID of the only chain allowed to issue new tokens.
    uint256 public immutable issuanceChainId;
    /// @notice Cumulative original issuance in token wei; bridge credits and burns never change it.
    uint256 public totalIssued;

    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address lzEndpoint,
        address tokenOwner,
        uint256 issuanceChainId_
    ) OFT(name, symbol, lzEndpoint, tokenOwner) Ownable(tokenOwner) {
        if (issuanceChainId_ == 0) revert InvalidIssuanceChainId();
        if (initialSupply > 0 && block.chainid != issuanceChainId_) {
            revert IssuanceUnavailableOnThisChain(block.chainid, issuanceChainId_);
        }

        issuanceChainId = issuanceChainId_;

        if (initialSupply > 0) {
            uint256 initialSupplyWei = initialSupply * 10 ** decimals();
            totalIssued = initialSupplyWei;
            _mint(tokenOwner, initialSupplyWei);
        }
    }

    function mint(address to, uint256 amount) public onlyOwner {
        if (block.chainid != issuanceChainId) {
            revert IssuanceUnavailableOnThisChain(block.chainid, issuanceChainId);
        }

        totalIssued += amount;
        _mint(to, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) public {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }
}
