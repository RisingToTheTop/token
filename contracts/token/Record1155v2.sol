// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*
__        ___    ____ __  __ ___ __  __ _   _ ____ ___ ____ 
\ \      / / \  / ___|  \/  |_ _|  \/  | | | / ___|_ _/ ___|
 \ \ /\ / / _ \| |  _| |\/| || || |\/| | | | \___ \| | |    
  \ V  V / ___ \ |_| | |  | || || |  | | |_| |___) | | |___ 
   \_/\_/_/   \_\____|_|  |_|___|_|  |_|\___/|____/___\____|
*/

import {WAGMIApp} from "../wagmi/WagmiApp.sol";
import {IRecord1155} from "./IRecord1155.sol";
import {MusicLib} from "../lib/MusicLib.sol";
import {IERC2981Upgradeable, IERC165Upgradeable}
from '@openzeppelin/contracts-upgradeable/interfaces/IERC2981Upgradeable.sol';
import {ERC1155Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol';
import {StringsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import {CountersUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol';
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title Record1155v2
 * @author WAGMIMusic
 */
contract Record1155v2 is IRecord1155, WAGMIApp, ERC1155Upgradeable, IERC2981Upgradeable {
  using StringsUpgradeable for uint256;
  using CountersUpgradeable for CountersUpgradeable.Counter;

  // 販売状態(列挙型)
  enum SaleState {Prepared, Presale, PublicSale, Suspended} 

  // ベースURI(tokenURI=baseURI+editionId+/+tokenId)
  string internal baseURI;
  // トークンの名称
  string private _name;
  // トークンの単位
  string private _symbol;

  // 楽曲id => 販売状態
  mapping(uint256 => SaleState) public sales;
  // アルバムid => アルバムサイズ
  mapping(uint256 => uint32) private _albumSize;
  // 楽曲id, アドレス => mint数
  mapping(uint256=>mapping(address => uint32)) private _tokenClaimed;

  event NowOnSale(
    uint256 indexed tokenId,
    SaleState indexed sales
  );

  /**
    @dev コンストラクタ(Proxyを利用したコントラクトはinitializeでconstructorを代用)
    @param _artist コントラクトのオーナーアドレス
    @param name_ コントラクトの名称
    @param symbol_ トークンの単位
    @param _baseURI ベースURI
   */
  function initialize(
        address _artist,
        string memory name_,
        string memory symbol_,
        string memory _baseURI
  ) public override initializer {
      __ERC1155_init(_baseURI);
      __Ownable_init();

      // コントラクトのデプロイアドレスに関わらずownerをartistに設定する
      transferOwnership(_artist);

      // /**
      // * Network: Ethereum
      // * Aggregator: JPY/USD
      // */
      // _numeratorAddr = 0xBcE206caE7f0ec07b545EddE332A47C2F75bbeb3;
      // /**
      // * Network: Ethereum
      // * Aggregator: ETH/USD
      // */
      // _denominatorAddr = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
      /**
      * Network: Polygon
      * Aggregator: JPY/USD
      */
      _numeratorAddr = 0xD647a6fC9BC6402301583C91decC5989d8Bc382D;
      /**
      * Network: Polygon
      * Aggregator: ETH/USD
      */
      _denominatorAddr = 0xF9680D99D6C9589e2a93a78A04A279e509205945;

      baseURI = _baseURI;
      _name = name_;
      _symbol = symbol_;

      // deployerをエージェントに設定
      _agent[_msgSender()] = true;

      // 楽曲idとアルバムidの初期値は1
      newTokenId.increment();
      newAlbumId.increment();// albumId=0 => universal album
  }

  // ============ Main Function ============
  /**
    @dev 楽曲データの作成(既存のアルバムに追加)
    @param music MusicData(Struct)
   */
  function createMusic(
    MusicLib.Music calldata music
  ) public virtual override onlyOwnerOrAgent {
    // データの有効性を確認
    MusicLib.validateShare(music.stakeHolders, music.share);
    // _albumIdの有効性を確認
    require(_existsAlbum(music.album), 'not exist');
    musics[newTokenId.current()] =
    MusicLib.Music({
      stakeHolders: music.stakeHolders,
      aggregator: music.aggregator,
      prices: music.prices,
      recoupLine: music.recoupLine,
      share: music.share,
      purchaseLimits: music.purchaseLimits,
      numSold: 0,
      quantity: music.quantity,
      presaleQuantity: music.presaleQuantity,
      royalty: music.royalty,
      album: uint32(music.album),
      merkleRoot: music.merkleRoot
    });

    emit MusicCreated(
      newTokenId.current(),
      music.stakeHolders,
      music.aggregator,
      music.prices,
      music.share,
      music.quantity,
      music.presaleQuantity,
      music.royalty,
      uint32(music.album),
      music.merkleRoot
    );

    // sales: default => prepared
    sales[newTokenId.current()] = SaleState.Prepared;
    // increment TokenId and AlbumId
    newTokenId.increment();
    ++_albumSize[music.album];
  }

  /**
    @dev アルバムデータの作成
    @param album AlbumData(Struct)
   */
  function createAlbum(
    MusicLib.Album calldata album
  ) external virtual override onlyOwnerOrAgent {
    // データの有効性を確認
    MusicLib.validateAlbum(album);
    for(uint256 i=0; i<album._quantities.length; ++i){
      musics[newTokenId.current()] =
      MusicLib.Music({
        stakeHolders: album._stakeHolders,
        aggregator: album._aggregator,
        prices: [album._presalePrices[i], album._prices[i]],
        recoupLine: album._recoupLines[i],
        share: album._share,
        numSold: 0,
        quantity: album._quantities[i],
        presaleQuantity: album._presaleQuantities[i],
        royalty: album._royalty,
        album: uint32(newAlbumId.current()),
        purchaseLimits: [album._presalePurchaseLimits[i],album._purchaseLimits[i]],
        merkleRoot: album._merkleRoot
      });

      emit MusicCreated(
        newTokenId.current(),
        album._stakeHolders,
        album._aggregator,
        [album._presalePrices[i], album._prices[i]],
        album._share,
        album._quantities[i],
        album._presaleQuantities[i],
        album._royalty,
        uint32(newAlbumId.current()),
        album._merkleRoot
      );
      // sales: default => suspended
      sales[newTokenId.current()] = SaleState.Prepared;
      // increment TokenId and AlbumId
      newTokenId.increment();
      ++_albumSize[newAlbumId.current()];
    }
    newAlbumId.increment();
  }

  function omniMint(
    uint256 _tokenId,
    uint32 _amount
  ) external virtual override payable {
    bytes32[] memory empty;
    omniMint(_tokenId, _amount, "", empty);
  }

  /**
    @dev NFTの購入
    @param _tokenId 購入する楽曲のid
    @param _merkleProof マークルプルーフ
   */
  function omniMint(
    uint256 _tokenId,
    uint32 _amount,
    bytes memory _data,
    bytes32[] memory _merkleProof
  ) public virtual override payable {
    // _tokenIdの有効性を確認
    require(_exists(_tokenId), 'not exist');
    // 在庫の確認
    require(musics[_tokenId].numSold + _amount <= musics[_tokenId].quantity, 'exceed stock');

    // 販売状態による分岐
    if (sales[_tokenId] == SaleState.Presale) {
      // 購入制限数の確認
      require(_tokenClaimed[_tokenId][_msgSender()] + _amount <=  musics[_tokenId].purchaseLimits[0], "exceeds limit");
      _validateWhitelist(_tokenId, _merkleProof);
      // プレセール時の支払価格の確認
      require(msg.value >= musics[_tokenId].prices[0] * _amount,'not enough');
    }else if(sales[_tokenId] == SaleState.PublicSale){
      // 購入制限数の確認
      require(_tokenClaimed[_tokenId][_msgSender()] + _amount <=  musics[_tokenId].purchaseLimits[1], "exceeds limit");
      // パブリックセール時の支払価格の確認
      require(msg.value >= musics[_tokenId].prices[1] * _amount,'not enough');
    }else{
      // SaleState: prepared or suspended
      revert("not on sale");
    }
    // Reentrancy guard
    // 発行量+_amount
    musics[_tokenId].numSold += _amount;
    // 購入履歴+_amount
    _tokenClaimed[_tokenId][_msgSender()] += _amount;
    // デポジットを更新
    profit[_tokenId] += msg.value;
    _mint(_msgSender(), _tokenId, _amount, _data);

    uint32 _albumId = musics[_tokenId].album;
    emit MusicPurchased(
      _tokenId, 
      _albumId,
      musics[_tokenId].numSold, 
      _msgSender()
    );
  }

  /**
    @dev 販売状態の移行(列挙型で管理)
    @param _tokenIds 楽曲のid列
    @param _sale 販売状態(0=>prepared, 1=>presale, 2=>public sale, 3=>suspended)
   */
  function handleSaleState (
    uint256[] calldata _tokenIds,
    uint8 _sale
  ) external virtual override onlyOwnerOrAgent {
    for(uint256 i=0; i<_tokenIds.length; ++i){
      sales[_tokenIds[i]] = SaleState(_sale);
      emit NowOnSale(_tokenIds[i], sales[_tokenIds[i]]);
    }
  }

  /**
    @dev マークルルートの設定
    @param _tokenIds 楽曲id
    @param _merkleRoot マークルルート
   */
  function setMerkleRoot(
    uint256[] calldata _tokenIds,
    bytes32 _merkleRoot
  ) public virtual override onlyOwnerOrAgent {
    for(uint256 i=0; i<_tokenIds.length; ++i){
      musics[_tokenIds[i]].merkleRoot = _merkleRoot;
    }
  }

  // ============ utility ============

  /**
    @dev newTokenId is totalSupply+1
    @return totalSupply 各トークンの発行量
   */
  function totalSupply(uint256 _tokenId) external virtual override view returns (uint256) {
    require(_exists(_tokenId), 'not exist');
    return musics[_tokenId].numSold;
  }

  /**
    @dev 特定のアルバムのtokenId列を取得
    @param _albumId アルバムid
    @return _tokenIdsOfMusic tokenId
   */
  function getTokenIdsOfAlbum(
      uint256 _albumId
  ) public virtual override view returns (uint256[] memory){
      // _albumIdの有効性を確認
      require(_existsAlbum(_albumId), 'not exist');
      uint256[] memory _tokenIdsOfAlbum = new uint256[](_albumSize[_albumId]);
      uint256 index = 0;
      for (uint256 id = 1; id < newTokenId.current(); ++id){
        if (musics[id].album == _albumId) {
          _tokenIdsOfAlbum[index] = id;
          ++index;
        }
      }
      return _tokenIdsOfAlbum;
  }

  // ============ Operational Function ============

  /**
    @dev NFTのMintオペレーション
    @notice WIP-1: this function should be able to invalidated for the future
   */
  function operationalMint (
    address _recipient,
    uint256 _tokenId,
    uint32 _amount,
    bytes memory _data
  )external virtual override onlyOwnerOrAgent {
    bytes32 digest = keccak256(abi.encode('oparationalMint(uint256 _tokenId,uint32 _amount)', _tokenId, _amount));
    _validateOparation(digest);
    // _tokenIdの有効性を確認
    require(_exists(_tokenId), 'not exist');
    _mint(_recipient, _tokenId, _amount, _data);
  }

  // ============ Token Standard ============

  /**
    @dev コントラクトの名称表示インターフェース
   */
  function name() public view virtual override returns(string memory){
      return(_name);
  }

  /**
    @dev トークンの単位表示インターフェース
   */
  function symbol() public view virtual override returns(string memory){
      return(_symbol);
  }

  /**
    @dev Returns e.g. https://.../{tokenId}
    @param _tokenId トークンID
    @return _tokenURI
   */
  function uri(uint256 _tokenId) public virtual view override returns (string memory) {
    require(_exists(_tokenId), 'not exist');
    return string(abi.encodePacked(baseURI,_tokenId.toString()));
  }

  /**
    @dev ベースURIの設定
   */
  function setBaseURI(
    string memory _uri
  ) external virtual override onlyOwnerOrAgent {
    baseURI = _uri;
  }

  /**
    @dev トークンのロイヤリティを取得(https://eips.ethereum.org/EIPS/eip-2981)
    @param _tokenId トークンid
    @param _salePrice トークンの二次流通価格
    @return _recipient ロイヤリティの受領者
    @return _royaltyAmount ロイヤリティの価格
   */
  function royaltyInfo(
    uint256 _tokenId,
    uint256 _salePrice
  ) external virtual view override 
  returns(
    address _recipient, uint256 _royaltyAmount
  ){
    MusicLib.Music memory music = musics[_tokenId];
    // 100_00 = 100%
    _royaltyAmount = (_salePrice * music.royalty) / 100_00;
    return(music.stakeHolders[0], _royaltyAmount);
  }

  function supportsInterface(
    bytes4 _interfaceId
  )public virtual view override(ERC1155Upgradeable, IERC165Upgradeable)returns (bool)
  {
    return
      type(IERC2981Upgradeable).interfaceId == _interfaceId || ERC1155Upgradeable.supportsInterface(_interfaceId);
  }
}