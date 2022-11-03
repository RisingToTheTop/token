// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IEscrow} from '../interfaces/IEscrow.sol';
import {IERC721Receiver} from '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import {ERC1155Receiver} from '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol';
import {IERC721Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol';
import {IERC1155Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol';
import {Record721} from  '../token/Record721.sol';
import {Record1155v2} from  '../token/Record1155v2.sol';

/**
__        ___    ____ __  __ ___ __  __ _   _ ____ ___ ____ 
\ \      / / \  / ___|  \/  |_ _|  \/  | | | / ___|_ _/ ___|
 \ \ /\ / / _ \| |  _| |\/| || || |\/| | | | \___ \| | |    
  \ V  V / ___ \ |_| | |  | || || |  | | |_| |___) | | |___ 
   \_/\_/_/   \_\____|_|  |_|___|_|  |_|\___/|____/___\____|

  staking escrow for
  lockup:ERC721 => reward:ERC1155
*/

contract StakingEscrow is IEscrow, IERC721Receiver, Ownable{

  address public erc721_address;
  address public erc1155_address;

  mapping(uint32 => Policy) public policies;
  mapping(address=>mapping(uint32=> Asset)) private _lockup;

  constructor(
    address _erc721_address,
    address _erc1155_address,
    address _artist
  ){
    erc721_address = _erc721_address;
    erc1155_address = _erc1155_address;
    _transferOwnership(_artist);
  }

  function setPolicy(
    uint32 _number, 
    uint256[] calldata _requirements, 
    uint256[] calldata _rewards, 
    uint256 _period
  )external override onlyOwner{
    require(policies[_number].period == 0, "policy of number already exist");
    policies[_number] = Policy({
      requirement: _requirements,
      reward: _rewards, 
      period: _period
    });
  }

  /**
    @notice 事前にロックアップするトークンのコントラクトのisApprovedForAllを実行
    @dev provision: run isApprovedForAll of token contract
    @param _staking_policy ステーキング設定の識別番号
    @param _token_ids トークンid
   */
  function lockup_721(
    uint32 _staking_policy,
    uint256[] calldata _token_ids
  )external override{
    Policy memory _policy = policies[_staking_policy];
    require(_lockup[_msgSender()][_staking_policy].lockup_time == 0, "assets of staking already exist");
    require(_policy.period != 0, "policy of number doesn't exist");

    for(uint256 i=0; i<_policy.requirement.length; ++i){
      require(Record721(erc721_address).tokenToMusic(_token_ids[i])==_policy.requirement[i], "tokenId is incorrect");
      IERC721Upgradeable(erc721_address).safeTransferFrom(_msgSender(), address(this), _token_ids[i], "");
    }

    _lockup[_msgSender()][_staking_policy] = Asset({
      lockup_time: block.timestamp,
      token_ids: _token_ids
    });
  }

  /**
    @notice 事前にロックアップするトークンのコントラクトのisApprovedForAllを実行
    @dev provision: run isApprovedForAll of token contract
    @param _staking_policy ステーキング設定の識別番号
   */
  function cancel(
    uint32 _staking_policy
  )external override{
    Asset memory _assets = _lockup[_msgSender()][_staking_policy];
    require(_assets.lockup_time != 0, "lockup asset doesn't exist");
    require(block.timestamp <= _assets.lockup_time + policies[_staking_policy].period, "lockup period of time reached");

    _assets.lockup_time = 0;

    _returnRequirement(_assets.token_ids);
  }

  function claim(
    uint32 _staking_policy
  )external override{
    Asset memory _assets = _lockup[_msgSender()][_staking_policy];
    Policy memory _policy = policies[_staking_policy];
    require(_assets.lockup_time != 0, "lockup asset doesn't exist");
    require(block.timestamp > _assets.lockup_time + _policy.period, "lockup period of time doesn't reached");

    _assets.lockup_time = 0;

    _returnRequirement(_assets.token_ids);
    _reward(_policy.reward);
  }

  function  _returnRequirement(
    uint256[] memory _token_ids
  )private{
    for(uint256 i=0; i<_token_ids.length; ++i){
      IERC721Upgradeable(erc721_address).safeTransferFrom(address(this), _msgSender(), _token_ids[i], "");
    }
  }

  function _reward(
    uint256[] memory _token_ids
  )private{
    for(uint256 i=0; i<_token_ids.length; ++i){
      Record1155v2(erc1155_address).operationalMint(_msgSender(), _token_ids[i], 1, "");
    }
  }

  function onERC721Received(
    address /* operator */,
    address /* from */,
    uint256 /* tokenId */,
    bytes calldata /* data */
  ) pure external override returns (bytes4){
    return(bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")));
  }
}