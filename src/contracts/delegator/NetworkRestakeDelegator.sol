// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {BaseDelegator} from "./BaseDelegator.sol";

import {INetworkRestakeDelegator} from "src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IBaseDelegator} from "src/interfaces/delegator/IBaseDelegator.sol";
import {IVault} from "src/interfaces/vault/IVault.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract NetworkRestakeDelegator is BaseDelegator, INetworkRestakeDelegator {
    using Checkpoints for Checkpoints.Trace256;
    using Math for uint256;

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    bytes32 public constant NETWORK_LIMIT_SET_ROLE = keccak256("NETWORK_LIMIT_SET_ROLE");

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    bytes32 public constant OPERATOR_NETWORK_SHARES_SET_ROLE = keccak256("OPERATOR_NETWORK_SHARES_SET_ROLE");

    mapping(address network => Checkpoints.Trace256 value) private _networkLimit;

    mapping(address network => Checkpoints.Trace256 shares) private _totalOperatorNetworkShares;

    mapping(address network => mapping(address operator => Checkpoints.Trace256 shares)) private _operatorNetworkShares;

    constructor(
        address networkRegistry,
        address vaultFactory,
        address operatorVaultOptInService,
        address operatorNetworkOptInService,
        address delegatorFactory
    )
        BaseDelegator(
            networkRegistry,
            vaultFactory,
            operatorVaultOptInService,
            operatorNetworkOptInService,
            delegatorFactory
        )
    {}

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function networkLimitIn(address network, uint48 duration) public view returns (uint256) {
        return _networkLimit[network].upperLookupRecent(Time.timestamp() + duration);
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function networkLimit(address network) public view returns (uint256) {
        return _networkLimit[network].upperLookupRecent(Time.timestamp());
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function totalOperatorNetworkSharesIn(address network, uint48 duration) public view returns (uint256) {
        return _totalOperatorNetworkShares[network].upperLookupRecent(Time.timestamp() + duration);
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function totalOperatorNetworkShares(address network) public view returns (uint256) {
        return _totalOperatorNetworkShares[network].upperLookupRecent(Time.timestamp());
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function operatorNetworkSharesIn(
        address network,
        address operator,
        uint48 duration
    ) public view returns (uint256) {
        return _operatorNetworkShares[network][operator].upperLookupRecent(Time.timestamp() + duration);
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function operatorNetworkShares(address network, address operator) public view returns (uint256) {
        return _operatorNetworkShares[network][operator].upperLookupRecent(Time.timestamp());
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function networkStakeIn(
        address network,
        uint48 duration
    ) public view override(IBaseDelegator, BaseDelegator) returns (uint256) {
        if (totalOperatorNetworkSharesIn(network, duration) == 0) {
            return 0;
        }
        return Math.min(IVault(vault).totalSupplyIn(duration), networkLimitIn(network, duration));
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function networkStake(address network) public view override(IBaseDelegator, BaseDelegator) returns (uint256) {
        if (totalOperatorNetworkShares(network) == 0) {
            return 0;
        }
        return Math.min(IVault(vault).totalSupply(), networkLimit(network));
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function operatorNetworkStakeIn(
        address network,
        address operator,
        uint48 duration
    ) public view override(IBaseDelegator, BaseDelegator) returns (uint256) {
        uint256 totalOperatorNetworkSharesIn_ = totalOperatorNetworkSharesIn(network, duration);
        if (totalOperatorNetworkSharesIn_ == 0) {
            return 0;
        }
        return operatorNetworkSharesIn(network, operator, duration).mulDiv(
            networkStakeIn(network, duration), totalOperatorNetworkSharesIn_
        );
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function operatorNetworkStake(
        address network,
        address operator
    ) public view override(IBaseDelegator, BaseDelegator) returns (uint256) {
        uint256 totalOperatorNetworkShares_ = totalOperatorNetworkShares(network);
        if (totalOperatorNetworkShares_ == 0) {
            return 0;
        }
        return operatorNetworkShares(network, operator).mulDiv(networkStake(network), totalOperatorNetworkShares_);
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function setNetworkLimit(address network, uint256 amount) external onlyRole(NETWORK_LIMIT_SET_ROLE) {
        if (amount > maxNetworkLimit[network]) {
            revert ExceedsMaxNetworkLimit();
        }

        uint48 epochDuration = IVault(vault).epochDuration();
        uint48 nextEpochStart = IVault(vault).currentEpochStart() + epochDuration;
        (, uint48 checkpointTimestamp,,) = _networkLimit[network].upperLookupRecentCheckpoint(nextEpochStart);

        uint48 timestamp = checkpointTimestamp < Time.timestamp() && amount > networkLimit(network)
            ? Time.timestamp()
            : nextEpochStart + epochDuration;

        _insertCheckpoint(_networkLimit[network], timestamp, amount);

        emit SetNetworkLimit(network, amount);
    }

    /**
     * @inheritdoc INetworkRestakeDelegator
     */
    function setOperatorsNetworkShares(
        address network,
        address[] calldata operators,
        uint256[] calldata shares
    ) external onlyRole(OPERATOR_NETWORK_SHARES_SET_ROLE) {
        uint256 length = operators.length;
        if (length == 0 || length != shares.length) {
            revert InvalidLength();
        }

        uint48 epochDuration = IVault(vault).epochDuration();
        uint48 nextEpochStart = IVault(vault).currentEpochStart() + epochDuration;
        (, uint48 checkpointTimestamp,,) =
            _totalOperatorNetworkShares[network].upperLookupRecentCheckpoint(nextEpochStart);

        bool isInstantUpdate = checkpointTimestamp < Time.timestamp() && totalOperatorNetworkShares(network) == 0;
        uint48 timestamp = isInstantUpdate ? Time.timestamp() : nextEpochStart + epochDuration;
        uint256 totalOperatorNetworkShares_;
        if (!isInstantUpdate) {
            totalOperatorNetworkShares_ = _totalOperatorNetworkShares[network].latest();
        }

        for (uint256 i; i < length; ++i) {
            if (isInstantUpdate) {
                if (operatorNetworkShares(network, operators[i]) != 0) {
                    revert DuplicateOperator();
                }
                if (shares[i] == 0) {
                    revert ZeroShares();
                }
                totalOperatorNetworkShares_ += shares[i];
            } else {
                totalOperatorNetworkShares_ =
                    totalOperatorNetworkShares_ - _operatorNetworkShares[network][operators[i]].latest() + shares[i];
            }

            _insertCheckpoint(_operatorNetworkShares[network][operators[i]], timestamp, shares[i]);

            emit SetOperatorNetworkShares(network, operators[i], shares[i]);
        }

        _insertCheckpoint(_totalOperatorNetworkShares[network], timestamp, totalOperatorNetworkShares_);
    }

    function _minOperatorNetworkStakeDuring(
        address network,
        address operator,
        uint48 duration
    ) internal view override returns (uint256 minOperatorNetworkStakeDuring_) {
        uint48 epochDuration = IVault(vault).epochDuration();

        uint256 totalOperatorNetworkShares_ = totalOperatorNetworkShares(network);
        if (totalOperatorNetworkShares_ != 0) {
            minOperatorNetworkStakeDuring_ = operatorNetworkShares(network, operator).mulDiv(
                Math.min(IVault(vault).activeSupply(), networkLimit(network)), totalOperatorNetworkShares_
            );
        }
        if (Time.timestamp() + duration >= IVault(vault).currentEpochStart() + epochDuration) {
            uint256 totalOperatorNetworkSharesIn_ = totalOperatorNetworkSharesIn(network, epochDuration);
            minOperatorNetworkStakeDuring_ = totalOperatorNetworkSharesIn_ == 0
                ? 0
                : Math.min(
                    minOperatorNetworkStakeDuring_,
                    operatorNetworkSharesIn(network, operator, epochDuration).mulDiv(
                        Math.min(IVault(vault).activeSupply(), networkLimitIn(network, epochDuration)),
                        totalOperatorNetworkSharesIn_
                    )
                );
        }
    }

    function _setMaxNetworkLimit(uint256 amount) internal override {
        Checkpoints.Trace256 storage _networkLimit_ = _networkLimit[msg.sender];
        (bool exists, uint48 latestTimestamp1, uint256 latestValue1) = _networkLimit_.latestCheckpoint();
        if (exists) {
            if (Time.timestamp() < latestTimestamp1) {
                _networkLimit_.pop();
                (, uint48 latestTimestamp2, uint256 latestValue2) = _networkLimit_.latestCheckpoint();
                if (Time.timestamp() < latestTimestamp2) {
                    _networkLimit_.pop();
                    _networkLimit_.push(Time.timestamp(), Math.min(_networkLimit_.latest(), amount));
                    _networkLimit_.push(latestTimestamp2, Math.min(latestValue2, amount));
                } else {
                    _networkLimit_.push(Time.timestamp(), Math.min(latestValue2, amount));
                }
                _networkLimit_.push(latestTimestamp1, Math.min(latestValue1, amount));
            } else {
                _networkLimit_.push(Time.timestamp(), Math.min(latestValue1, amount));
            }
        }
    }

    function _onSlash(address network, address operator, uint256 slashedAmount) internal override {
        uint256 networkLimit_ = networkLimit(network);
        uint256 operatorNetworkShares_ = operatorNetworkShares(network, operator);
        uint256 operatorSlashedShares =
            slashedAmount.mulDiv(operatorNetworkShares_, operatorNetworkStake(network, operator), Math.Rounding.Ceil);

        if (networkLimit_ != type(uint256).max) {
            _insertCheckpoint(_networkLimit[network], Time.timestamp(), networkLimit_ - slashedAmount);
        }

        _insertCheckpoint(
            _totalOperatorNetworkShares[network],
            Time.timestamp(),
            totalOperatorNetworkShares(network) - operatorSlashedShares
        );

        _insertCheckpoint(
            _operatorNetworkShares[network][operator], Time.timestamp(), operatorNetworkShares_ - operatorSlashedShares
        );
    }

    function _initializeInternal(
        address,
        bytes memory data
    ) internal override returns (IBaseDelegator.BaseParams memory) {
        InitParams memory params = abi.decode(data, (InitParams));

        if (
            params.baseParams.defaultAdminRoleHolder == address(0)
                && (
                    params.networkLimitSetRoleHolder == address(0)
                        || params.operatorNetworkSharesSetRoleHolder == address(0)
                )
        ) {
            revert MissingRoleHolders();
        }

        if (params.networkLimitSetRoleHolder != address(0)) {
            _grantRole(NETWORK_LIMIT_SET_ROLE, params.networkLimitSetRoleHolder);
        }
        if (params.operatorNetworkSharesSetRoleHolder != address(0)) {
            _grantRole(OPERATOR_NETWORK_SHARES_SET_ROLE, params.operatorNetworkSharesSetRoleHolder);
        }

        return params.baseParams;
    }
}
