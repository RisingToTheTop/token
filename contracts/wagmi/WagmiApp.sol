// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*
__        ___    ____ __  __ ___ __  __ _   _ ____ ___ ____ 
\ \      / / \  / ___|  \/  |_ _|  \/  | | | / ___|_ _/ ___|
 \ \ /\ / / _ \| |  _| |\/| || || |\/| | | | \___ \| | |    
  \ V  V / ___ \ |_| | |  | || || |  | | |_| |___) | | |___ 
   \_/\_/_/   \_\____|_|  |_|___|_|  |_|\___/|____/___\____|
*/
import {IWAGMIApp} from "../interfaces/IWagmiApp.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {MusicLib} from "../lib/MusicLib.sol";
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {CountersUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol';
import {IDistributor} from "../interfaces/IDistributor.sol";
import {MerkleProofUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";

/**
 * @title WAGMIapp
 * @author WAGMIMusic
 */
contract WAGMIApp is OwnableUpgradeable, IWAGMIApp {
  using CountersUpgradeable for CountersUpgradeable.Counter;

  // 価格換算先のChainlinkアドレス(Default:円)
  address internal _numeratorAddr;
  // 価格換算元のChainlinkアドレス(Default:Ether)
  address internal _denominatorAddr;
  // 実行権限のある執行者
  mapping(address => bool) internal _agent;
  // 分配コントラクトアドレス
  address public distributor;
  // 楽曲のID
  CountersUpgradeable.Counter internal newTokenId;
  // アルバムのID
  CountersUpgradeable.Counter internal newAlbumId;
  // 楽曲id => 楽曲データ
  mapping(uint256 => MusicLib.Music) public musics;
  // 楽曲id => 収益
  mapping(uint256 => uint256) public profit;
  mapping(address => uint256) private _withdrawnForEach;
  // 楽曲id => リクープ履歴
  mapping(uint256 => uint256) private _recoupedValue;
  mapping(uint256 => bool) private _recouped;

  /**
    @dev 実行権限の確認
   */
  modifier onlyOwnerOrAgent {
    require(msg.sender == owner() || _agent[msg.sender], "not allowed but owner or agent");
    _;
  }

  modifier onlyOwnerOrDistributor {
    require(msg.sender == owner() || msg.sender == distributor, "not allowed but owner or distributor");
    _;
  }

  // ============ Revenue Pool ============

  /**
    @dev 収益の引き出し
    @param _recipient 受領者
    @param _value 請求額
    @dev param: value 引き出し可能な資産総額
    @dev param: _dist Editionごとの引き出し可能な資産額
   */
  function withdraw(
    address payable _recipient,
    uint256 _value
  ) external virtual override {
    uint256 distribution = 0;
    uint256 locked = 0;
    for(uint256 id=1; id < newTokenId.current(); ++id){
      (bool _approval, uint256 dist) = _getDistribution(id, _msgSender());
      if(!_approval){
        locked += dist;
      }
      distribution += dist;
    }
    uint256 value = distribution - locked - _withdrawnForEach[_msgSender()];
    // by any chance
    if(address(this).balance < value){value = address(this).balance;}
    require(value >= _value, 'exceed withdrawable value');
    _withdrawnForEach[_msgSender()] += _value;
    _sendFunds(_recipient, _value);
    emit Withdraw(msg.sender, _recipient, value, distribution, locked);
  }

  /**
    @dev 引き出し可能な資産額の確認
    @param _claimant 請求アドレス
    @return distribution 配分された資産総額
    @return locked 未承認の配分額
    @return value 引き出し可能な資産総額
   */
  function withdrawable(
    address _claimant
  ) public virtual override view returns(
    uint256 distribution,
    uint256 locked,
    uint256 value
  ){
    distribution = 0;
    locked = 0;
    for(uint256 id=1; id < newTokenId.current(); ++id){
      (bool _approval, uint256 dist) = _getDistribution(id, _claimant);
      if(!_approval){
        locked += dist;
      }
      distribution += dist;
    }
    value = distribution - locked - _withdrawnForEach[_claimant];
    return(distribution, locked, value);
  }

  /**
    @dev 分配資産額の確認
   */
  function _getDistribution(
    uint256 _tokenId,
    address _claimant
  ) internal virtual view returns(bool _approval, uint256 _distribution){
    uint32 _share = 0;
    for(uint32 i=0; i < musics[_tokenId].stakeHolders.length; ++i){
      if(musics[_tokenId].stakeHolders[i]==_claimant){
        _share = musics[_tokenId].share[i];
        break;
      }
    }
    if(distributor == address(0x0)){
      // Defaultの分配契約
      _distribution = uint256(_share) * (profit[_tokenId] - calculateRecoupLine(_tokenId)) / 100;
      _approval = (_recouped[_tokenId] || musics[_tokenId].aggregator == address(0x0));
      return(_approval, _distribution);
    }
    // 分配コントラクトの通信プロトコル
    (_approval, _distribution) = IDistributor(distributor).getDistribution(_claimant, _tokenId, profit[_tokenId], _share);
    return(_approval, _distribution);
  }

  /**
    @dev 諸費用のリクープ
    @param _tokenId 楽曲id
   */
  function recoup(uint256 _tokenId) external virtual override {
    require(musics[_tokenId].aggregator == msg.sender, "caller should be aggregator");
    require(!_recouped[_tokenId], "cost have been recouped");
    uint256 value = calculateRecoupLine(_tokenId);
    if(profit[_tokenId] < value){
      value = profit[_tokenId];
    }
    _recouped[_tokenId] = true;
    _recoupedValue[_tokenId] = value;
    _sendFunds(musics[_tokenId].aggregator, value);
    emit Recoup(_tokenId, musics[_tokenId].aggregator, value);
  }

  /**
    @dev リクープラインの換算(円 => Wei)
    @param _tokenId 楽曲id
    @return value リクープライン(Wei)
   */
  function calculateRecoupLine(uint256 _tokenId) public virtual override view returns(uint256 value){
    // リクープ後
    if(_recouped[_tokenId]){
      return _recoupedValue[_tokenId];
    }
    // default
    if(distributor == address(0x0)){
      uint256 converter = _getEtherPerJPY();
      value = musics[_tokenId].recoupLine * converter;
      if(profit[_tokenId] < value){
        value = profit[_tokenId];
      }
      return value;
    }
    // custom: 分配コントラクトの通信プロトコル
    value = IDistributor(distributor).getRecoupLine(_tokenId);
    return value;
  }

  /**
    @dev 送金機能(fallback関数を呼び出すcallを使用)
   */
  function _sendFunds(
    address payable _recipient,
    uint256 _amount
  ) internal virtual {
    require(address(this).balance >= _amount, 'Insufficient balance');
    (bool success, ) = _recipient.call{value: _amount}('');
    require(success, 'recipient reverted');
  }

  // ============ Operational Function ============

  /**
    @dev 資産の引き出しオペレーション
    @notice WIP-1: this function should be able to invalidated for the future
   */
  function operationalWithdraw(address payable _recipient, uint256 _claimed) external virtual override onlyOwnerOrDistributor {
    bytes32 digest = keccak256(abi.encode('operationalWithdraw(address payable _recipient, uint256 _claimed)', _recipient, _claimed));
    _validateOparation(digest);
    _sendFunds(_recipient, _claimed);
  }

  /**
    @dev エージェントの設定
    @param _agentAddr エージェントのアドレス
    @param _licensed 権限の可否
  */
  function license(address _agentAddr, bool _licensed) external virtual override onlyOwnerOrAgent {
    _agent[_agentAddr] = _licensed;
  }

  /**
    @dev 分配コントラクトの設定
    @param _distributor 分配コントラクトアドレス
   */
  function setRemoteDistributor(address _distributor) public virtual override onlyOwnerOrAgent{
    distributor = _distributor;
  }

  /**
    @dev データフィードの再構成
    @param numeratorAddr_ 価格換算先のChainlinkアドレス
    @param denominatorAddr_ 価格換算元のChainlinkアドレス
   */
  function reconfigureData(address numeratorAddr_, address denominatorAddr_) external virtual override onlyOwnerOrAgent{
    _numeratorAddr = numeratorAddr_;
    _denominatorAddr = denominatorAddr_;
  }

  // ============ utility ============

  /**
    @dev 収益の分配データを取得
    @param _tokenId 楽曲id
    @return stakeHolders ステークホルダー
    @return share 収益分配率
    @return aggregator アグリゲーター
    @return recoupline1 リクープライン(円)
    @return recoupline2 リクープライン(実効価格)
   */
  function getShare(
    uint256 _tokenId
  ) external virtual override view returns (address[] memory, uint32[] memory, address payable, uint256, uint256){
    MusicLib.Music memory music = musics[_tokenId];
    return(music.stakeHolders, music.share, music.aggregator, music.recoupLine, calculateRecoupLine(_tokenId));
  }

  // ============ helper function ============
  function _exists(
    uint256 _tokenId
  ) internal virtual view returns(bool){
    if(_tokenId!=0){
      return musics[_tokenId].quantity != 0;
    }
    return true;
  }

  function _existsAlbum(uint256 _albumId) internal virtual view returns(bool){
    return _albumId < newAlbumId.current();
  }

  function _validateOparation(bytes32 digest) internal virtual {}

  /**
    @dev whitelistの認証(マークルツリーを利用)
    @param _tokenId 購入する楽曲のid
    @param _merkleProof マークルプルーフ
   */
  function _validateWhitelist(
    uint256 _tokenId,
    bytes32[] memory _merkleProof
  ) internal virtual {
    bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
    require(
      MerkleProofUpgradeable.verify(_merkleProof, musics[_tokenId].merkleRoot, leaf),
      "Invalid Merkle Proof"
    );
  }

  /**
    @dev 通貨価格の換算(円 => Wei)
    @return converter 円 => Wei
   */
  function _getEtherPerJPY()internal view returns(uint256){
    return(10**13);
    // Default: JPY(円)
    ( 
    /*uint80 roundID*/, 
    int256 _numerator, 
    /*uint startedAt*/, 
    /*uint timeStamp*/, 
    /*uint80 answeredInRound*/
    ) = AggregatorV3Interface(_numeratorAddr).latestRoundData();
    // 価格データの小数点以下桁数
    uint8 _numeratorDecimals = AggregatorV3Interface(_numeratorAddr).decimals();
    _numerator = MusicLib.scalePrice(_numerator, _numeratorDecimals);

    // Default: Ether
    ( 
    /*uint80 roundID*/, 
    int256 _denominator, 
    /*uint startedAt*/, 
    /*uint timeStamp*/, 
    /*uint80 answeredInRound*/
    ) = AggregatorV3Interface(_denominatorAddr).latestRoundData();
    // 価格データの小数点以下桁数
    uint8 _denominatorDecimals = AggregatorV3Interface(_denominatorAddr).decimals();
    _denominator = MusicLib.scalePrice(_denominator, _denominatorDecimals);

    // converter: 円 => Wei
    return uint256(_numerator) * 1 ether / uint256(_denominator);
  }
}

