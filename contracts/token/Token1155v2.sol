// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*
__        ___    ____ __  __ ___ __  __ _   _ ____ ___ ____ 
\ \      / / \  / ___|  \/  |_ _|  \/  | | | / ___|_ _/ ___|
 \ \ /\ / / _ \| |  _| |\/| || || |\/| | | | \___ \| | |    
  \ V  V / ___ \ |_| | |  | || || |  | | |_| |___) | | |___ 
   \_/\_/_/   \_\____|_|  |_|___|_|  |_|\___/|____/___\____|
*/

import {IERC2981Upgradeable, IERC165Upgradeable}
from '@openzeppelin/contracts-upgradeable/interfaces/IERC2981Upgradeable.sol';
import {ERC1155Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {CountersUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol';
import {MerkleProofUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";
import {StringsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IDistributor} from "../interfaces/IDistributor.sol";

/**
 * @title Token1155v2
 * @author WAGMIMusic
 */
contract Token1155v2 is ERC1155Upgradeable, IERC2981Upgradeable, OwnableUpgradeable {
  using CountersUpgradeable for CountersUpgradeable.Counter;
  using StringsUpgradeable for uint256;

  struct Music {
    address[] stakeHolders;// 収益の受領者(筆頭受領者=二次流通ロイヤリティの受領者)
    address payable aggregator;// アグリゲーター
    uint256[2] prices;// [preSale価格，publicSale価格]
    uint256 recoupLine; // リクープライン(円)
    uint32[] share;// 収益の分配率
    uint32[2] purchaseLimits; // [preSale購入制限，publicSale購入制限]
    uint32 numSold;// 現在のトークン発行量
    uint32 quantity;// トークン発行上限
    uint32 presaleQuantity;// プレセール配分量
    uint32 royalty;// 二次流通時の印税(using 2 desimals)
    uint32 album;// 収録アルバムid
    bytes32 merkleRoot;// マークルルート
  }

  struct Album {
    address[] _stakeHolders;
    address payable _aggregator;
    uint256[] _presalePrices;
    uint256[] _prices;
    uint256[] _recoupLines;
    uint32[] _presaleQuantities;
    uint32[] _quantities;
    uint32[] _share;
    uint32[] _presalePurchaseLimits;
    uint32[] _purchaseLimits;
    uint32 _royalty;
    bytes32 _merkleRoot;
  }
  // 為替データの有効小数桁数
  uint8 constant DECIMALS = 10;
  // 価格換算先のChainlinkアドレス(Default:円)
  address public _numeratorAddr;
  // 価格換算元のChainlinkアドレス(Default:Ether)
  address public _denominatorAddr;
  // ベースURI(tokenURI=baseURI+editionId+/+tokenId)
  string internal baseURI;
  // トークンの名称
  string private _name;
  // トークンの単位
  string private _symbol;
  // 分配コントラクトアドレス
  address public distributor;
  // 楽曲のID
  CountersUpgradeable.Counter private newTokenId;
  // アルバムのID
  CountersUpgradeable.Counter private newAlbumId;
  // 販売状態(列挙型)
  enum SaleState {Prepared, Presale, PublicSale, Suspended} 

  // 楽曲id => 楽曲データ
  mapping(uint256 => Music) public musics;
  // 楽曲id => 販売状態
  mapping(uint256 => SaleState) public sales;
  // アルバムid => アルバムサイズ
  mapping(uint256 => uint32) private _albumSize;
  // 楽曲id, アドレス => mint数
  mapping(uint256=>mapping(address => uint32)) private _tokenClaimed;
  // 実行権限のある執行者
  mapping(address => bool) private _agent;
  // 楽曲id => 収益
  mapping(uint256 => uint256) public profit;
  mapping(address => uint256) private _withdrawnForEach;
  // 楽曲id => リクープ履歴
  mapping(uint256 => uint256) private _recoupedValue;

  event MusicCreated(
    uint256 indexed tokenId,
    address[] stakeHolders,
    address aggregator,
    uint256[2] prices,
    uint32[] share,
    uint32 quantity,
    uint32 presaleQuantity,
    uint32 royalty,
    uint32 album,
    bytes32 merkleRoot
  );

  event NowOnSale(
    uint256 indexed tokenId,
    SaleState indexed sales
  );

  event MusicPurchased(
    uint256 indexed tokenId,
    uint32 indexed album,
    uint32 numSold,
    address indexed buyer
  );

  event Recoup(
    uint256 indexed tokenId,
    address aggregator,
    uint256 value
  );

  event Withdraw(
    address indexed claimant,
    address recipient,
    uint256 value,
    uint256 distribution,
    uint256 locked
  );

  /**
    @dev 実行権限の確認
   */
  modifier onlyOwnerOrAgent {
    require(msg.sender == owner() || _agent[msg.sender], "This is not allowed except for owner or agent");
    _;
  }

  modifier onlyOwnerOrDistributor {
    require(msg.sender == owner() || msg.sender == distributor, "This is not allowed except for owner or distributor");
    _;
  }

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
  ) public initializer {
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
  // function createMusic(
  //   Music calldata music
  // ) public virtual onlyOwnerOrAgent {
  //   // データの有効性を確認
  //   _validateShare(music.stakeHolders, music.share);
  //   // _albumIdの有効性を確認
  //   require(_existsAlbum(music.album), 'The album does not exist');
  //   musics[newTokenId.current()] =
  //   Music({
  //     stakeHolders: music.stakeHolders,
  //     aggregator: music.aggregator,
  //     prices: music.prices,
  //     recoupLine: music.recoupLine,
  //     share: music.share,
  //     purchaseLimits: music.purchaseLimits,
  //     numSold: 0,
  //     quantity: music.quantity,
  //     presaleQuantity: music.presaleQuantity,
  //     royalty: music.royalty,
  //     album: uint32(music.album),
  //     merkleRoot: music.merkleRoot
  //   });

  //   emit MusicCreated(
  //     newTokenId.current(),
  //     music.stakeHolders,
  //     music.aggregator,
  //     music.prices,
  //     music.share,
  //     music.quantity,
  //     music.presaleQuantity,
  //     music.royalty,
  //     uint32(music.album),
  //     music.merkleRoot
  //   );

  //   // sales: default => prepared
  //   sales[newTokenId.current()] = SaleState.Prepared;
  //   // increment TokenId and AlbumId
  //   newTokenId.increment();
  //   ++_albumSize[music.album];
  // }

  /**
    @dev アルバムデータの作成
    @param album AlbumData(Struct)
   */
  function createAlbum(
    Album calldata album
  ) external virtual onlyOwnerOrAgent {
    // データの有効性を確認
    _validateAlbum(album);
    for(uint256 i=0; i<album._quantities.length; ++i){
      musics[newTokenId.current()] =
      Music({
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

  // function omniMint(
  //   uint256 _tokenId,
  //   uint32 _amount
  // ) external virtual payable {
  //   bytes32[] memory empty;
  //   omniMint(_tokenId, _amount, "", empty);
  // }

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
  ) public virtual payable {
    // _tokenIdの有効性を確認
    require(_exists(_tokenId), 'The music does not exist');
    // 在庫の確認
    require(musics[_tokenId].numSold + _amount <= musics[_tokenId].quantity, 'Amount exceed stock');

    // セール期間による分岐
    if (sales[_tokenId] == SaleState.Presale) {
      // 購入制限数の確認
      require(_tokenClaimed[_tokenId][_msgSender()] + _amount <=  musics[_tokenId].purchaseLimits[0], "Accumulayion amount of mint exceeds limit");
      _validateWhitelist(_tokenId, _merkleProof);
      // プレセール時の支払価格の確認
      require(msg.value >= musics[_tokenId].prices[0] * _amount,'Must send enough to purchase token.');
    }else if(sales[_tokenId] == SaleState.PublicSale){
      // 購入制限数の確認
      require(_tokenClaimed[_tokenId][_msgSender()] + _amount <=  musics[_tokenId].purchaseLimits[1], "Accumulayion amount of mint exceeds limit");
      // パブリックセール時の支払価格の確認
      require(msg.value >= musics[_tokenId].prices[1] * _amount,'Must send enough to purchase token.');
    }else{
      // SaleState: prepared or suspended
      revert("Tokens aren't on sale now");
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
    @dev セール状態の停止(列挙型で管理)
    @param _tokenIds 楽曲のid列
   */
  function suspendSale (
    uint256[] calldata _tokenIds
  ) external virtual onlyOwnerOrAgent {
    for(uint256 i=0; i<_tokenIds.length; ++i){
      sales[_tokenIds[i]] = SaleState.Suspended;
      emit NowOnSale(_tokenIds[i], sales[_tokenIds[i]]);
    }
  }

  /**
    @dev プレセールの開始(列挙型で管理)
    @param _tokenIds 楽曲のid列
   */
  function startPresale (
    uint256[] calldata _tokenIds
  ) external virtual onlyOwnerOrAgent {
    for(uint256 i=0; i<_tokenIds.length; ++i){
      sales[_tokenIds[i]] = SaleState.Presale;
      emit NowOnSale(_tokenIds[i], sales[_tokenIds[i]]);
    }
  }

  /**
    @dev パブリックセールの開始(列挙型で管理)
    @param _tokenIds 楽曲のid列
   */
  function startPublicSale (
    uint256[] calldata _tokenIds
  ) external virtual onlyOwnerOrAgent {
    for(uint256 i=0; i<_tokenIds.length; ++i){
      sales[_tokenIds[i]] = SaleState.PublicSale;
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
  ) public virtual onlyOwnerOrAgent {
    for(uint256 i=0; i<_tokenIds.length; ++i){
      musics[_tokenIds[i]].merkleRoot = _merkleRoot;
    }
  }

  // ============ utility ============

  /**
    @dev newTokenId is totalSupply+1
    @return totalSupply 各トークンの発行量
   */
  function totalSupply(uint256 _tokenId) external virtual view returns (uint256) {
    require(_exists(_tokenId), 'query for nonexistent token');
    return musics[_tokenId].numSold;
  }

  /**
    @dev 特定のアルバムのtokenId列を取得
    @param _albumId アルバムid
    @return _tokenIdsOfMusic tokenId
   */
  function getTokenIdsOfAlbum(
      uint256 _albumId
  ) public virtual view returns (uint256[] memory){
      // _albumIdの有効性を確認
      require(_existsAlbum(_albumId), 'The album does not exist');
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
  ) external view returns (address[] memory, uint32[] memory, address payable, uint256, uint256){
    Music memory music = musics[_tokenId];
    return(music.stakeHolders, music.share, music.aggregator, music.recoupLine, calculateRecoupLine(_tokenId));
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
  ) external virtual {
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
    require(value >= _value, 'claiming value exceed withdrawable value');
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
  ) public virtual view returns(
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
      _approval = (_recoupedValue[_tokenId] != 0 || musics[_tokenId].aggregator == address(0x0));
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
  function recoup(uint256 _tokenId) external {
    require(musics[_tokenId].aggregator == msg.sender, "caller should be aggregator");
    require(_recoupedValue[_tokenId] == 0, "cost have been recouped");
    uint256 value = calculateRecoupLine(_tokenId);
    if(profit[_tokenId] < value){
      value = profit[_tokenId];
    }
    _recoupedValue[_tokenId] = value;
    _sendFunds(musics[_tokenId].aggregator, value);
    emit Recoup(_tokenId, musics[_tokenId].aggregator, value);
  }

  /**
    @dev リクープラインの換算(円 => Wei)
    @param _tokenId 楽曲id
    @return value リクープライン(Wei)
   */
  function calculateRecoupLine(uint256 _tokenId) public view returns(uint256 value){
    // リクープ後
    if(_recoupedValue[_tokenId] != 0){
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
    require(address(this).balance >= _amount, 'Insufficient balance for send');
    (bool success, ) = _recipient.call{value: _amount}('');
    require(success, 'Unable to send value: recipient may have reverted');
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
  )external virtual onlyOwnerOrAgent {
    bytes32 digest = keccak256(abi.encode('oparationalMint(uint256 _tokenId,uint32 _amount)', _tokenId, _amount));
    _validateOparation(digest);
    // _tokenIdの有効性を確認
    require(_exists(_tokenId), 'The music does not exist');
    _mint(_recipient, _tokenId, _amount, _data);
  }

  /**
    @dev 資産の引き出しオペレーション
    @notice WIP-1: this function should be able to invalidated for the future
   */
  function operationalWithdraw(address payable _recipient, uint256 _claimed) external virtual onlyOwnerOrDistributor {
    bytes32 digest = keccak256(abi.encode('operationalWithdraw(address payable _recipient, uint256 _claimed)', _recipient, _claimed));
    _validateOparation(digest);
    _sendFunds(_recipient, _claimed);
  }

  /**
    @dev エージェントの設定
    @param _agentAddr エージェントのアドレス
    @param _licensed 権限の可否
  */
  function license(address _agentAddr, bool _licensed) external virtual onlyOwnerOrAgent {
    _agent[_agentAddr] = _licensed;
  }

  /**
    @dev 分配コントラクトの設定
    @param _distributor 分配コントラクトアドレス
   */
  function setRemoteDistributor(address _distributor) public virtual onlyOwnerOrAgent{
    distributor = _distributor;
  }

  /**
    @dev データフィードの再構成
    @param numeratorAddr_ 価格換算先のChainlinkアドレス
    @param denominatorAddr_ 価格換算元のChainlinkアドレス
   */
  function reconfigureData(address numeratorAddr_, address denominatorAddr_) external onlyOwnerOrAgent{
    _numeratorAddr = numeratorAddr_;
    _denominatorAddr = denominatorAddr_;
  }

  // ============ Token Standard ============

  /**
    @dev コントラクトの名称表示インターフェース
   */
  function name() public view virtual returns(string memory){
      return(_name);
  }

  /**
    @dev トークンの単位表示インターフェース
   */
  function symbol() public view virtual returns(string memory){
      return(_symbol);
  }

  /**
    @dev Returns e.g. https://.../{tokenId}
    @param _tokenId トークンID
    @return _tokenURI
   */
  function uri(uint256 _tokenId) public virtual view override returns (string memory) {
    require(_exists(_tokenId), 'ERC1155URIStorage: URI query for nonexistent token');
    return string(abi.encodePacked(baseURI,_tokenId.toString()));
  }

  /**
    @dev ベースURIの設定
   */
  function setBaseURI(
    string memory _uri
  ) external virtual onlyOwnerOrAgent {
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
    Music memory music = musics[_tokenId];
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

  function _validateShare(
    address[] calldata _stakeHolders,
    uint32[] calldata _share
  ) internal virtual {
    require(_stakeHolders.length==_share.length, "stakeHolders' and share's length don't match");
    uint32 s;
    for(uint256 i=0; i<_share.length; ++i){
      s += _share[i];
    }
    require(s == 100, 'total share must match to 100');
  }

  function _validateAlbum(
    Album calldata album
  ) internal virtual {
    _validateShare(album._stakeHolders, album._share);
    uint256 l = album._quantities.length;
    require(album._presaleQuantities.length == l, "presaleQuantities length isn't enough");
    require(album._presalePrices.length == l, "presalePrices length isn't enough");
    require(album._recoupLines.length == l, "recoupLines length isn't enough");
    require(album._prices.length == l, "prices length isn't enough");
    require(album._presalePurchaseLimits.length == l, "presalePurchaseLimits length isn't enough");
    require(album._purchaseLimits.length == l, "purchaseLimit length isn't enough");
  }

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
  function _getEtherPerJPY()private view returns(uint256){
    // return(10**13);
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
}