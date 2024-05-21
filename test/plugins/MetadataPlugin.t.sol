// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {NonMigratablesRegistry} from "src/contracts/NonMigratablesRegistry.sol";
import {IPlugin} from "src/interfaces/IPlugin.sol";

import {MetadataPlugin} from "src/contracts/plugins/MetadataPlugin.sol";
import {IMetadataPlugin} from "src/interfaces/plugins/IMetadataPlugin.sol";

contract MetadataPluginTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    NonMigratablesRegistry registry;

    IMetadataPlugin plugin;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        registry = new NonMigratablesRegistry();
    }

    function test_Create(string calldata metadataURL_) public {
        plugin = IMetadataPlugin(address(new MetadataPlugin(address(registry))));

        assertEq(plugin.metadataURL(alice), "");

        vm.startPrank(alice);
        registry.register();
        vm.stopPrank();

        vm.startPrank(alice);
        plugin.setMetadataURL(metadataURL_);
        vm.stopPrank();

        assertEq(plugin.metadataURL(alice), metadataURL_);
    }

    function test_SetNumberRevertNotEntity(string calldata metadataURL_) public {
        plugin = IMetadataPlugin(address(new MetadataPlugin(address(registry))));

        vm.startPrank(alice);
        vm.expectRevert(IPlugin.NotEntity.selector);
        plugin.setMetadataURL(metadataURL_);
        vm.stopPrank();
    }
}