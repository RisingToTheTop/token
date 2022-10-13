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
import {ERC721Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {CountersUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol';
import {MerkleProofUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";
import {StringsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IDistributor} from "../interfaces/IDistributor.sol";

/**
 * @title Token721
 * @author WAGMIMusic
 */
contract Token721 is ERC721Upgradeable, IERC2981Upgradeable, OwnableUpgradeable {
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
    bytes32 merkleRoot;// マークルルート
  }

  // 為替データの有効小数桁数
  uint8 constant DECIMALS = 10;
  // 価格換算先のChainlinkアドレス(Default:円)
  address public _numeratorAddr;
  // 価格換算元のChainlinkアドレス(Default:Ether)
  address public _denominatorAddr;
  // ベースURI(tokenURI=baseURI+editionId+/+tokenId)
  string internal baseURI;
  // 分配コントラクトアドレス
  address public distributor;
  // トークンのID
  CountersUpgradeable.Counter private newTokenId;
  // 楽曲のID
  CountersUpgradeable.Counter private newMusicId;
  // 販売状態(列挙型)
  enum SaleState {Prepared, Presale, PublicSale, Suspended} 

  // 楽曲id => 楽曲データ
  mapping(uint256 => Music) public musics;
  // tokenId => 楽曲id
  mapping(uint256 => uint256) public tokenToMusic;
  // 楽曲id => 販売状態
  mapping(uint256 => SaleState) public sales;
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
    uint256 indexed musicId,
    address[] stakeHolders,
    address aggregator,
    uint256[2] prices,
    uint32[] share,
    uint32 quantity,
    uint32 presaleQuantity,
    uint32 royalty,
    bytes32 merkleRoot
  );

  event NowOnSale(
    uint256 indexed tokenId,
    SaleState indexed sales
  );

  event MusicPurchased(
    uint256 indexed musicId,
    uint256 indexed tokenId,
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
    @param _name コントラクトの名称
    @param _symbol トークンの単位
    @param _baseURI ベースURI
   */
  function initialize(
        address _artist,
        string memory _name,
        string memory _symbol,
        string memory _baseURI
  ) public initializer {
      __ERC721_init(_name, _symbol);
      __Ownable_init();

      // コントラクトのデプロイアドレスに関わらずownerをartistに設定する
      transferOwnership(_artist);

      /**
      * Network: Ethereum
      * Aggregator: JPY/USD
      */
      _numeratorAddr = 0xBcE206caE7f0ec07b545EddE332A47C2F75bbeb3;
      /**
      * Network: Ethereum
      * Aggregator: ETH/USD
      */
      _denominatorAddr = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

      // deployerをエージェントに設定
      _agent[_msgSender()] = true;

      baseURI = _baseURI;
      // トークンidと楽曲idの初期値は1
      newTokenId.increment();
      newMusicId.increment();
  }

  // ============ Main Function ============

  /**
    @dev 楽曲データの作成
    @param music MusicData(Struct)
   */
  function createMusic(
    Music calldata music
  ) external virtual onlyOwnerOrAgent {
    // データの有効性を確認
    _validateShare(music.stakeHolders, music.share);
    
    musics[newMusicId.current()] =
    Music({
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
      merkleRoot: music.merkleRoot
    });

    emit MusicCreated(
      newMusicId.current(),
      music.stakeHolders,
      music.aggregator,
      music.prices,
      music.share,
      music.quantity,
      music.presaleQuantity,
      music.royalty,
      music.merkleRoot
    );

    // sales: default => prepared
    sales[newTokenId.current()] = SaleState.Prepared;
    newMusicId.increment();
  }

  // function omniMint(
  //   uint256 _musicId
  // ) external virtual payable {
  //   bytes32[] memory empty;
  //   omniMint(_musicId, empty);
  // }

  /**
    @dev NFTの購入
    @param _musicId 購入する楽曲のid
    @param _merkleProof マークルプルーフ
   */
  function omniMint(
    uint256 _musicId, 
    bytes32[] memory _merkleProof
  ) public virtual payable {
    // _musicIdの有効性を確認
    require(musics[_musicId].quantity > 0, 'The music does not exist');
    // 在庫の確認
    require(musics[_musicId].numSold < musics[_musicId].quantity, 'This edition is already sold out');
    // セール期間による分岐
    if (sales[_musicId] == SaleState.Presale) {
      // 購入制限数の確認
      require(_tokenClaimed[_musicId][_msgSender()] <  musics[_musicId].purchaseLimits[0], "Accumulayion amount of mint exceeds limit");
      _validateWhitelist(_musicId, _merkleProof);
      // プレセール時の支払価格の確認
      require(msg.value >= musics[_musicId].prices[0],'Must send enough to purchase token.');
    }else if(sales[_musicId] == SaleState.PublicSale){
      // 購入制限数の確認
      require(_tokenClaimed[_musicId][_msgSender()] <  musics[_musicId].purchaseLimits[1], "Accumulayion amount of mint exceeds limit");
      // パブリックセール時の支払価格の確認
      require(msg.value >= musics[_musicId].prices[1],'Must send enough to purchase token.');
    }else{
      // SaleState: prepared or suspended
      revert("Tokens aren't on sale now");
    }
    // トークンId+1(Reentrancy guard)
    uint256 _tokenId = newTokenId.current();
    newTokenId.increment();
    // 発行量+1
    ++musics[_musicId].numSold;
     // 購入履歴+1
    ++_tokenClaimed[_musicId][_msgSender()];
    // 楽曲idを保存
    tokenToMusic[_tokenId] = _musicId;
    // デポジットを更新
    profit[_musicId] += msg.value;
    _mint(_msgSender(), _tokenId);
    emit MusicPurchased(
      _musicId, 
      _tokenId, 
      musics[_musicId].numSold, 
      _msgSender()
    );
  }

  /**
    @dev セール状態の停止(列挙型で管理)
    @param _musicId 購入する楽曲のid
   */
  function suspendSale (
    uint256 _musicId
  ) external virtual onlyOwnerOrAgent {
    sales[_musicId] = SaleState.Suspended;
    emit NowOnSale(_musicId, sales[_musicId]);
  }

  /**
    @dev プレセールの開始(列挙型で管理)
    @param _musicId 購入する楽曲のid
   */
  function startPresale (
    uint256 _musicId
  ) external virtual onlyOwnerOrAgent {
    sales[_musicId] = SaleState.Presale;
    emit NowOnSale(_musicId, sales[_musicId]);
  }

  /**
    @dev パブリックセールの開始(列挙型で管理)
    @param _musicId 購入する楽曲のid
   */
  function startPublicSale (
    uint256 _musicId
  ) external virtual onlyOwnerOrAgent {
    sales[_musicId] = SaleState.PublicSale;
    emit NowOnSale(_musicId, sales[_musicId]);
  }

  /**
    @dev マークルルートの設定
    @param _musicId 楽曲id
    @param _merkleRoot マークルルート
   */
  function setMerkleRoot(
    uint256 _musicId,
    bytes32 _merkleRoot
  ) public virtual onlyOwnerOrAgent {
    musics[_musicId].merkleRoot = _merkleRoot;
  }

  // ============ utility ============

  /**
    @dev newTokenId is totalSupply+1
    @return totalSupply トークンの発行総量
   */
  function totalSupply() external virtual view returns (uint256) {
    return newTokenId.current() - 1;
  }

  /**
    @dev 特定の楽曲のtokenIdを取得
    @param _musicId 楽曲id
    @return _tokenIdsOfMusic tokenId
   */
  function getTokenIdsOfMusic(
      uint256 _musicId
  ) public virtual view returns (uint256[] memory){
      // _musicIdの有効性を確認
      require(musics[_musicId].quantity > 0, 'The music does not exist');
      uint256[] memory _tokenIdsOfMusic = new uint256[](musics[_musicId].numSold);
      uint256 index = 0;
      for (uint256 id = 1; id < newTokenId.current(); ++id){
        if (tokenToMusic[id] == _musicId) {
          _tokenIdsOfMusic[index] = id;
          ++index;
        }
      }
      return _tokenIdsOfMusic;
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
    for(uint256 id=1; id < newMusicId.current(); ++id){
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
    for(uint256 id=1; id < newMusicId.current(); ++id){
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
    uint256 _musicId,
    address _claimant
  ) internal virtual view returns(bool _approval, uint256 _distribution){
    uint32 _share = 0;
    for(uint32 i=0; i < musics[_musicId].stakeHolders.length; ++i){
      if(musics[_musicId].stakeHolders[i]==_claimant){
        _share = musics[_musicId].share[i];
        break;
      }
    }
    if(distributor == address(0x0)){
      // Defaultの分配契約
      _distribution = uint256(_share) * (profit[_musicId] - calculateRecoupLine(_musicId)) / 100;
      _approval = (_recoupedValue[_musicId] != 0 || musics[_musicId].aggregator == address(0x0));
      return(_approval, _distribution);
    }
    // 分配コントラクトの通信プロトコル
    (_approval, _distribution) = IDistributor(distributor).getDistribution(_claimant, _musicId, profit[_musicId], _share);
    return(_approval, _distribution);
  }

  /**
    @dev 諸費用のリクープ
    @param _musicId 楽曲id
   */
  function recoup(uint256 _musicId) external {
    require(musics[_musicId].aggregator == msg.sender, "caller should be aggregator");
    require(_recoupedValue[_musicId] == 0, "cost have been recouped");
    uint256 value = calculateRecoupLine(_musicId);
    if(profit[_musicId] < value){
      value = profit[_musicId];
    }
    _recoupedValue[_musicId] = value;
    _sendFunds(musics[_musicId].aggregator, value);
    emit Recoup(_musicId, musics[_musicId].aggregator, value);
  }

/**
    @dev リクープラインの換算(円 => Wei)
    @param _musicId 楽曲id
    @return value リクープライン(Wei)
   */
  function calculateRecoupLine(uint256 _musicId) public view returns(uint256 value){
    // リクープ後
    if(_recoupedValue[_musicId] != 0){
      return _recoupedValue[_musicId];
    }
    // default
    if(distributor == address(0x0)){
      uint256 converter = _getEtherPerJPY();
      value = musics[_musicId].recoupLine * converter;
      if(profit[_musicId] < value){
        value = profit[_musicId];
      }
      return value;
    }
    // custom: 分配コントラクトの通信プロトコル
    value = IDistributor(distributor).getRecoupLine(_musicId);
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
    uint256 _musicId,
    uint32 _amount
  )external virtual onlyOwnerOrAgent {
    bytes32 digest = keccak256(abi.encode('oparationalMint(uint256 _musicId,uint32 _amount)', _musicId, _amount));
    _validateOparation(digest);
    // _musicIdの有効性を確認
    require(musics[_musicId].quantity > 0, 'The music does not exist');
    // 発行量+amount
    musics[_musicId].numSold += _amount;
    for (uint256 i = 0; i<_amount; i++){
      // トークンId+1(Reentrancy guard)
      uint256 _tokenId = newTokenId.current();
      newTokenId.increment();
      _mint(_recipient, _tokenId);
    }
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
    @dev Returns e.g. https://.../{musicId}/{tokenId}
    @param _tokenId トークンID
    @return _tokenURI 
  */
  function tokenURI(uint256 _tokenId) public virtual view override returns (string memory) {
    require(_exists(_tokenId), 'ERC721URIStorage: URI query for nonexistent token');
    return string(abi.encodePacked(baseURI,tokenToMusic[_tokenId].toString(),'/',_tokenId.toString()));
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
    // tokenId => 楽曲データ
    uint256 _musicId = tokenToMusic[_tokenId];
    Music memory music = musics[_musicId];
    // 100_00 = 100%
    _royaltyAmount = (_salePrice * music.royalty) / 100_00;
    return(music.stakeHolders[0], _royaltyAmount);
  }

  function supportsInterface(
    bytes4 _interfaceId
  )public virtual view override(ERC721Upgradeable, IERC165Upgradeable)returns (bool)
  {
    return
      type(IERC2981Upgradeable).interfaceId == _interfaceId || ERC721Upgradeable.supportsInterface(_interfaceId);
  }

  // ============ helper function ============
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

  /**
    @dev whitelistの認証(マークルツリーを利用)
    @param _musicId 購入する楽曲のid
    @param _merkleProof マークルプルーフ
   */
  function _validateWhitelist(
    uint256 _musicId,
    bytes32[] memory _merkleProof
  ) internal virtual {
    bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
    require(
      MerkleProofUpgradeable.verify(_merkleProof, musics[_musicId].merkleRoot, leaf),
      "Invalid Merkle Proof"
    );
  }

  /**
    @dev 通貨価格の換算(円 => Wei)
    @return converter 円 => Wei
   */
  function _getEtherPerJPY()private view returns(uint256){
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