// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IVaultStorage} from "./IVaultStorage.sol";

interface IVault is IVaultStorage {
    error AlreadyClaimed();
    error AlreadySet();
    error InsufficientClaim();
    error InsufficientDeposit();
    error InsufficientWithdrawal();
    error InvalidAdminFee();
    error InvalidEpoch();
    error InvalidEpochDuration();
    error NoDepositWhitelist();
    error NotWhitelistedDepositor();
    error NotStakingController();
    error TooMuchWithdraw();

    /**
     * @notice Initial parameters needed for a vault deployment.
     * @param collateral vault's underlying collateral
     * @param epochDuration duration of the vault epoch (it determines sync points for withdrawals)
     * @param adminFee admin fee (up to ADMIN_FEE_BASE inclusively)
     * @param depositWhitelist if enabling deposit whitelist
     * @param stakingControllerFactory factory for creating vault's staking controller
     * @param vetoDuration duration of the veto period for a slash request
     * @param executeDuration duration of the slash period for a slash request (after the veto duration has passed)
     */
    struct InitParams {
        address collateral;
        uint48 epochDuration;
        uint256 adminFee;
        bool depositWhitelist;
        address stakingControllerFactory;
        uint48 vetoDuration;
        uint48 executeDuration;
    }

    /**
     * @notice Emitted when a deposit is made.
     * @param depositor account that made the deposit
     * @param onBehalfOf account the deposit was made on behalf of
     * @param amount amount of the collateral deposited
     * @param shares amount of the active shares minted
     */
    event Deposit(address indexed depositor, address indexed onBehalfOf, uint256 amount, uint256 shares);

    /**
     * @notice Emitted when a withdrawal is made.
     * @param withdrawer account that made the withdrawal
     * @param claimer account that needs to claim the withdrawal
     * @param amount amount of the collateral withdrawn
     * @param burnedShares amount of the active shares burned
     * @param mintedShares amount of the epoch withdrawal shares minted
     */
    event Withdraw(
        address indexed withdrawer, address indexed claimer, uint256 amount, uint256 burnedShares, uint256 mintedShares
    );

    /**
     * @notice Emitted when a claim is made.
     * @param claimer account that claimed
     * @param recipient account that received the collateral
     * @param amount amount of the collateral claimed
     */
    event Claim(address indexed claimer, address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when an admin fee is set.
     * @param adminFee admin fee
     */
    event SetAdminFee(uint256 adminFee);

    /**
     * @notice Emitted when a deposit whitelist status is enabled/disabled.
     * @param depositWhitelist if enabled deposit whitelist
     */
    event SetDepositWhitelist(bool depositWhitelist);

    /**
     * @notice Emitted when a depositor whitelist status is set.
     * @param account account for which the whitelist status is set
     * @param status if whitelisted the account
     */
    event SetDepositorWhitelistStatus(address indexed account, bool status);

    /**
     * @notice Get a total amount of the collateral that can be slashed
     *         in `duration` seconds (if there will be no new deposits and slash executions).
     * @param duration duration to get the total amount of the slashable collateral in
     * @return total amount of the slashable collateral in `duration` seconds
     */
    function totalSupplyIn(uint48 duration) external view returns (uint256);

    /**
     * @notice Get a total amount of the collateral that can be slashed.
     * @return total amount of the slashable collateral
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Get an active balance for a particular account at a given timestamp.
     * @param account account to get the active balance for
     * @param timestamp time point to get the active balance for the account at
     * @return active balance for the account at the timestamp
     */
    function activeBalanceOfAt(address account, uint48 timestamp) external view returns (uint256);

    /**
     * @notice Get an active balance for a particular account.
     * @param account account to get the active balance for
     * @return active balance for the account
     */
    function activeBalanceOf(address account) external view returns (uint256);

    /**
     * @notice Get pending withdrawals for a particular account at a given epoch (zero if claimed).
     * @param epoch epoch to get the pending withdrawals for the account at
     * @param account account to get the pending withdrawals for
     * @return pending withdrawals for the account at the epoch
     */
    function pendingWithdrawalsOf(uint256 epoch, address account) external view returns (uint256);

    /**
     * @notice Deposit collateral into the vault.
     * @param onBehalfOf account the deposit is made on behalf of
     * @param amount amount of the collateral to deposit
     * @return shares amount of the active shares minted
     */
    function deposit(address onBehalfOf, uint256 amount) external returns (uint256 shares);

    /**
     * @notice Withdraw collateral from the vault (it will be claimable after the next epoch).
     * @param claimer account that needs to claim the withdrawal
     * @param amount amount of the collateral to withdraw
     * @return burnedShares amount of the active shares burned
     * @return mintedShares amount of the epoch withdrawal shares minted
     */
    function withdraw(address claimer, uint256 amount) external returns (uint256 burnedShares, uint256 mintedShares);

    /**
     * @notice Claim collateral from the vault.
     * @param recipient account that receives the collateral
     * @param epoch epoch to claim the collateral for
     * @return amount amount of the collateral claimed
     */
    function claim(address recipient, uint256 epoch) external returns (uint256 amount);

    /**
     * @notice Slash callback for burning collateral.
     * @param slashedAmount amount to slash
     * @return actualSlashedAmount amount of burned collateral
     */
    function onSlash(uint256 slashedAmount) external returns (uint256 actualSlashedAmount);

    /**
     * @notice Set an admin fee.
     * @param adminFee admin fee (up to ADMIN_FEE_BASE inclusively)
     * @dev Only the ADMIN_FEE_SET_ROLE holder can call this function.
     */
    function setAdminFee(uint256 adminFee) external;

    /**
     * @notice Enable/disable deposit whitelist.
     * @param status if enabling deposit whitelist
     * @dev Only the DEPOSIT_WHITELIST_SET_ROLE holder can call this function.
     */
    function setDepositWhitelist(bool status) external;

    /**
     * @notice Set a depositor whitelist status.
     * @param account account for which the whitelist status is set
     * @param status if whitelisting the account
     * @dev Only the DEPOSITOR_WHITELIST_ROLE holder can call this function.
     */
    function setDepositorWhitelistStatus(address account, bool status) external;
}
