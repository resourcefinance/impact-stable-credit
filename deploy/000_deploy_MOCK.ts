import { HardhatRuntimeEnvironment } from "hardhat/types"
import { DeployFunction } from "hardhat-deploy/types"
import { deployProxyAndSave, deployProxyAndSaveAs, getConfig } from '../utils/utils';
import { AccessManager__factory, AssurancePool__factory, ERC20, FeeManager__factory, StableCreditRegistry__factory, StableCredit__factory } from "../types"
import { parseEther } from "ethers";

const func: DeployFunction = async function (hardhat: HardhatRuntimeEnvironment) {
  let { reserveTokenAddress, adminOwner, swapRouterAddress } = getConfig()
  let {ethers, upgrades, deployments} = hardhat
  const [owner] = await hardhat.ethers.getSigners();
  // deploy mock reserve token
  reserveTokenAddress = (await deployments.getOrNull("ReserveToken"))?.address
  if (!reserveTokenAddress) {
    const contractDeployment = await deployments.deploy("MockERC20", {
      from: owner.address,
      args: [
        parseEther("100000000"), 
        "USD Coin",
        "USDC"
      ]
    })
    reserveTokenAddress = contractDeployment.address
    await deployments.save("ReserveToken", contractDeployment)
    console.log("🚀 reserve token deployed at ", reserveTokenAddress)
  }

  // deploy assurance oracle
  let assuranceOracleAddress = (await deployments.getOrNull("AssuranceOracle"))?.address
  if (!assuranceOracleAddress) {
    const contractDeployment = await deployments.deploy("AssuranceOracle", {
      from: owner.address,
    })
    assuranceOracleAddress = contractDeployment.address
    await deployments.save("AssuranceOracle", contractDeployment)
    console.log("🚀 assurance oracle deployed at", assuranceOracleAddress)
  }

  // deploy StableCreditRegistry
  let stableCreditRegistryAddress = (await deployments.getOrNull("StableCreditRegistry"))
    ?.address
  if (!stableCreditRegistryAddress) {
    stableCreditRegistryAddress =  await deployProxyAndSave("StableCreditRegistry", [], hardhat)
  }

  // deploy access manager
  let accessManagerAddress = (await deployments.getOrNull("AccessManager"))?.address
  if (!accessManagerAddress) {
    const accessManagerArgs = [owner.address]
    accessManagerAddress = await deployProxyAndSave(
      "AccessManager",
      accessManagerArgs,
      hardhat,
    )
  }

  // deploy stable credit
  let stableCreditAddress = (await deployments.getOrNull("StableCreditMock"))?.address
  if (!stableCreditAddress) {
    const stableCreditArgs = ["Mock Network", "mUSD", accessManagerAddress]
    stableCreditAddress = await deployProxyAndSaveAs(
      "StableCreditMock",
      "StableCredit",
      stableCreditArgs,
      hardhat
    )
  }

  // deploy assurance pool
  let assurancePoolAddress = (await deployments.getOrNull("AssurancePool"))?.address
  if (!assurancePoolAddress) {
    const assurancePoolArgs = [
      stableCreditAddress,
      reserveTokenAddress,
      reserveTokenAddress,
      assuranceOracleAddress,
      swapRouterAddress,
      owner.address
    ]
    assurancePoolAddress = await deployProxyAndSave(
      "AssurancePool",
      assurancePoolArgs,
      hardhat,
    )
  }

  // deploy feeManager
  let feeManagerAddress = (await deployments.getOrNull("FeeManagerMock"))?.address
  if (!feeManagerAddress) {
    const feeManagerArgs = [stableCreditAddress]
    feeManagerAddress = await deployProxyAndSaveAs(
      "FeeManagerMock",
      "FeeManager",
      feeManagerArgs,
      hardhat,
    )
  }

  // deploy creditIssuer
  let creditIssuerAddress = (await deployments.getOrNull("CreditIssuerMock"))?.address
  if (!creditIssuerAddress) {
    const creditIssuerArgs = [stableCreditAddress]
    creditIssuerAddress = await deployProxyAndSaveAs(
      "CreditIssuerMock",
      "CreditIssuer",
      creditIssuerArgs,
      hardhat,
    )
  }

  // // ============ Initialize Contracts State ============ //


  const stableCredit = await hardhat.ethers.getContractAt("StableCreditMock", stableCreditAddress)
  const accessManager = await hardhat.ethers.getContractAt("AccessManager", accessManagerAddress)
  const assurancePool = await hardhat.ethers.getContractAt("AssurancePool", assurancePoolAddress)
  const feeManager = await hardhat.ethers.getContractAt("FeeManagerMock", feeManagerAddress)
  const stableCreditRegistry = await hardhat.ethers.getContractAt("StableCreditRegistry", stableCreditRegistryAddress)

  // grant admin access
  if (adminOwner) await (await accessManager.grantAdmin(adminOwner)).wait()
  // grant stableCredit operator access
  await (await accessManager.grantOperator(stableCreditAddress)).wait()
  // grant creditIssuer operator access
  await (await accessManager.grantOperator(creditIssuerAddress)).wait()
  // grant feeManager operator access
  await (await accessManager.grantOperator(feeManagerAddress)).wait()
  // set accessManager
  await (await stableCredit.setAccessManager(accessManagerAddress)).wait()
  // set feeManager
  await (await stableCredit.setFeeManager(feeManagerAddress)).wait()
  // set creditIssuer
  await (await stableCredit.setCreditIssuer(creditIssuerAddress)).wait()
  // set reservePool
  await (await stableCredit.setAssurancePool(assurancePoolAddress)).wait()
  // set targetRTD to 20%
  await (await assurancePool.setTargetRTD((20e16).toString())).wait()
  // set base fee rate to 5%
  await (await feeManager.setBaseFeeRate((5e16).toString())).wait()
  // set add network to registry
  await (await stableCreditRegistry.addNetwork(stableCreditAddress)).wait()
}

export default func
func.tags = ["MOCK"]
