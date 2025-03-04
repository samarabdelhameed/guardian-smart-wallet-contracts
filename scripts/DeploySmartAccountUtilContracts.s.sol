// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import { Script } from "forge-std/Script.sol";
import { EntryPoint } from "contracts/prebuilts/account/utils/EntryPoint.sol";
import { HelperConfig } from "./HelperConfig.s.sol";
import { AccountLock } from "contracts/prebuilts/account/utils/AccountLock.sol";
import { GuardianAccountFactory } from "contracts/prebuilts/account/guardian/GuardianAccountFactory.sol";
import { Account } from "contracts/prebuilts/account/non-upgradeable/Account.sol";
import { Guardian } from "contracts/prebuilts/account/utils/Guardian.sol";
import { AccountGuardian } from "contracts/prebuilts/account/utils/AccountGuardian.sol";
import { AccountRecovery } from "contracts/prebuilts/account/utils/AccountRecovery.sol";

contract DeploySmartAccountUtilContracts is Script {
    address public admin = makeAddr("admin");
    address smartWalletAccount;
    address payable entryPointAddress;
    EntryPoint entryPoint;
    address networkAccount;
    HelperConfig.NetworkConfig activeNetworkConfig;

    constructor() {
        HelperConfig config = new HelperConfig();
        (networkAccount, entryPointAddress) = config.activeNetworkConfig();

        entryPoint = EntryPoint(entryPointAddress);
    }

    // This deploy script should only be used for testing purposes as it deploys a smart account as well.
    function run()
        external
        returns (address, GuardianAccountFactory, Guardian, AccountLock, AccountGuardian, AccountRecovery)
    {
        GuardianAccountFactory guardianAccountFactory;

        uint64 currentNonce = vm.getNonce(networkAccount);
        vm.setNonce(networkAccount, currentNonce);

        vm.broadcast(networkAccount);
        guardianAccountFactory = new GuardianAccountFactory(entryPoint);

        ///@dev accountGuardian is deployed when new smart account is created using the AccountFactory::createAccount(...)
        vm.setNonce(networkAccount, currentNonce + 1);
        vm.prank(networkAccount);
        smartWalletAccount = guardianAccountFactory.createAccount(admin, abi.encode("shiven@gmail.com"));

        Guardian guardianContract = guardianAccountFactory.guardian();
        AccountLock accountLock = guardianAccountFactory.accountLock();

        AccountGuardian accountGuardian = AccountGuardian(guardianContract.getAccountGuardian(smartWalletAccount));

        AccountRecovery accountRecovery = AccountRecovery(guardianContract.getAccountRecovery(smartWalletAccount));

        return (
            smartWalletAccount,
            guardianAccountFactory,
            guardianContract,
            accountLock,
            accountGuardian,
            accountRecovery
        );
    }
}
