// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../IThirdwebModule.sol";
import "../IThirdwebRestrictedTransfer.sol";

interface ITokenERC20 is IThirdwebModule, IThirdwebRestrictedTransfer {

    /**
     * @dev Creates `amount` new tokens for `to`.
     *
     * See {ERC20-_mint}.
     *
     * Requirements:
     *
     * - the caller must have the `MINTER_ROLE`.
     */
    function mint(address to, uint256 amount) external;
}