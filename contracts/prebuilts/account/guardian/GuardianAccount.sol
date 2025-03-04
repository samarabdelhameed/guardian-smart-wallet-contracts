// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */
/* solhint-disable reason-string */

// Base
import "../utils/BaseAccount.sol";

// Extensions
import "../utils/AccountCore.sol";
import "../../../extension/upgradeable/ContractMetadata.sol";
import "../../../external-deps/openzeppelin/token/ERC721/utils/ERC721Holder.sol";
import "../../../external-deps/openzeppelin/token/ERC1155/utils/ERC1155Holder.sol";

// Utils
import "../../../eip/ERC1271.sol";
import "../utils/Helpers.sol";
import "../../../external-deps/openzeppelin/utils/cryptography/ECDSA.sol";
import "forge-std/console.sol";
import { GuardianAccountFactory } from "./GuardianAccountFactory.sol";
import { Guardian } from "../utils/Guardian.sol";
import { AccountLock } from "../utils/AccountLock.sol";

//   $$\     $$\       $$\                 $$\                         $$\
//   $$ |    $$ |      \__|                $$ |                        $$ |
// $$$$$$\   $$$$$$$\  $$\  $$$$$$\   $$$$$$$ |$$\  $$\  $$\  $$$$$$\  $$$$$$$\
// \_$$  _|  $$  __$$\ $$ |$$  __$$\ $$  __$$ |$$ | $$ | $$ |$$  __$$\ $$  __$$\
//   $$ |    $$ |  $$ |$$ |$$ |  \__|$$ /  $$ |$$ | $$ | $$ |$$$$$$$$ |$$ |  $$ |
//   $$ |$$\ $$ |  $$ |$$ |$$ |      $$ |  $$ |$$ | $$ | $$ |$$   ____|$$ |  $$ |
//   \$$$$  |$$ |  $$ |$$ |$$ |      \$$$$$$$ |\$$$$$\$$$$  |\$$$$$$$\ $$$$$$$  |
//    \____/ \__|  \__|\__|\__|       \_______| \_____\____/  \_______|\_______/

