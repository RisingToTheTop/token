// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Token1155} from  '../legacy/Token1155.sol';
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

contract Vault is Ownable {

  struct CostProposal {
    address agent;
    uint256[] tokenIds;
    uint256[] costs;
  }

  uint8 constant DECIMALS = 10;
  // WAGMIMusicのコントラクト
  address public wagmiContract;
  Token1155 wagmiToken;
  // 価格換算先のChainlinkアドレス(Default:円)
  address private _numeratorAddr;
  // 価格換算元のChainlinkアドレス(Default:Ether)
  address private _denominatorAddr;
  // 楽曲ごとのリクープライン(円)
  mapping(uint256 => uint256) public tokenToCost;
  mapping(uint256 => bool) public isRecouped;
  mapping(uint256 => bool) public isApproved;

  constructor(
    address _contract, 
    address _artist,
    address _chainlinkJPY,
    address _chainlinkETH
  ){
    wagmiContract = _contract;
    wagmiToken = Token1155(wagmiContract);
    transferOwnership(_artist);
    /**
    * Network: Ethereum
    * Aggregator: JPY/USD
    * Address: 0xbce206cae7f0ec07b545edde332a47c2f75bbeb3
    */
    _numeratorAddr = _chainlinkJPY;
    /**
    * Network: Ethereum
    * Aggregator: ETH/USD
    * Address: 0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419
    */
    _denominatorAddr = _chainlinkETH;
  }

  /**
    @dev 報酬額の計算
    @param _claimant 請求アドレス
    @param _tokenId 楽曲id
    @param _deposit デポジット
    @param _share 収益配分率
    @return _approval 収益配分の承認
    @return _distribution 報酬額
   */
  function getDistribution(
    address _claimant, 
    uint256 _tokenId, 
    uint256 _deposit, 
    uint32 _share
  )external view returns(bool _approval, uint256 _distribution){
    _distribution = uint256(_share) * (_deposit - calculateRecoupLine(_tokenId)) / 100;
    return(isRecouped[_tokenId], _distribution);
  }

  /**
    @dev 諸費用のリクープ
    @param _recipient 受領アドレス
    @param _tokenId 楽曲id
   */
  function recoup(address payable _recipient, uint256 _tokenId) external {
    require(isApproved[_tokenId], "Recoup is not approved");
    require(!isRecouped[_tokenId], "Cost have been recouped");
    isRecouped[_tokenId] = true;
    uint256 _value = calculateRecoupLine(_tokenId);
    // ToDo: optimize operationalWithdraw function
    wagmiToken.operationalWithdraw(_recipient, _value);
  }

  /**
    @dev リクープラインの換算(円 => Wei)
    @param _tokenId 楽曲id
    @return リクープライン(Wei)
   */
  function calculateRecoupLine(uint256 _tokenId) public view returns(uint256){
    uint256 converter = _getEtherPerJPY();
    return tokenToCost[_tokenId] * converter;
  }

  /**
    @dev 通貨価格の換算(円 => Wei)
    @return converter 円 => Wei
   */
  function _getEtherPerJPY()private view returns(uint256){
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
    _numerator = _scalePrice(_numerator, _numeratorDecimals);

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
    _denominator = _scalePrice(_denominator, _denominatorDecimals);

    // converter: 円 => Wei
    return uint256(_numerator) * 1 ether / uint256(_denominator);
  }

  /**
    @dev 有効小数点以下桁数の調整
    @param _price 価格データ
    @param _priceDecimals 価格データの小数点以下桁数
    @return 調整後価格データ
   */
  function _scalePrice(
    int256 _price, 
    uint8 _priceDecimals
  ) private pure returns (int256){
    if (_priceDecimals < DECIMALS) {
      return _price * int256(10 ** uint256(DECIMALS - _priceDecimals));
    } else if (_priceDecimals > DECIMALS) {
      return _price / int256(10 ** uint256(_priceDecimals - DECIMALS));
    }
    return _price;
  }

  /**
    @dev コントラクトの再構成
    @param _wagmiContract WAGMIMusicのコントラクトアドレス
   */
  function reconfigureContract(address _wagmiContract) external onlyOwner {
    wagmiContract = _wagmiContract;
    wagmiToken = Token1155(wagmiContract);
  }

  /**
    @dev データフィードの再構成
    @param numeratorAddr_ 価格換算先のChainlinkアドレス
    @param denominatorAddr_ 価格換算元のChainlinkアドレス
   */
  function reconfigureData(address numeratorAddr_, address denominatorAddr_) external onlyOwner {
    _numeratorAddr = numeratorAddr_;
    _denominatorAddr = denominatorAddr_;
  }
}