// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*
__        ___    ____ __  __ ___ __  __ _   _ ____ ___ ____ 
\ \      / / \  / ___|  \/  |_ _|  \/  | | | / ___|_ _/ ___|
 \ \ /\ / / _ \| |  _| |\/| || || |\/| | | | \___ \| | |    
  \ V  V / ___ \ |_| | |  | || || |  | | |_| |___) | | |___ 
   \_/\_/_/   \_\____|_|  |_|___|_|  |_|\___/|____/___\____|
*/

interface IEscrow {
  struct Policy {
    uint256[] requirement;
    uint256[] reward;
    uint256 period;
  }

  struct Asset {
    uint256 lockup_time;
    uint256[] token_ids;
  }

  function setPolicy(uint32 _number, uint256[] calldata requirement, uint256[] calldata reward, uint256 period) external;
  function lockup_721(uint32 _policy, uint256[] calldata _token_ids) external;
  function claim(uint32 _policy) external;
  function cancel(uint32 _policy) external;
}