const fs = require("fs")
import { HardhatUserConfig, task } from "hardhat/config";
import { NetworkUserConfig } from "hardhat/types";
import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
import "hardhat-dependency-compiler"
import "hardhat-preprocessor"
import "hardhat-deploy"
import 'hardhat-deploy-ethers';
import "@typechain/hardhat"
import "@nomicfoundation/hardhat-ethers"
import "@openzeppelin/hardhat-upgrades"


dotenvConfig({ path: resolve(__dirname, "./.env") });

const chainIds = {
  ganache: 1337,
  goerli: 5,
  hardhat: 31337,
  kovan: 42,
  mainnet: 1,
  rinkeby: 4,
  ropsten: 3,
};

const MNEMONIC = process.env.MNEMONIC || "";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || "";
const INFURA_API_KEY = process.env.INFURA_API_KEY || "";

function createTestnetConfig(network: keyof typeof chainIds): NetworkUserConfig {
  const url: string = "https://" + network + ".infura.io/v3/" + INFURA_API_KEY;
  return {
    accounts: {
      count: 10,
      initialIndex: 0,
      mnemonic: MNEMONIC,
      path: "m/44'/60'/0'/0",
    },
    chainId: chainIds[network],
    url,
    saveDeployments: true,
  };
}

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      accounts: {
        mnemonic: MNEMONIC,
      },
      chainId: chainIds.hardhat,
      saveDeployments: true,
    },
    mainnet: createTestnetConfig("mainnet"),
    goerli: createTestnetConfig("goerli"),
    kovan: createTestnetConfig("kovan"),
    rinkeby: createTestnetConfig("rinkeby"),
    ropsten: createTestnetConfig("ropsten"),
  },
  solidity: {
    compilers: [
      {
        version: "0.8.15",
      },
    ],
  },
  typechain: {
    outDir: "types",
    target: "ethers-v6",
  },
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./contracts",
    tests: "./test",
    deployments: "./deployments",
    deploy: "./deploy",
    imports: "./artifacts",
  },
  dependencyCompiler: {
    paths: [
      "lib/stable-credit/contracts/Assurance/AssurancePool.sol",
      "lib/stable-credit/contracts/Assurance/AssuranceOracle.sol",
      "lib/stable-credit/lib/v3-periphery/contracts/interfaces/ISwapRouter.sol",
      "lib/stable-credit/contracts/StableCredit/StableCredit.sol",
      "lib/stable-credit/contracts/StableCredit/StableCreditRegistry.sol",
      "lib/stable-credit/contracts/AccessManager.sol",
      "lib/stable-credit/contracts/CreditIssuer.sol",
      "lib/stable-credit/contracts/FeeManager.sol",
    ],
  },
  preprocess: {
    eachLine: (hre) => ({
      transform: (line) => {
        if (line.match(/^\s*import /i)) {
          getRemappings().forEach(([find, replace]) => {
            if (line.match(find)) {
              line = line.replace(find, replace)
            }
          })
        }
        return line
      },
    }),
  }
};


export default config;

function getRemappings() {
  return fs
    .readFileSync("remappings.txt", "utf8")
    .split("\n")
    .filter(Boolean) // remove empty lines
    .map((line) => line.trim().split("="))
}
