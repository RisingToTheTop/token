const albumId = 1

const share = {
  description:""
}

const attributes = {
  Original: [
    {"trait_type":"Audio Type","value":"Original Mix"},
    {"trait_type":"Image Type","value":"Duction; #4348"},
    {"trait_type":"Artist","value":"Hibikilla"},
    {"trait_type":"Riddim","value":"Mr.Japlyn"},
    {"trait_type":"Chorus","value":"Singer Jilly"},
    {"trait_type":"Recording Engineer","value":"Akio (SRAD)"},
    {"trait_type":"Mixing Engineer","value":"Mr.Japlyn"},
    {"trait_type":"Mastering Engineer","value":"Hiroshi Shiota (Saltfield Mastering)"},
    {"trait_type":"Art Work","value":"Dozono Syunpei"},
    {"display_type":"date","trait_type":"Release Date","value":"1660921200"}
  ],
}

const assetElement = [
  {
    // 1. Orginal
    url:"https://ipfs.moralis.io:2053/ipfs/QmcZJuF6dsUne17JhTzDBcJoYCxbVGZBrnT5KtQRP1GTQh/metadata/1"
  },
  {
    // 2. Special
    url:"https://ipfs.moralis.io:2053/ipfs/QmcZJuF6dsUne17JhTzDBcJoYCxbVGZBrnT5KtQRP1GTQh/metadata/2"
  },
  {
    // 3. Instrumental
    url:"https://ipfs.moralis.io:2053/ipfs/QmcZJuF6dsUne17JhTzDBcJoYCxbVGZBrnT5KtQRP1GTQh/metadata/3"
  },
  {
    // 4. Acappella
    url:"https://ipfs.moralis.io:2053/ipfs/QmcZJuF6dsUne17JhTzDBcJoYCxbVGZBrnT5KtQRP1GTQh/metadata/4"
  },
  {
    // 5. Normal
    url:"https://api.opensea.io/api/v2/metadata/matic/0x2953399124f0cbb46d2cbacd8a89cf0599974963/78555306292208822264975053909961537674478548303611333324072215595578311049286"
  },
  {
    // 6. MV Rare
    url:"https://api.opensea.io/api/v2/metadata/matic/0x2953399124f0cbb46d2cbacd8a89cf0599974963/78555306292208822264975053909961537674478548303611333324072215596677822676997"
  },
  {
    // 7. Record Rare
    url:"https://api.opensea.io/api/v2/metadata/matic/0x2953399124f0cbb46d2cbacd8a89cf0599974963/78555306292208822264975053909961537674478548303611333324072215597777334304773"
  },
  {
    // 8. Acappella
    url:"https://api.opensea.io/api/v2/metadata/matic/0x2953399124f0cbb46d2cbacd8a89cf0599974963/78555306292208822264975053909961537674478548303611333324072215601075869188106"
  }
]

const editionSize = assetElement.length;

module.exports = {
  albumId,
  assetElement,
  editionSize
}