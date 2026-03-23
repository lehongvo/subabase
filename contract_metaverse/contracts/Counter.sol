// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

contract Counter {
  uint public x;

  event Increment(uint by);

  function inc() public {
    incBy(1);
  }

  function incBy(uint by) public {
    require(by > 0, "incBy: increment should be positive");
    x += by;
    emit Increment(by);
  }
}
