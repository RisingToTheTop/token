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
// ToDo:optimization
import {MerkleProofUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";
import {StringsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

/**
 * @title WAGMIMusicToken721
 * @author WAGMIMusic
 */
contract WAGMIMusicToken721 is ERC721Upgradeable, IERC2981Upgradeable, OwnableUpgradeable {
  using CountersUpgradeable for CountersUpgradeable.Counter;
  using StringsUpgradeable for uint256;

  struct Music {
    address payable[] stakeHolders;// 収益の受領者(筆頭受領者=二次流通ロイヤリティの受領者)
    uint256[2] prices;// [preSale価格，publicSale価格]
    uint32[] share;// 収益の分配率
    uint32 numSold;// 現在のトークン発行量
    uint32 quantity;// トークン発行上限
    uint32 presaleQuantity;// プレセール配分量
    uint32 royalty;// 二次流通時の印税
    bytes32 merkleRoot;// マークルルート
  }

  // ベースURI(tokenURI=baseURI+editionId+/+tokenId)
  string internal baseURI;
  // トークンのID
  CountersUpgradeable.Counter private newTokenId;
  // 楽曲のID
  CountersUpgradeable.Counter private newMusicId;
  // 販売状態(列挙型)
  enum SaleState {Presale, PublicSale, Suspended} 

  // 楽曲id => 楽曲データ
  mapping(uint256 => Music) public musics;
  // tokenId => 楽曲id
  mapping(uint256 => uint256) public tokenToMusic;
  // 楽曲id => 販売状態
  mapping(uint256 => SaleState) public sales;
  // 楽曲id, アドレス => 請求ログ
  mapping(uint256=>mapping(address => bool)) private _whitelistClaimed;
  // 実行権限のある執行者
  mapping(address => bool) private _agent;
  // 楽曲id => デポジット
  mapping(uint256 => uint256) private _deposit;
  mapping(uint256 => mapping(address => uint256)) private _withdrawnForEach;

  event MusicCreated(
    uint256 indexed musicId,
    address payable[] indexed stakeHolders,
    uint256[2] prices,
    uint32[] share,
    uint32 quantity,
    uint32 presaleQuantity,
    uint32 royalty,
    bytes32 merkleRoot
  );

  event MusicPurchased(
    uint256 indexed musicId,
    uint256 indexed tokenId,
    uint32 numSold,
    address indexed buyer
  );

  event NowOnSale(
    uint256 indexed musicId,
    SaleState indexed sales
  );

  /**
    @dev 実行権限の確認
   */
  modifier onlyOwnerOrAgent {
    require(msg.sender == owner() || _agent[msg.sender], "This is not allowed except for owner or agent");
    _;
  }

  /**
    @dev コンストラクタ(Proxyを利用したコントラクトはinitializeでconstructorを代用)
    @param _artist コントラクトのオーナーアドレス
    @param _name トークンの名称
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

      baseURI = _baseURI;
      // トークンidと楽曲idの初期値は1
      newTokenId.increment();
      newMusicId.increment();
  }

  // ============ Main Function ============

  /**
    @dev 楽曲データの作成
    @param _stakeHolders 収益の受領者
    @param _share 収益の分配率
    @param _prices [preSale価格，publicSale価格]
    @param _quantity トークン発行量
    @param _presaleQuantity プレセール配分量
    @param _royalty 二次流通時の印税
   */
  function createMusic(
    address payable[] calldata _stakeHolders,
    uint256[2] calldata _prices,
    uint32[] calldata _share,
    uint32 _quantity,
    uint32 _presaleQuantity,
    uint32 _royalty,
    bytes32 _merkleRoot
  ) external virtual onlyOwnerOrAgent {
    // データの有効性を確認
    _validateShare(_stakeHolders, _share);
    
    musics[newMusicId.current()] =
    Music({
      stakeHolders: _stakeHolders,
      prices: _prices,
      share: _share,
      numSold: 0,
      quantity: _quantity,
      presaleQuantity: _presaleQuantity,
      royalty: _royalty,
      merkleRoot: _merkleRoot
    });

    emit MusicCreated(
      newMusicId.current(),
      _stakeHolders,
      _prices,
      _share,
      _quantity,
      _presaleQuantity,
      _royalty,
      _merkleRoot
    );
    sales[newMusicId.current()] = SaleState.Suspended;
    newMusicId.increment();
  }

  function omniMint(
    uint256 _musicId
  ) public virtual payable {
    bytes32[] memory empty;
    omniMint(_musicId, empty);
  }

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
    // 販売状態の確認
    require(sales[_musicId] != SaleState.Suspended, 'Sale is suspended now');
    // 在庫の確認
    require(musics[_musicId].numSold < musics[_musicId].quantity, 'This edition is already sold out');
    // セール期間による分岐
    if (sales[_musicId] == SaleState.Presale) {
      _validateWhitelist(_musicId, _merkleProof);
      // プレセール時の支払価格の確認
      require(msg.value >= musics[_musicId].prices[0],'Must send enough to purchase token.');
    }else{
      // パブリックセール時の支払価格の確認
      require(msg.value >= musics[_musicId].prices[1],'Must send enough to purchase token.');
    }
    // トークンId+1(Reentrancy guard)
    uint256 _tokenId = newTokenId.current();
    newTokenId.increment();
    // 発行量+1
    musics[_musicId].numSold++;
    // 楽曲idを保存
    tokenToMusic[_tokenId] = _musicId;
    // デポジットを更新
    _deposit[_musicId] += msg.value;

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
      uint256[] memory _tokenIdsOfMusic = new uint256[](musics[_musicId].numSold);
      uint256 index = 0;
      for (uint256 id = 1; id < newTokenId.current(); id++){
        if (tokenToMusic[id] == _musicId) {
          _tokenIdsOfMusic[index] = id;
          index++;
        }
      }
      return _tokenIdsOfMusic;
  }

  // ============ Revenue Pool ============
  /**
    @dev 収益の引き出し
    @param _recipient 受領者
    @dev param: _withdrawable 引き出し可能な資産総額
    @dev param: dist Editionごとの引き出し可能な資産額
   */
  function withdraw(
    address payable _recipient
  ) external virtual {
    uint256 _withdrawable = 0;
    for(uint256 id=1; id < newMusicId.current(); id++){
      uint256 dist = _getDistribution(id) - _withdrawnForEach[id][_msgSender()];
      _deposit[id] -= dist;
      _withdrawnForEach[id][_msgSender()] += dist;
      _withdrawable += dist;
    }
    require(_withdrawable > 0, 'withdrawable distribution is zero');
    _sendFunds(_recipient, _withdrawable);
  }

  /**
    @dev 引き出し可能な資産額の確認
    @param _distribution 配分された資産総額
    @param _withdrawable 引き出し可能な資産総額
   */
  function withdrawable() public virtual view returns(
    uint256 _distribution,
    uint256 _withdrawable
  ){
    _distribution = 0;
    for(uint256 id=1; id < newMusicId.current(); id++){
      _distribution += _getDistribution(id);
      _withdrawable += _getDistribution(id) - _withdrawnForEach[id][_msgSender()];
    }
    return(_distribution, _withdrawable);
  }

  /**
    @dev 分配資産額の確認
   */
  function _getDistribution(
    uint256 _musicId
  ) internal virtual view returns(uint256 _distribution){
    uint256 _share = 0;
    for(uint32 i=0; i < musics[_musicId].stakeHolders.length;i++){
      if(musics[_musicId].stakeHolders[i]==_msgSender()){
        _share = musics[_musicId].share[i];
        break;
      }
    }
    _distribution = _share * _deposit[_musicId] / 100;
    return(_distribution);
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
  function oparationalMint (
    address _recipient,
    uint256 _musicId,
    uint32 _amount
  )external virtual onlyOwner{
    bytes32 digest = keccak256(abi.encode('oparationalMint(uint256 _musicId,uint32 _amount)', _musicId, _amount));
    _validateOparation(digest);
    // _musicIdの有効性を確認
    require(musics[_musicId].quantity > 0, 'The music does not exist');
    // 在庫の確認
    require(musics[_musicId].numSold + _amount <= musics[_musicId].quantity, 'This edition is already sold out');
    // 発行量+_amount
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
  function operationalWithdraw(address payable _recipient, uint256 _claimed) external virtual onlyOwner {
    bytes32 digest = keccak256(abi.encode('operationalWithdraw(address payable _recipient, uint256 _claimed)', _recipient, _claimed));
    _validateOparation(digest);
    require(_claimed <= address(this).balance, "Claimed amount is exceeding funding");
    _sendFunds(_recipient, _claimed);
  }
  function _validateOparation(bytes32 digest) internal virtual {}

  /**
    @dev エージェントの設定
    @param _agentAddr エージェントのアドレス
    @param _licensed 権限の可否
  */
  function license(address _agentAddr, bool _licensed) external virtual onlyOwner {
    _agent[_agentAddr] = _licensed;
  }

  // ============ Token Standard ============

  /**
    @dev Returns e.g. https://.../{musicId}/{tokenId}
    @notice WIP-1: modify tokenURI to https://.../{musicId}
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
    // ToDo: decimalのテスト必須
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

  function _validateShare(
    address payable[] calldata _stakeHolders,
    uint32[] calldata _share
  ) internal virtual {
    require(_stakeHolders.length==_share.length, "stakeHolders' and share's length don't match");
    uint32 s;
    for(uint256 i=0; i<_share.length; i++){
      s += _share[0];
    }
    require(s == 100, 'total share must match to 100');
  }

  /**
    @dev whitelistの認証(マークルツリーを利用)
    @param _musicId 購入する楽曲のid
    @param _merkleProof マークルプルーフ
   */
  function _validateWhitelist (
    uint256 _musicId,
    bytes32[] memory _merkleProof
  ) internal virtual {
    require(!_whitelistClaimed[_musicId][msg.sender], "Address already claimed");
    bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
    require(
      MerkleProofUpgradeable.verify(_merkleProof, musics[_musicId].merkleRoot, leaf),
      "Invalid Merkle Proof"
    );
    _whitelistClaimed[_musicId][msg.sender] = true;
  }
}