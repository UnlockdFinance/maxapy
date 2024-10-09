// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { IERC20Metadata } from "openzeppelin/interfaces/IERC20Metadata.sol";
// import {Policy} from "../Policy.sol";
import { IEToken } from "./IEToken.sol";
// import {IRiskModule} from "./IRiskModule.sol";
// import {IAccessManager} from "./IAccessManager.sol";

interface IPolicyPool {
    /**
     * @dev Reference to the main currency (ERC20) used in the protocol
     * @return The address of the currency (e.g. USDC) token used in the protocol
     */
    function currency() external view returns (IERC20Metadata);

    /**
     * @dev Deposits liquidity into an eToken. Forwards the call to {EToken-deposit}, after transferring the funds.
     * The user will receive etokens for the same amount deposited.
     *
     * Requirements:
     * - `msg.sender` approved the spending of `currency()` for at least `amount`
     * - `eToken` is an active eToken installed in the pool.
     *
     * Events:
     * - {EToken-Transfer}: from 0x0 to `msg.sender`, reflects the eTokens minted.
     * - {ERC20-Transfer}: from `msg.sender` to address(eToken)
     *
     * @param eToken The address of the eToken to which the user wants to provide liquidity
     * @param amount The amount to deposit
     */
    function deposit(IEToken eToken, uint256 amount) external;

    /**
     * @dev Withdraws an amount from an eToken. Forwards the call to {EToken-withdraw}.
     * `amount` of eTokens will be burned and the user will receive the same amount in `currency()`.
     *
     * Requirements:
     * - `eToken` is an active (or deprecated) eToken installed in the pool.
     *
     * Events:
     * - {EToken-Transfer}: from `msg.sender` to `0x0`, reflects the eTokens burned.
     * - {ERC20-Transfer}: from address(eToken) to `msg.sender`
     *
     * @param eToken The address of the eToken from where the user wants to withdraw liquidity
     * @param amount The amount to withdraw. If equal to type(uint256).max, means full withdrawal.
     *               If the balance is not enough or can't be withdrawn (locked as SCR), it withdraws
     *               as much as it can, but doesn't fails.
     * @return Returns the actual amount withdrawn.
     */
    function withdraw(IEToken eToken, uint256 amount) external returns (uint256);
}
