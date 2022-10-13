// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Token1155} from  '../legacy/Token1155.sol';
import {ERC1155Receiver} from '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

/**
__        ___    ____ __  __ ___ __  __ _   _ ____ ___ ____ 
\ \      / / \  / ___|  \/  |_ _|  \/  | | | / ___|_ _/ ___|
 \ \ /\ / / _ \| |  _| |\/| || || |\/| | | | \___ \| | |    
  \ V  V / ___ \ |_| | |  | || || |  | | |_| |___) | | |___ 
   \_/\_/_/   \_\____|_|  |_|___|_|  |_|\___/|____/___\____|

  exchange escrow for
  legacy:ERC1155 => new:ERC1155
*/

contract ExchangeEscrow is ERC1155Receiver, Ownable{

  // 旧規格コントラクトアドレス
  address public legacyContract;
  // 新規格コントラクトアドレス
  address public newContract;
  // 規格移行データ(旧規格トークンid=>新規格トークンid)
  mapping(uint256=>uint256) public migrate;

  /**
    @dev コンストラクタ
    @param _legacy 旧規格コントラクトアドレス
    @param _new 新規格コントラクトアドレス
   */
  constructor(address _legacy, address _new){
    legacyContract = _legacy;
    newContract = _new;
  }

  /**
    @dev トークンの規格移行
    @param _legacyId 旧規格トークンid
    @param _newId 新規格トークンid
   */
  function setMigration(uint256 _legacyId, uint256 _newId) onlyOwner external {
    migrate[_legacyId] = _newId;
  }

  /**
    @dev 新規格トークンのmint
    @param _tokenId トークンid
    @param _amount トークン発行量
    @param _recipient 受領アドレス
   */
  function _claimNewToken (uint256 _tokenId, uint32 _amount, address _recipient) private {
    Token1155 newToken = Token1155(newContract);
    newToken.oparationalMint(_recipient, _tokenId, _amount, "");
  }

  function _onReceivedCombination(
    address _from,
    uint256 _legacyId,
    uint256 _amount
  ) private {
    uint256 _newId = migrate[_legacyId];
    require(_newId != 0,"exchange of this token is not supported");
    _claimNewToken(_newId, uint32(_amount), _from);
  }

  function onERC1155Received(
      address/* operator */,
      address from,
      uint256 id,
      uint256 value,
      bytes calldata/* data */
  ) external override returns (bytes4){
    require(msg.sender == legacyContract, "msg.sender isn't legacyContract");
    _onReceivedCombination(from, id, value);
    return(bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")));
  }

  function onERC1155BatchReceived(
      address/* operator */,
      address/* from */,
      uint256[] calldata/* id */,
      uint256[] calldata/* value */,
      bytes calldata/* data */
  ) external pure override returns (bytes4){
    revert("ERC1155BatchReceive is not supported");
  }
}