import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deployer } = await getNamedAccounts();

  await deployments.deploy('TradCastPoint', {
    contract: 'TradCastPoint',
    from: deployer,
    args: [deployer],
    log: true,
    autoMine: true,
  });
};

export default func;
func.id = 'deploy_tradcast_point';
func.tags = ['TradCastPoint'];
