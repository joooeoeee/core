// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {VaultFactory} from "src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "src/contracts/SlasherFactory.sol";
import {NetworkRegistry} from "src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "src/contracts/OperatorRegistry.sol";
import {MetadataService} from "src/contracts/service/MetadataService.sol";
import {NetworkMiddlewareService} from "src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "src/contracts/service/OptInService.sol";

import {Vault} from "src/contracts/vault/Vault.sol";
import {NetworkRestakeDelegator} from "src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "src/contracts/delegator/FullRestakeDelegator.sol";
import {Slasher} from "src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "src/contracts/slasher/VetoSlasher.sol";

import {IVault} from "src/interfaces/vault/IVault.sol";
import {SimpleCollateral} from "test/mocks/SimpleCollateral.sol";
import {Token} from "test/mocks/Token.sol";
import {VaultConfigurator} from "src/contracts/VaultConfigurator.sol";
import {IVaultConfigurator} from "src/interfaces/IVaultConfigurator.sol";
import {INetworkRestakeDelegator} from "src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IFullRestakeDelegator} from "src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IBaseDelegator} from "src/interfaces/delegator/IBaseDelegator.sol";

import {IVaultStorage} from "src/interfaces/vault/IVaultStorage.sol";

contract NetworkRestakeDelegatorTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    VaultFactory vaultFactory;
    DelegatorFactory delegatorFactory;
    SlasherFactory slasherFactory;
    NetworkRegistry networkRegistry;
    OperatorRegistry operatorRegistry;
    MetadataService operatorMetadataService;
    MetadataService networkMetadataService;
    NetworkMiddlewareService networkMiddlewareService;
    OptInService networkVaultOptInService;
    OptInService operatorVaultOptInService;
    OptInService operatorNetworkOptInService;

    SimpleCollateral collateral;
    VaultConfigurator vaultConfigurator;

    Vault vault;
    NetworkRestakeDelegator delegator;
    Slasher slasher;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        vaultFactory = new VaultFactory(owner);
        delegatorFactory = new DelegatorFactory(owner);
        slasherFactory = new SlasherFactory(owner);
        networkRegistry = new NetworkRegistry();
        operatorRegistry = new OperatorRegistry();
        operatorMetadataService = new MetadataService(address(operatorRegistry));
        networkMetadataService = new MetadataService(address(networkRegistry));
        networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
        networkVaultOptInService = new OptInService(address(networkRegistry), address(vaultFactory));
        operatorVaultOptInService = new OptInService(address(operatorRegistry), address(vaultFactory));
        operatorNetworkOptInService = new OptInService(address(operatorRegistry), address(networkRegistry));

        address vaultImpl =
            address(new Vault(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultImpl);

        address networkRestakeDelegatorImpl = address(
            new NetworkRestakeDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory)
            )
        );
        delegatorFactory.whitelist(networkRestakeDelegatorImpl);

        address fullRestakeDelegatorImpl = address(
            new FullRestakeDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory)
            )
        );
        delegatorFactory.whitelist(fullRestakeDelegatorImpl);

        address slasherImpl = address(
            new Slasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkVaultOptInService),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(slasherFactory)
            )
        );
        slasherFactory.whitelist(slasherImpl);

        address vetoSlasherImpl = address(
            new VetoSlasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkVaultOptInService),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(networkRegistry),
                address(slasherFactory)
            )
        );
        slasherFactory.whitelist(vetoSlasherImpl);

        Token token = new Token("Token");
        collateral = new SimpleCollateral(address(token));

        collateral.mint(token.totalSupply());

        vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));
    }

    function test_Create(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, type(uint48).max));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        assertEq(delegator.VERSION(), 1);
        assertEq(delegator.NETWORK_REGISTRY(), address(networkRegistry));
        assertEq(delegator.VAULT_FACTORY(), address(vaultFactory));
        assertEq(delegator.OPERATOR_VAULT_OPT_IN_SERVICE(), address(operatorVaultOptInService));
        assertEq(delegator.OPERATOR_NETWORK_OPT_IN_SERVICE(), address(operatorNetworkOptInService));
        assertEq(delegator.vault(), address(vault));
        assertEq(delegator.maxNetworkLimit(alice), 0);
        assertEq(delegator.networkStakeIn(alice, 0), 0);
        assertEq(delegator.networkStake(alice), 0);
        assertEq(delegator.operatorNetworkStakeIn(alice, alice, 0), 0);
        assertEq(delegator.operatorNetworkStake(alice, alice), 0);
        assertEq(delegator.minOperatorNetworkStakeDuring(alice, alice, 0), 0);
        assertEq(delegator.NETWORK_LIMIT_SET_ROLE(), keccak256("NETWORK_LIMIT_SET_ROLE"));
        assertEq(delegator.OPERATOR_NETWORK_SHARES_SET_ROLE(), keccak256("OPERATOR_NETWORK_SHARES_SET_ROLE"));
        assertEq(delegator.networkLimitIn(alice, 0), 0);
        assertEq(delegator.networkLimit(alice), 0);
        assertEq(delegator.totalOperatorNetworkSharesIn(alice, 0), 0);
        assertEq(delegator.totalOperatorNetworkShares(alice), 0);
        assertEq(delegator.operatorNetworkSharesIn(alice, alice, 0), 0);
        assertEq(delegator.operatorNetworkShares(alice, alice), 0);
    }

    function test_CreateRevertNotVault(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, type(uint48).max));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        vm.expectRevert(IBaseDelegator.NotVault.selector);
        delegatorFactory.create(
            0,
            true,
            abi.encode(
                address(1),
                abi.encode(
                    INetworkRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({defaultAdminRoleHolder: bob}),
                        networkLimitSetRoleHolder: bob,
                        operatorNetworkSharesSetRoleHolder: bob
                    })
                )
            )
        );
    }

    function test_CreateRevertMissingRoleHolders(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, type(uint48).max));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        vm.expectRevert(INetworkRestakeDelegator.MissingRoleHolders.selector);
        delegatorFactory.create(
            1,
            true,
            abi.encode(
                address(vault),
                abi.encode(
                    INetworkRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({defaultAdminRoleHolder: address(0)}),
                        networkLimitSetRoleHolder: address(0),
                        operatorNetworkSharesSetRoleHolder: bob
                    })
                )
            )
        );
    }

    function test_OnSlashRevertNotSlasher(uint48 epochDuration) public {
        epochDuration = uint48(bound(epochDuration, 1, type(uint48).max));

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        vm.startPrank(alice);
        vm.expectRevert(IBaseDelegator.NotSlasher.selector);
        delegator.onSlash(address(0), address(0), 0);
        vm.stopPrank();
    }

    function test_SetMaxNetworkLimit(uint48 epochDuration, uint256 maxNetworkLimit1, uint256 maxNetworkLimit2) public {
        epochDuration = uint48(bound(epochDuration, 1, type(uint48).max));
        maxNetworkLimit1 = bound(maxNetworkLimit1, 1, type(uint256).max);
        vm.assume(maxNetworkLimit1 != maxNetworkLimit2);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        _registerNetwork(alice, alice);

        _setMaxNetworkLimit(alice, maxNetworkLimit1);

        assertEq(delegator.maxNetworkLimit(alice), maxNetworkLimit1);

        _setMaxNetworkLimit(alice, maxNetworkLimit2);

        assertEq(delegator.maxNetworkLimit(alice), maxNetworkLimit2);
    }

    function test_SetMaxNetworkLimitRevertNotNetwork(uint48 epochDuration, uint256 maxNetworkLimit) public {
        epochDuration = uint48(bound(epochDuration, 1, type(uint48).max));
        maxNetworkLimit = bound(maxNetworkLimit, 1, type(uint256).max);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        _registerNetwork(alice, alice);

        vm.expectRevert(IBaseDelegator.NotNetwork.selector);
        _setMaxNetworkLimit(bob, maxNetworkLimit);
    }

    function test_SetMaxNetworkLimitRevertAlreadySet(uint48 epochDuration, uint256 maxNetworkLimit) public {
        epochDuration = uint48(bound(epochDuration, 1, type(uint48).max));
        maxNetworkLimit = bound(maxNetworkLimit, 1, type(uint256).max);

        (vault, delegator) = _getVaultAndDelegator(epochDuration);

        _registerNetwork(alice, alice);

        _setMaxNetworkLimit(alice, maxNetworkLimit);

        vm.expectRevert(IBaseDelegator.AlreadySet.selector);
        _setMaxNetworkLimit(alice, maxNetworkLimit);
    }

    function _getVaultAndDelegator(uint48 epochDuration) internal returns (Vault, NetworkRestakeDelegator) {
        (address vault_, address delegator_,) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: alice,
                vaultParams: IVault.InitParams({
                    collateral: address(collateral),
                    delegator: address(0),
                    slasher: address(0),
                    burner: address(0xdEaD),
                    epochDuration: epochDuration,
                    slasherSetEpochsDelay: 3,
                    depositWhitelist: false,
                    defaultAdminRoleHolder: alice,
                    slasherSetRoleHolder: alice,
                    depositorWhitelistRoleHolder: alice
                }),
                delegatorIndex: 0,
                delegatorParams: abi.encode(
                    INetworkRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({defaultAdminRoleHolder: alice}),
                        networkLimitSetRoleHolder: alice,
                        operatorNetworkSharesSetRoleHolder: alice
                    })
                ),
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: ""
            })
        );

        return (Vault(vault_), NetworkRestakeDelegator(delegator_));
    }

    function _getSlasher(address vault_) internal returns (Slasher) {
        return Slasher(slasherFactory.create(0, true, abi.encode(address(vault_), "")));
    }

    function _registerOperator(address user) internal {
        vm.startPrank(user);
        operatorRegistry.registerOperator();
        vm.stopPrank();
    }

    function _registerNetwork(address user, address middleware) internal {
        vm.startPrank(user);
        networkRegistry.registerNetwork();
        networkMiddlewareService.setMiddleware(middleware);
        vm.stopPrank();
    }

    function _grantDepositorWhitelistRole(address user, address account) internal {
        vm.startPrank(user);
        Vault(address(vault)).grantRole(vault.DEPOSITOR_WHITELIST_ROLE(), account);
        vm.stopPrank();
    }

    function _grantDepositWhitelistSetRole(address user, address account) internal {
        vm.startPrank(user);
        Vault(address(vault)).grantRole(vault.DEPOSIT_WHITELIST_SET_ROLE(), account);
        vm.stopPrank();
    }

    function _deposit(address user, uint256 amount) internal returns (uint256 shares) {
        collateral.transfer(user, amount);
        vm.startPrank(user);
        collateral.approve(address(vault), amount);
        shares = vault.deposit(user, amount);
        vm.stopPrank();
    }

    function _withdraw(address user, uint256 amount) internal returns (uint256 burnedShares, uint256 mintedShares) {
        vm.startPrank(user);
        (burnedShares, mintedShares) = vault.withdraw(user, amount);
        vm.stopPrank();
    }

    function _claim(address user, uint256 epoch) internal returns (uint256 amount) {
        vm.startPrank(user);
        amount = vault.claim(user, epoch);
        vm.stopPrank();
    }

    function _optInNetworkVault(address user) internal {
        vm.startPrank(user);
        networkVaultOptInService.optIn(address(vault));
        vm.stopPrank();
    }

    function _optOutNetworkVault(address user) internal {
        vm.startPrank(user);
        networkVaultOptInService.optOut(address(vault));
        vm.stopPrank();
    }

    function _optInOperatorVault(address user) internal {
        vm.startPrank(user);
        operatorVaultOptInService.optIn(address(vault));
        vm.stopPrank();
    }

    function _optOutOperatorVault(address user) internal {
        vm.startPrank(user);
        operatorVaultOptInService.optOut(address(vault));
        vm.stopPrank();
    }

    function _optInOperatorNetwork(address user, address network) internal {
        vm.startPrank(user);
        operatorNetworkOptInService.optIn(network);
        vm.stopPrank();
    }

    function _optOutOperatorNetwork(address user, address network) internal {
        vm.startPrank(user);
        operatorNetworkOptInService.optOut(network);
        vm.stopPrank();
    }

    function _setDepositWhitelist(address user, bool depositWhitelist) internal {
        vm.startPrank(user);
        vault.setDepositWhitelist(depositWhitelist);
        vm.stopPrank();
    }

    function _setDepositorWhitelistStatus(address user, address depositor, bool status) internal {
        vm.startPrank(user);
        vault.setDepositorWhitelistStatus(depositor, status);
        vm.stopPrank();
    }

    function _setSlasher(address user, address slasher_) internal {
        vm.startPrank(user);
        vault.setSlasher(slasher_);
        vm.stopPrank();
    }

    function _setNetworkLimit(address user, address network, uint256 amount) internal {
        vm.startPrank(user);
        delegator.setNetworkLimit(network, amount);
        vm.stopPrank();
    }

    function _setOperatorNetworkShares(address user, address network, address operator, uint256 shares) internal {
        vm.startPrank(user);
        delegator.setOperatorNetworkShares(network, operator, shares);
        vm.stopPrank();
    }

    function _slash(address user, address network, address operator, uint256 amount) internal {
        vm.startPrank(user);
        slasher.slash(network, operator, amount);
        vm.stopPrank();
    }

    function _setMaxNetworkLimit(address user, uint256 amount) internal {
        vm.startPrank(user);
        delegator.setMaxNetworkLimit(amount);
        vm.stopPrank();
    }
}
