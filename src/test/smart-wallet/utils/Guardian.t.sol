// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import { GuardianAccountFactory } from "contracts/prebuilts/account/guardian/GuardianAccountFactory.sol";
import { Guardian } from "contracts/prebuilts/account/utils/Guardian.sol";
import { IGuardian } from "contracts/prebuilts/account/interface/IGuardian.sol";
import { Test } from "forge-std/Test.sol";
import { DeploySmartAccountUtilContracts } from "scripts/DeploySmartAccountUtilContracts.s.sol";

contract GuardianTest is Test {
    Guardian public guardian;
    address account;
    GuardianAccountFactory factory;
    DeploySmartAccountUtilContracts deployer;
    address public user = makeAddr("guardianUser");
    uint256 public STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        deployer = new DeploySmartAccountUtilContracts();
        (account, factory, guardian, , , ) = deployer.run();
        vm.deal(user, STARTING_USER_BALANCE);
    }

    /////////////////////////////////////////
    ///// addVerifiedGuardian() tests //////
    ///////////////////////////////////////

    function testAddVerifiedGuardian() external {
        vm.prank(user);
        guardian.addVerifiedGuardian();

        vm.prank(address(factory));
        assert(guardian.getVerifiedGuardians().length > 0);
    }

    function testRevertIfZeroAddressBeingAddedAsGuardian() external {
        vm.prank(address(0));
        vm.expectRevert();
        guardian.addVerifiedGuardian();
    }

    function testRevertIfSameGuardianAddedTwice() external {
        vm.startPrank(user);
        guardian.addVerifiedGuardian();

        vm.expectRevert(abi.encodeWithSelector(IGuardian.GuardianAlreadyExists.selector, user));
        guardian.addVerifiedGuardian();
    }

    /////////////////////////////////////////
    ///// isVerifiedGuardian() test //////
    ///////////////////////////////////////

    function testIsGuardianVerified() external {
        // setup
        vm.prank(user);
        guardian.addVerifiedGuardian();

        assertEq(guardian.isVerifiedGuardian(user), true);
    }

    ///////////////////////////////////////
    ///// removeVerifiedGuardian() test ///////////
    ///////////////////////////////////////

    function testremoveVerifiedGuardian() external {
        // Arrange
        vm.prank(user);
        guardian.addVerifiedGuardian();
        assertEq(guardian.isVerifiedGuardian(user), true);

        // Act
        vm.prank(user);
        guardian.removeVerifiedGuardian();

        //Assert
        assertEq(guardian.isVerifiedGuardian(user), false);
    }

    function testRevertOnRemovingGuardianThatDoesNotExist() external {
        // ACT
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IGuardian.NotAGuardian.selector, user));
        guardian.removeVerifiedGuardian();
    }

    ///////////////////////////////////////
    ///// getVerified() test //////////////
    ///////////////////////////////////////
    function testGetVerifiedGuardians() external {
        // SETUP
        vm.prank(user);
        guardian.addVerifiedGuardian();

        // ACT/assert
        vm.prank(address(factory));
        uint256 verifiedGuardiansCount = guardian.getVerifiedGuardians().length;
        assertEq(verifiedGuardiansCount, 1);
    }

    function testRevertIfNonOwnerCallsGetVerified() external {
        vm.prank(user);
        vm.expectRevert(Guardian.NotOwner.selector);
        guardian.getVerifiedGuardians();
    }

    /////////////////////////////////////////////
    ///// linkAccountToAccountGuardian() test ////
    //////////////////////////////////////////////

    function testLinkingAccountToAccountGuardian() external {
        // Setup
        address accountGuardian = makeAddr("accountGuardian");
        guardian.linkAccountToAccountGuardian(account, accountGuardian);

        assertEq(guardian.getAccountGuardian(account), accountGuardian);
    }
}
