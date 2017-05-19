var LibSignatures = artifacts.require("./LibSignatures.sol");
var VPC           = artifacts.require("./VPC.sol");
var MSContract= artifacts.require("./MSContract.sol");

module.exports = function(deployer) {
  deployer.deploy(LibSignatures);
  deployer.link(LibSignatures, VPC);
  deployer.deploy(VPC);
  deployer.link(LibSignatures, MSContract);
  deployer.deploy(MSContract, "0x90f8bf6a479f320ead074411a4b0e7944ea8c9c1", "0xffcf8fdee72ac11b5c542428b35eef5769c409f0");
};
