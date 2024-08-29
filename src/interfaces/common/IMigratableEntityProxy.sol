// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface IMigratableEntityProxy {
    error NotInitialized();

    /**
     * @notice Upgrade the proxy to a new implementation and call a function on the new implementation.
     * @param newImplementation address of the new implementation
     * @param data data to call on the new implementation
     */
    function upgradeToAndCall(address newImplementation, bytes calldata data) external;
}
