import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers } = hre;
  const { deployer } = await getNamedAccounts();

  const pointAddress = (await deployments.get('TradCastPoint')).address;
  const seed = ethers.utils.solidityKeccak256(['string'], ['TradCastFeatures-Celo']);
  console.log('seed', seed);

  await deployments.deploy('TradCastFeatures', {
    contract: 'TradCastFeatures',
    from: deployer,
    args: [deployer, pointAddress, seed],
    log: true,
    autoMine: true,
  });
};

export default func;
func.id = 'deploy_tradcast_features';
func.tags = ['TradCastFeatures'];
