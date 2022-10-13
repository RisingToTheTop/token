// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract SumpleToken is ERC1155 {
  uint256 public value;

  constructor()ERC1155("uri"){}
  function oparationalMint(address _recipient, uint256 _tokenId, uint256 _amount, bytes memory data) public {_mint(_recipient, _tokenId, _amount, data);}
  function setData(uint256 a)public{
    value = a;
  }
}