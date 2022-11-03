// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*
__        ___    ____ __  __ ___ __  __ _   _ ____ ___ ____ 
\ \      / / \  / ___|  \/  |_ _|  \/  | | | / ___|_ _/ ___|
 \ \ /\ / / _ \| |  _| |\/| || || |\/| | | | \___ \| | |    
  \ V  V / ___ \ |_| | |  | || || |  | | |_| |___) | | |___ 
   \_/\_/_/   \_\____|_|  |_|___|_|  |_|\___/|____/___\____|
*/

import {MusicLib} from "../lib/MusicLib.sol";

interface IRecord1155 {

   event MusicCreated(uint256 indexed tokenId,address[] stakeHolders,address aggregator,uint256[2] prices,uint32[] share,uint32 quantity,uint32 presaleQuantity,uint32 royalty,uint32 album,bytes32 merkleRoot);

   event MusicPurchased(uint256 indexed tokenId,uint32 indexed album,uint32 numSold,address indexed buyer);

   /**
      @dev コンストラクタ(Proxyを利用したコントラクトはinitializeでconstructorを代用)
      @param _artist コントラクトのオーナーアドレス
      @param name_ コントラクトの名称
      @param symbol_ トークンの単位
      @param _baseURI ベースURI
   */
   function initialize(address _artist,string memory name_,string memory symbol_,string memory _baseURI) external;

   /**
      @dev 楽曲データの作成(既存のアルバムに追加)
      @param music MusicData(Struct)
   */
   function createMusic(MusicLib.Music calldata music) external;

   /**
      @dev アルバムデータの作成
      @param album AlbumData(Struct)
   */
   function createAlbum(MusicLib.Album calldata album) external;

   function omniMint(uint256 _tokenId,uint32 _amount) external payable;

   /**
      @dev NFTの購入
      @param _tokenId 購入する楽曲のid
      @param _merkleProof マークルプルーフ
   */
   function omniMint(uint256 _tokenId,uint32 _amount,bytes memory _data,bytes32[] memory _merkleProof) external payable;

   /**
      @dev 販売状態の移行(列挙型で管理)
      @param _tokenIds 楽曲のid列
      @param _sale 販売状態(0 => prepared, 1=>presale, 2=>public sale, 3=>suspended)
   */
   function handleSaleState (uint256[] calldata _tokenIds, uint8 _sale) external;

   /**
      @dev マークルルートの設定
      @param _tokenIds 楽曲id
      @param _merkleRoot マークルルート
   */
   function setMerkleRoot(uint256[] calldata _tokenIds,bytes32 _merkleRoot) external;

   // ============ utility ============

   /**
      @dev newTokenId is totalSupply+1
      @return totalSupply 各トークンの発行量
   */
   function totalSupply(uint256 _tokenId) external view returns (uint256);

   /**
      @dev 特定のアルバムのtokenId列を取得
      @param _albumId アルバムid
      @return _tokenIdsOfMusic tokenId
   */
   function getTokenIdsOfAlbum(uint256 _albumId) external view returns (uint256[] memory);

   // ============ Operational Function ============

   /**
      @dev NFTのMintオペレーション
      @notice WIP-1: this function should be able to invalidated for the future
      */
   function operationalMint (address _recipient,uint256 _tokenId,uint32 _amount,bytes memory _data)external;

   // ============ Token Standard ============

   /**
      @dev コントラクトの名称表示インターフェース
   */
   function name() external view returns(string memory);

   /**
      @dev トークンの単位表示インターフェース
   */
   function symbol() external view returns(string memory);

   /**
      @dev ベースURIの設定
   */
   function setBaseURI(string memory _uri) external;
}