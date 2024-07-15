// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

abstract contract StaticDelegateCallable {
    function staticDelegateCall(address target, bytes memory data) external {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        bytes memory revertData = abi.encode(success, returndata);
        assembly {
            revert(add(32, revertData), mload(revertData))
        }
    }
}