//! The KeyServerSet contract. Owned version with migration support.
//!
//! Copyright 2017 Svyatoslav Nikolsky, Parity Technologies Ltd.
//!
//! Licensed under the Apache License, Version 2.0 (the "License");
//! you may not use this file except in compliance with the License.
//! You may obtain a copy of the License at
//!
//!     http://www.apache.org/licenses/LICENSE-2.0
//!
//! Unless required by applicable law or agreed to in writing, software
//! distributed under the License is distributed on an "AS IS" BASIS,
//! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//! See the License for the specific language governing permissions and
//! limitations under the License.

pragma solidity >0.4.99 <0.6.0;

import "./Owned.sol";
import "./KeyServerSet.sol";


// Single-owned KeyServerSet with migration support.
contract OwnedKeyServerSetWithMigration is Owned, KeyServerSetWithMigration {
	struct KeyServer {
		// Index in the keyServersList.
		uint8 index;
		// Public key of key server.
		bytes publicKey;
		// IP address of key server.
		string ip;
	}

	struct Set {
		// Public keys of all active key servers.
		address[] list;
		// Mapping public key => server IP address.
		mapping(address => KeyServer) map;
	}

	// When new server is added to new set.
	event KeyServerAdded(address keyServer);
	// When existing server is removed from new set.
	event KeyServerRemoved(address keyServer);
	// When migration is started.
	event MigrationStarted();
	// When migration is completed.
	event MigrationCompleted();

	// Is initialized.
	bool isInitialized;
	// Block at which current
	uint256 currentSetChangeBlock;
	// Current key servers set.
	Set currentSet;
	// Migration key servers set.
	Set migrationSet;
	// New key servers set.
	Set newSet;
	// Migration master.
	address migrationMaster;
	// Migration id.
	bytes32 migrationId;
	// Required migration confirmations.
	mapping(address => bool) migrationConfirmations;

	// Only if valid public is passed
	modifier isValidPublic(bytes memory keyServerPublic) {
		require(checkPublic(keyServerPublic), "Check public");
		_;
	}

	// Only run if server is currently on current set.
	modifier isOnCurrentSet(address keyServer) {
		require(keccak256(abi.encodePacked(currentSet.map[keyServer].ip)) != keccak256(""), "Not current set");
		_;
	}

	// Only run if server is currently on migration set.
	modifier isOnMigrationSet(address keyServer) {
		require(keccak256(abi.encodePacked(migrationSet.map[keyServer].ip)) != keccak256(""), "Not migration set");
		_;
	}

	// Only run if server is currently on new set.
	modifier isOnNewSet(address keyServer) {
		require(keccak256(abi.encodePacked(newSet.map[keyServer].ip)) != keccak256(""), "Not new set");
		_;
	}

	// Only run if server is currently on new set.
	modifier isNotOnNewSet(address keyServer) {
		require(keccak256(abi.encodePacked(newSet.map[keyServer].ip)) == keccak256(""), "New set");
		_;
	}

	// Only when no active migration process.
	modifier noActiveMigration {
		require(migrationMaster == address(0), "Should no active migration");
		_;
	}

	// Only when migration with given id is in progress.
	modifier isActiveMigration(bytes32 id) {
		require(migrationId == id, "Should active migrations");
		_;
	}

	// Only when migration id is valid.
	modifier isValidMigrationId(bytes32 id) {
		require(id != bytes32(0), "Should valid migration");
		_;
	}

	// Only when migration is required.
	modifier whenMigrationRequired {
		require(!areEqualSets(currentSet, newSet), "Require migration");
		_;
	}

	// Only run when sender is potential participant of migration.
	modifier isPossibleMigrationParticipant {
		require(
			keccak256(abi.encodePacked(currentSet.map[msg.sender].ip)) != keccak256("") ||
			keccak256(abi.encodePacked(newSet.map[msg.sender].ip)) != keccak256(""), "Only potential participant");
		_;
	}

	// Only run when sender is participant of migration.
	modifier isMigrationParticipant(address keyServer) {
		require(
			keccak256(abi.encodePacked(currentSet.map[keyServer].ip)) != keccak256("") ||
			keccak256(abi.encodePacked(migrationSet.map[keyServer].ip)) != keccak256(""), "Only participant");
		_;
	}

	/// We do not support direct payments.
	function() external payable { revert("Direct payment not supported"); }

	/// Get number of block when current set has been changed last time.
	function getCurrentLastChange() external view returns (uint256) {
		return currentSetChangeBlock;
	}

	/// Get index of given key server in current set.
	function getCurrentKeyServerIndex(address keyServer) external view returns (uint8) {
		KeyServer storage entry = currentSet.map[keyServer];
		require(keccak256(abi.encodePacked(entry.ip)) != keccak256(""), "Not equal key server index");
		return entry.index;
	}

	/// Get count of key servers in current set.
	function getCurrentKeyServersCount() external view returns (uint8) {
		return uint8(currentSet.list.length);
	}

	/// Get address of key server in current set.
	function getCurrentKeyServer(uint8 index) external view returns (address) {
		require(index < currentSet.list.length, "Key length not equal");
		return currentSet.list[index];
	}

	// Get all current key servers.
	function getCurrentKeyServers() external view returns (address[] memory) {
		return currentSet.list;
	}

	// Get current key server public key.
	function getCurrentKeyServerPublic(address keyServer) external isOnCurrentSet(keyServer) view returns (bytes memory) {
		return currentSet.map[keyServer].publicKey;
	}

	// Get current key server address.
	function getCurrentKeyServerAddress(address keyServer) external isOnCurrentSet(keyServer) view returns (string memory) {
		return currentSet.map[keyServer].ip;
	}

	// Get all migration key servers.
	function getMigrationKeyServers() external view returns (address[] memory) {
		return migrationSet.list;
	}

	// Get migration key server public key.
	function getMigrationKeyServerPublic(address keyServer) external isOnMigrationSet(keyServer) view returns (bytes memory) {
		return migrationSet.map[keyServer].publicKey;
	}

	// Get migration key server address.
	function getMigrationKeyServerAddress(address keyServer) external isOnMigrationSet(keyServer) view returns (string memory) {
		return migrationSet.map[keyServer].ip;
	}

	// Get all new key servers.
	function getNewKeyServers() external view returns (address[] memory) {
		return newSet.list;
	}

	// Get new key server public key.
	function getNewKeyServerPublic(address keyServer) external isOnNewSet(keyServer) view returns (bytes memory) {
		return newSet.map[keyServer].publicKey;
	}

	// Get new key server address.
	function getNewKeyServerAddress(address keyServer) external isOnNewSet(keyServer) view returns (string memory) {
		return newSet.map[keyServer].ip;
	}

	// Get migration id.
	function getMigrationId() external isValidMigrationId(migrationId) view returns (bytes32) {
		return migrationId;
	}

	// Start migration.
	function startMigration(bytes32 id) external noActiveMigration isValidMigrationId(id) whenMigrationRequired isPossibleMigrationParticipant {
		// migration to empty set is impossible
		require (newSet.list.length != 0, "Should not empty");

		migrationMaster = msg.sender;
		migrationId = id;
		copySet(migrationSet, newSet);
		emit MigrationStarted();
	}

	// Confirm migration.
	function confirmMigration(bytes32 id) external isValidMigrationId(id) isActiveMigration(id) isOnMigrationSet(msg.sender) {
		require(!migrationConfirmations[msg.sender], "Should not confirmed");
		migrationConfirmations[msg.sender] = true;

		// check if migration is completed
		for (uint j = 0; j < migrationSet.list.length; ++j) {
			if (!migrationConfirmations[migrationSet.list[j]]) {
				return;
			}
		}

		// migration is completed => delete confirmations
		for (uint m = 0; m < migrationSet.list.length; ++m) {
			delete migrationConfirmations[migrationSet.list[m]];
		}
		delete migrationMaster;

		// ...and copy migration set to current set
		copySet(currentSet, migrationSet);

		// ...and also delete entries from migration set
		clearSet(migrationSet);

		// ...and fire completion event
		emit MigrationCompleted();

		// ...and update current server set change block
		currentSetChangeBlock = block.number;
	}

	// Get migration master.
	function getMigrationMaster() external view returns (address) {
		return migrationMaster;
	}

	// Is migration confirmed.
	function isMigrationConfirmed(address keyServer) external view isMigrationParticipant(keyServer) returns (bool) {
		return migrationConfirmations[keyServer];
	}

	// Complete initialization. Before this function is called, all calls to addKeyServer/removeKeyServer
	// affect both newSet and currentSet.
	function completeInitialization() public onlyOwner {
		require(!isInitialized, "Should not initialized yet");
		isInitialized = true;
	}

	// Add new key server to set.
	function addKeyServer(bytes memory keyServerPublic, string memory keyServerIp)
		public
		onlyOwner
		isValidPublic(keyServerPublic)
		isNotOnNewSet(computeAddress(keyServerPublic))
	{
		// append to the new set
		address keyServer = appendToSet(newSet, keyServerPublic, keyServerIp);
		// also append to current set
		if (!isInitialized) {
			appendToSet(currentSet, keyServerPublic, keyServerIp);
		}
		// fire event
		emit KeyServerAdded(keyServer);
	}

	// Remove key server from set.
	function removeKeyServer(address keyServer) public onlyOwner isOnNewSet(keyServer) {
		// remove element from the new set
		removeFromSet(newSet, keyServer);
		// also remove from the current set
		if (!isInitialized) {
			removeFromSet(currentSet, keyServer);
		}
		// fire event
		emit KeyServerRemoved(keyServer);
	}

	// Compute address from public key.
	function computeAddress(bytes memory keyServerPublic) private pure returns (address) {
		return address(uint(keccak256(keyServerPublic)) & 0x00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
	}

	// 'Check' public key.
	function checkPublic(bytes memory keyServerPublic) private pure returns (bool) {
		return keyServerPublic.length == 64;
	}

	// Copy set (assignment operator).
	function copySet(Set storage set1, Set storage set2) private {
		for (uint i = 0; i < set1.list.length; ++i) {
			delete set1.map[set1.list[i]];
		}

		set1.list = set2.list;
		for (uint j = 0; j < set1.list.length; ++j) {
			set1.map[set1.list[j]] = set2.map[set1.list[j]];
		}
	}

	// Clear set.
	function clearSet(Set storage set) private {
		while (set.list.length > 0) {
			address keyServer = set.list[set.list.length - 1];
			delete set.list[set.list.length - 1];
			set.list.length = set.list.length - 1;
			delete set.map[keyServer];
		}
	}

	// Are two sets equal?
	function areEqualSets(Set storage set1, Set storage set2) private view returns (bool) {
		for (uint i = 0; i < set1.list.length; ++i) {
			if (keccak256(abi.encodePacked(set2.map[set1.list[i]].ip)) == keccak256("")) {
				return false;
			}
		}
		for (uint j = 0; j < set2.list.length; ++j) {
			if (keccak256(abi.encodePacked(set1.map[set2.list[j]].ip)) == keccak256("")) {
				return false;
			}
		}
		return true;
	}

	// Append new key serer to set.
	function appendToSet(Set storage set, bytes memory keyServerPublic, string memory keyServerIp) private returns (address) {
		// we do not support > 256 key servers in the list
		require(set.list.length < 256, "Should less than 256");

		address keyServer = computeAddress(keyServerPublic);
		set.map[keyServer].index = uint8(set.list.length);
		set.map[keyServer].publicKey = keyServerPublic;
		set.map[keyServer].ip = keyServerIp;
		set.list.push(keyServer);
		return keyServer;
	}

	// Remove existing key server set.
	function removeFromSet(Set storage set, address keyServer) private {
		// swap list elements (removedIndex, lastIndex)
		uint8 removedIndex = uint8(set.map[keyServer].index);
		uint8 lastIndex = uint8(set.list.length) - 1;
		address lastKeyServer = set.list[lastIndex];
		set.list[removedIndex] = lastKeyServer;
		set.map[lastKeyServer].index = removedIndex;
		// remove element from list and map
		delete set.list[lastIndex];
		delete set.map[keyServer];
		set.list.length--;
	}
}
