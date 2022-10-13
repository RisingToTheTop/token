// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*
__        ___    ____ __  __ ___ __  __ _   _ ____ ___ ____ 
\ \      / / \  / ___|  \/  |_ _|  \/  | | | / ___|_ _/ ___|
 \ \ /\ / / _ \| |  _| |\/| || || |\/| | | | \___ \| | |    
  \ V  V / ___ \ |_| | |  | || || |  | | |_| |___) | | |___ 
   \_/\_/_/   \_\____|_|  |_|___|_|  |_|\___/|____/___\____|
*/

interface IDistributor {
  function getDistribution(address claimant,uint256 tokenId,uint256 deposit,uint32 share) external view returns(bool approval,uint256 distribution);
  function getRecoupLine(uint256 tokenId) external view returns(uint256 recoupLine);
}