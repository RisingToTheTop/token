// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*
__        ___    ____ __  __ ___ __  __ _   _ ____ ___ ____ 
\ \      / / \  / ___|  \/  |_ _|  \/  | | | / ___|_ _/ ___|
 \ \ /\ / / _ \| |  _| |\/| || || |\/| | | | \___ \| | |    
  \ V  V / ___ \ |_| | |  | || || |  | | |_| |___) | | |___ 
   \_/\_/_/   \_\____|_|  |_|___|_|  |_|\___/|____/___\____|
*/

interface IWAGMIApp {
  event Recoup(uint256 indexed tokenId,address aggregator,uint256 value);

  event Withdraw(address indexed claimant,address recipient,uint256 value,uint256 distribution,uint256 locked);

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
  ) external;

  /**
    @dev 引き出し可能な資産額の確認
    @param _claimant 請求アドレス
    @return distribution 配分された資産総額
    @return locked 未承認の配分額
    @return value 引き出し可能な資産総額
   */
  function withdrawable(
    address _claimant
  ) external view returns(
    uint256 distribution,
    uint256 locked,
    uint256 value
  );

  /**
    @dev 諸費用のリクープ
    @param _tokenId 楽曲id
   */
  function recoup(uint256 _tokenId) external;

  /**
    @dev リクープラインの換算(円 => Wei)
    @param _tokenId 楽曲id
    @return value リクープライン(Wei)
   */
  function calculateRecoupLine(uint256 _tokenId) external view returns(uint256 value);

  /**
    @dev 資産の引き出しオペレーション
    @notice WIP-1: this function should be able to invalidated for the future
   */
  function operationalWithdraw(address payable _recipient, uint256 _claimed) external;

  /**
    @dev エージェントの設定
    @param _agentAddr エージェントのアドレス
    @param _licensed 権限の可否
  */
  function license(address _agentAddr, bool _licensed) external;

  /**
    @dev 分配コントラクトの設定
    @param _distributor 分配コントラクトアドレス
   */
  function setRemoteDistributor(address _distributor) external;

  /**
    @dev データフィードの再構成
    @param numeratorAddr_ 価格換算先のChainlinkアドレス
    @param denominatorAddr_ 価格換算元のChainlinkアドレス
   */
  function reconfigureData(address numeratorAddr_, address denominatorAddr_) external;

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
  ) external view returns (address[] memory, uint32[] memory, address payable, uint256, uint256);
}