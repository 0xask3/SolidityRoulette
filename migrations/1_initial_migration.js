const Roulette = artifacts.require("Roulette");

module.exports = async function(deployer, network, accounts) {
  await deployer.deploy(
    Roulette,
    1078,
    "0xBbC88aD98b78e1AE8C1449B47D5060AB1D06890D"
  );

  const rouletteInstance = await Roulette.deployed();

  await rouletteInstance.setToken(
    "0x77c21c770Db1156e271a3516F89380BA53D594FA",
    true,
    BigInt(1e18),
    BigInt(1e30)
  );
};
