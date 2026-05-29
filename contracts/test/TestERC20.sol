// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice A real, standard ERC-20 used as the test stablecoin. This is not a
///         behavioral mock: it is OpenZeppelin's audited ERC20 with an open
///         mint for test setup, the same kind of token the README documents
///         deploying to Moca testnet when no canonical USDC exists there.
contract TestERC20 is ERC20 {
    uint8 private immutable _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
