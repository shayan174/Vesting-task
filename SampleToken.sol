// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Shayantoken is ERC20 {
    constructor(uint256 initialSupply)  ERC20("shayan_token", "SHTN") {
        _mint(msg.sender, initialSupply);
    }
}
