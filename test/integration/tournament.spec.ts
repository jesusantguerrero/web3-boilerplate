/* eslint-disable no-unused-expressions */
/* eslint-disable node/no-missing-import */
import chai from "chai";
import chaiAsPromised from "chai-as-promised";
import { getContract } from "../../utils/getContract";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import hre from "hardhat";
import {
  autoFundCheck,
  networkConfig,
  getNetworkIdFromName,
} from "../../helper-hardhat-config";
import { ethers } from "ethers";

chai.use(chaiAsPromised);
const { expect } = chai;
// eslint-disable-next-line no-unused-vars
let owner: SignerWithAddress;
let user2: SignerWithAddress;
let user3: SignerWithAddress;

(async () => {
  [owner, user2, user3] = await hre.ethers.getSigners();
})();

let tournament: ethers.Contract,
  linkToken: ethers.Contract,
  vrfCoordinator: ethers.Contract,
  pcToken: ethers.Contract;

beforeEach(async () => {
  await hre.deployments.fixture(["mocks", "local"]);
  const LinkToken = await hre.deployments.get("LinkToken");
  const VRFCoordinatorMock = await hre.deployments.get("VRFCoordinatorMock");
  const RoosterFight = await hre.deployments.get("RoosterFight");
  linkToken = await hre.ethers.getContractAt("LinkToken", LinkToken.address);
  vrfCoordinator = await hre.ethers.getContractAt(
    "VRFCoordinatorMock",
    VRFCoordinatorMock.address
  );
  pcToken = await hre.ethers.getContractAt(
    "RoosterFight",
    RoosterFight.address
  );
  const networkId = await getNetworkIdFromName("localhost");
  const keyHash = networkConfig[networkId || 1].keyHash || "";
  tournament = await getContract("Tournament", [
    vrfCoordinator.address,
    linkToken.address,
    keyHash,
  ]);

  if (
    await autoFundCheck(
      tournament.address,
      "localhost",
      linkToken.address,
      "Nothing more"
    )
  ) {
    await hre.run("fund-link", {
      contract: tournament.address,
      linkaddress: linkToken.address,
    });
  }
});
describe("Tournament unit tests", async () => {
  it("Should add participants", async () => {
    await tournament.addPrix(
      "Amateur League",
      "Tournament for new cock fighters",
      8,
      ethers.utils.parseEther("100")
    );
    const startDate = new Date().getTime();
    const endDate = startDate + 7;
    await tournament.addEvent(0, startDate, endDate);

    // integration with fights
    await pcToken.connect(user2).mint(1);
    await pcToken.connect(user3).mint(2);

    // Token registration
    await tournament.setNFTAddress(pcToken.address);

    // tournament registration
    const eventFee = await tournament.getEventFee(0);
    await tournament.connect(user2).addParticipant(1, 0, { value: eventFee });
    await tournament.connect(user3).addParticipant(2, 0, { value: eventFee });
    expect((await tournament.getEventParticipants(0)).length).to.equal(2);

    //  fights
    const trx = await tournament.prepareFight(0, 1, 0);
    const receipt = await trx.wait(1);
    const requestId = receipt.events[2].topics[1];
    expect((await tournament.getMatchesForEvent(0)).length).to.equal(1);
    console.log("events: ", receipt.events);
    console.log("requestId: ", requestId);
    expect(requestId).to.not.be.null;

    // wait 60 secs for oracle to callback
    await new Promise((resolve) => setTimeout(resolve, 30000));

    const result = await tournament.startFight(requestId, 0);
    const trx2 = await result.wait(1);
    console.log("events: ", trx2.events);
    await tournament.payout(0);
  });
});
