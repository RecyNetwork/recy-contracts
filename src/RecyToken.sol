// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RecyToken is OFT {
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        address _lzEndpoint,
        address _delegate
    ) OFT(_name, _symbol, _lzEndpoint, _delegate) Ownable(_delegate) {
        if (_initialSupply > 0) {
            _mint(_delegate, _initialSupply * 10 ** decimals());
        }
    }

    function mint(address to, uint256 amount) public onlyOwner {
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
