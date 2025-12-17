import 'dotenv/config';
import './utils/decrypt-env-vars';

import 'hardhat-deploy';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-etherscan';
//import '@nomiclabs/hardhat-waffle';
import '@typechain/hardhat';
import 'hardhat-contract-sizer';
import 'hardhat-gas-reporter';
import 'hardhat-deploy-tenderly';
import { SolcUserConfig, HardhatUserConfig } from 'hardhat/types';
import 'solidity-coverage';
import { accounts, addForkConfiguration } from './utils/network';
import { task } from 'hardhat/config';

task('accounts', 'Prints the list of accounts', async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

task('named-accounts', 'Prints the named accounts', async (taskArgs, hre) => {
  const accounts = await hre.getNamedAccounts();
  console.log(accounts);
});

const DEFAULT_COMPILER_SETTINGS: SolcUserConfig = {
  version: '0.8.30',
  settings: {
    evmVersion: 'cancun',
    optimizer: {
      enabled: true,
      runs: 100_000,
    },
    metadata: {
      bytecodeHash: 'none',
    },
  },
};

if (process.env.RUN_COVERAGE == '1') {
  /**
   * Updates the default compiler settings when running coverage.
   *
   * See https://github.com/sc-forks/solidity-coverage/issues/417#issuecomment-730526466
   */
  console.info('Using coverage compiler settings');
  DEFAULT_COMPILER_SETTINGS.settings.details = {
    yul: true,
    yulDetails: {
      stackAllocation: true,
    },
  };
}

const config: HardhatUserConfig = {
  namedAccounts: {
    deployer: 0,
  },
  networks: addForkConfiguration({
    hardhat: {
      initialBaseFeePerGas: 0, // to fix : https://github.com/sc-forks/solidity-coverage/issues/652, see https://github.com/sc-forks/solidity-coverage/issues/652#issuecomment-896330136
      saveDeployments: true,
    },
    localhost: {
      url: 'http://localhost:8545',
      accounts: accounts(),
    },
    celo_mainnet: {
      url: 'https://forno.celo.org',
      chainId: 42220,
      accounts: accounts('celo_mainnet'),
    },
    celo_alfajores: {
      url: 'https://alfajores-forno.celo-testnet.org',
      chainId: 44787,
      accounts: accounts('celo_alfajores'),
    },
  }),
  paths: {
    sources: 'contracts',
  },
  gasReporter: {
    currency: 'USD',
    gasPrice: 100,
    enabled: process.env.REPORT_GAS ? true : false,
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
    maxMethodDiff: 10,
  },
  typechain: {
    outDir: 'typechain',
    target: 'ethers-v5',
  },
  solidity: {
    compilers: [DEFAULT_COMPILER_SETTINGS],
  },
  contractSizer: {
    alphaSort: false,
    disambiguatePaths: true,
    runOnCompile: false,
  },
};

if (process.env.ETHERSCAN_API_KEY) {
  config.etherscan = {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: process.env.ETHERSCAN_API_KEY,
  };
}

export default config;