contract GuardianAccount is AccountCore, ContractMetadata, ERC1271, ERC721Holder, ERC1155Holder {
    using ECDSA for bytes32;
    using EnumerableSet for EnumerableSet.AddressSet;
    bool public paused;
    Guardian guardian;

    error NotAuthorizedToLock(address locker, address accountLock);

    /*///////////////////////////////////////////////////////////////
                    Constructor, Initializer, Modifiers
    //////////////////////////////////////////////////////////////*/

    constructor(IEntryPoint _entrypoint, address _factory) AccountCore(_entrypoint, _factory) {
        paused = false;
    }

    /// @notice Checks whether the caller is the EntryPoint contract or the admin.
    modifier onlyAdminOrEntrypoint() virtual {
        require(msg.sender == address(entryPoint()) || isAdmin(msg.sender), "Account: not admin or EntryPoint.");
        _;
    }

    /// @notice The account can be paused only by the AccountLock contract
    modifier onlyAccountLock(address locker) {
        if (locker != accountLock) {
            revert NotAuthorizedToLock(locker, accountLock);
        }
        _;
    }

    modifier onlyAccountRecovery(address sender) {
        if (Guardian(commonGuardian).getAccountRecovery(address(this)) != sender) {
            revert("Only Account Recovery Contract allowed to update admin");
        }
        _;
    }

    /// @notice Will check if the Account transactions has been paused by the guardians. If paused, it will not allow the `execute(..)` or the `executeBatch(..)` function to run.
    modifier whenNotPaused() {
        require(!paused, "Smart account has been paused.");
        _;
    }

    /// @notice Lets the account receive native tokens.
    receive() external payable {}

    /*///////////////////////////////////////////////////////////////
                            View functions
    //////////////////////////////////////////////////////////////*/

    /// @notice See {IERC165-supportsInterface}.
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155Receiver) returns (bool) {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @notice See EIP-1271
    function isValidSignature(
        bytes32 _hash,
        bytes memory _signature
    ) public view virtual override returns (bytes4 magicValue) {
        address signer = _hash.recover(_signature);

        if (isAdmin(signer)) {
            return MAGICVALUE;
        }

        address caller = msg.sender;
        EnumerableSet.AddressSet storage approvedTargets = _accountPermissionsStorage().approvedTargets[signer];

        require(
            approvedTargets.contains(caller) || (approvedTargets.length() == 1 && approvedTargets.at(0) == address(0)),
            "Account: caller not approved target."
        );

        if (isActiveSigner(signer)) {
            magicValue = MAGICVALUE;
        }
    }

    /*///////////////////////////////////////////////////////////////
                            External functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Executes a transaction (called directly from an admin, or by entryPoint)
    function execute(
        address _target,
        uint256 _value,
        bytes calldata _calldata
    ) external virtual onlyAdminOrEntrypoint whenNotPaused {
        _registerOnFactory();
        _call(_target, _value, _calldata);
    }

    /// @notice Executes a sequence transaction (called directly from an admin, or by entryPoint)
    function executeBatch(
        address[] calldata _target,
        uint256[] calldata _value,
        bytes[] calldata _calldata
    ) external virtual onlyAdminOrEntrypoint whenNotPaused {
        _registerOnFactory();

        require(_target.length == _calldata.length && _target.length == _value.length, "Account: wrong array lengths.");
        for (uint256 i = 0; i < _target.length; i++) {
            _call(_target[i], _value[i], _calldata[i]);
        }
    }

    function setPaused(bool pauseStatus) external onlyAccountLock(msg.sender) {
        paused = pauseStatus;
        AccountLock(accountLock).addLockAccountToList(address(this));
    }

    /// @notice Updates the account admin (post recovery concensus)
    function updateAdmin(address newAdmin) external onlyAccountRecovery(msg.sender) {
        // retrieving `recoveryEmailData` from `AccountCore::recoveryEmailData` passed during initialization of smart account contract
        _setAdmin(newAdmin, true, recoveryEmailData);

        emit AdminUpdated(newAdmin);
    }

    ////// getter functions ////////
    function getAccountAdmin() public view returns (address[] memory) {
        address[] memory admins = getAllAdmins();
        return admins;
    }

    fallback() external {
        console.log("Reached Fallback() of Account.sol");
    }

    /*///////////////////////////////////////////////////////////////
                        Internal functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Registers the account on the factory if it hasn't been registered yet.
    function _registerOnFactory() internal virtual {
        GuardianAccountFactory factoryContract = GuardianAccountFactory(factory);
        if (!factoryContract.isRegistered(address(this))) {
            factoryContract.onRegister(address(this), "");
        }
    }

    /// @dev Calls a target contract and reverts if it fails.
    function _call(
        address _target,
        uint256 value,
        bytes memory _calldata
    ) internal virtual returns (bytes memory result) {
        bool success;
        (success, result) = _target.call{ value: value }(_calldata);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /// @dev Returns whether contract metadata can be set in the given execution context.
    function _canSetContractURI() internal view virtual override returns (bool) {
        return isAdmin(msg.sender) || msg.sender == address(this);
    }

    /// @notice Initializes the smart contract wallet.
    function initialize(
        address _defaultAdmin,
        address _guardian,
        address _accountLock,
        bytes calldata _data
    ) public initializer {
        // This is passed as data in the `_registerOnFactory()` call in `AccountExtension` / `Account`.
        // AccountCoreStorage.data().firstAdmin = _defaultAdmin;
        _setAdmin(_defaultAdmin, true, _data);
        commonGuardian = _guardian;
        accountLock = _accountLock;
        recoveryEmailData = _data;
    }

    /// @notice Makes the given account an admin.
    function _setAdmin(address _account, bool _isAdmin, bytes memory _data) internal {
        AccountPermissions._setAdmin(_account, _isAdmin);

        if (factory.code.length > 0) {
            if (_isAdmin) {
                GuardianAccountFactory(factory).onSignerAdded(_account, _account, _data);
            } else {
                GuardianAccountFactory(factory).onSignerRemoved(_account, _account, _data);
            }
        }
    }
}
