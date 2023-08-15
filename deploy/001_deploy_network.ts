import { HardhatRuntimeEnvironment } from "hardhat/types"
import { DeployFunction } from "hardhat-deploy/types"
import { deployProxyAndSave, deployProxyAndSaveAs, getConfig } from "../utils/utils"
import { ImpactStableCredit } from "../types"

const func: DeployFunction = async function (hardhat: HardhatRuntimeEnvironment) {
  let { symbol, name, swapRouterAddress, reserveTokenAddress, adminOwner } = getConfig()

  if (!reserveTokenAddress) throw new Error("reserveTokenAddress is not set")
  if (!symbol) throw new Error("symbol is not set")
  if (!name) throw new Error("name is not set")
  if (!adminOwner) throw new Error("adminOwner is not set")
  if (!swapRouterAddress) throw new Error("swapRouterAddress is not set")

  // ============ Deploy Contracts ============ //

  let { upgrades, deployments } = hardhat
  const [owner] = await hardhat.ethers.getSigners()

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

  // deploy access manager
  let accessManagerAddress = (await deployments.getOrNull("AccessManager"))?.address
  if (!accessManagerAddress) {
    const accessManagerArgs = [owner.address]
    accessManagerAddress = await deployProxyAndSave("AccessManager", accessManagerArgs, hardhat)
  }

  // deploy stable credit
  let stableCreditAddress = (await deployments.getOrNull("ImpactStableCredit"))?.address
  if (!stableCreditAddress) {
    const stableCreditArgs = [name, symbol, accessManagerAddress]
    stableCreditAddress = await deployProxyAndSaveAs(
      "ImpactStableCredit",
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
      owner.address,
    ]
    assurancePoolAddress = await deployProxyAndSave("AssurancePool", assurancePoolArgs, hardhat)
  }

  // deploy feeManager
  let feeManagerAddress = (await deployments.getOrNull("ImpactFeeManager"))?.address
  if (!feeManagerAddress) {
    const feeManagerArgs = [stableCreditAddress]
    feeManagerAddress = await deployProxyAndSaveAs(
      "ImpactFeeManager",
      "FeeManager",
      feeManagerArgs,
      hardhat
    )
  }

  // deploy creditIssuer
  let creditIssuerAddress = (await deployments.getOrNull("ImpactCreditIssuer"))?.address
  if (!creditIssuerAddress) {
    const creditIssuerArgs = [stableCreditAddress]
    creditIssuerAddress = await deployProxyAndSaveAs(
      "ImpactCreditIssuer",
      "CreditIssuer",
      creditIssuerArgs,
      hardhat
    )
  }

  // deploy credit pool
  let creditPoolAddress = (await hardhat.deployments.getOrNull("CreditPool"))?.address
  if (!creditPoolAddress) {
    const creditPoolArgs = [stableCreditAddress]
    creditPoolAddress = await deployProxyAndSave("CreditPool", creditPoolArgs, hardhat)
  }

  // deploy launch pool
  let launchPoolAddress = (await hardhat.deployments.getOrNull("LaunchPool"))?.address
  if (!launchPoolAddress) {
    const launchPoolArgs = [stableCreditAddress, creditPoolAddress, 30 * 24 * 60 * 60]
    launchPoolAddress = await deployProxyAndSave("LaunchPool", launchPoolArgs, hardhat)
  }

  // deploy ambassador
  let ambassadorAddress = (await hardhat.deployments.getOrNull("Ambassador"))?.address
  if (!ambassadorAddress) {
    // initialize ambassador with:
    //      30% depositRate,
    //      5% debtAssumptionRate,
    //      50% debtServiceRate,
    //      2 credit promotion amount
    const ambassadorArgs = [
      stableCreditAddress,
      (30e16).toString(),
      (5e16).toString(),
      (50e16).toString(),
      (2e6).toString(),
    ]
    ambassadorAddress = await deployProxyAndSave("Ambassador", ambassadorArgs, hardhat)
  }

  // ============ Initialize Contracts State ============ //

  const stableCredit = (await hardhat.ethers.getContractAt(
    "ImpactStableCredit",
    stableCreditAddress
  )) as ImpactStableCredit
  const accessManager = await hardhat.ethers.getContractAt("AccessManager", accessManagerAddress)
  const assurancePool = await hardhat.ethers.getContractAt("AssurancePool", assurancePoolAddress)
  const feeManager = await hardhat.ethers.getContractAt("ImpactFeeManager", feeManagerAddress)
  const admin = await hardhat.ethers.getContractAt(
    "OwnableUpgradeable",
    await (await upgrades.admin.getInstance()).getAddress()
  )

  // grant adminOwner admin access
  if (adminOwner) await (await accessManager.grantAdmin(adminOwner)).wait()
  // grant stableCredit operator access
  await (await accessManager.grantOperator(stableCreditAddress)).wait()
  // grant creditIssuer operator access
  await (await accessManager.grantOperator(creditIssuerAddress)).wait()
  // grant launchPool operator access
  await (await accessManager.grantOperator(launchPoolAddress)).wait()
  // grant creditPool operator access
  await (await accessManager.grantOperator(creditPoolAddress)).wait()
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
  // set ambassador
  await (await stableCredit.setAmbassador(ambassadorAddress)).wait()
  // set targetRTD to 20%
  await (await assurancePool.setTargetRTD((20e16).toString())).wait()
  // grant issuer role to ambassador
  await (await accessManager.grantIssuer(ambassadorAddress)).wait()
  // grant operator role to ambassador
  await (await accessManager.grantOperator(ambassadorAddress)).wait()

  if (adminOwner && (await admin.owner()) != adminOwner) {
    // transfer admin ownership to adminOwner address
    await upgrades.admin.transferProxyAdminOwnership(adminOwner)
  }
  // revoke signer admin access
  await (await accessManager.revokeAdmin((await hardhat.ethers.getSigners())[0].address)).wait()
}

export default func
func.tags = ["NETWORK"]
