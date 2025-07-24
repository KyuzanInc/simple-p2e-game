import { config as loadEnv } from "dotenv";
import hre from "hardhat";
import {
  Address,
  zeroAddress,
} from "viem";
import { getChain } from "../config/chains";

// 🎮 Hey there! Welcome to the SBT purchase script!
// Think of this as your friendly guide to buying SBTs (Soulbound Tokens) -
// they're like special digital collectibles that stick to your wallet forever!
//
// This script will show you THREE different ways to buy SBTs:
// 💰 SMP tokens - Your in-game currency (like coins in a video game!)
// 🪙 POAS tokens - Another type of digital money
// 💎 ETH - The "real money" of the blockchain world
//
// Don't worry if this sounds complicated - we'll walk through it step by step! 🚀

// First, let's grab our secret configuration from the .env file
// (It's like getting our wallet and keys before going shopping!)
loadEnv();

// 🏠 Here's where we keep track of all the important addresses
// Think of these like the addresses of different shops and your wallet!
const SBTSALE_ADDRESS = process.env.SBTSALE_ADDRESS as Address | undefined;  // The SBT shop
const SBT_ADDRESS = process.env.SBT_ADDRESS as Address | undefined;          // The SBT itself
const SMP_ADDRESS = process.env.SMP_ADDRESS as Address | undefined;          // Your SMP coin purse
const POAS_ADDRESS = process.env.POAS_ADDRESS as Address | undefined;        // Your POAS coin purse

// 🚨 Oops! Let's make sure you didn't forget to set up your addresses!
// It's like checking if you have your wallet before leaving the house 😅
if (!SBTSALE_ADDRESS || !SBT_ADDRESS || !SMP_ADDRESS || !POAS_ADDRESS) {
  throw new Error(
    "Whoops! Looks like you forgot to set up your .env file! 🙈\n" +
    "Please add: SBTSALE_ADDRESS, SBT_ADDRESS, SMP_ADDRESS and POAS_ADDRESS"
  );
}

/**
 * 🎉 Time to go shopping! This is where the magic happens!
 * Think of this like going to your favorite store and buying something awesome
 * @param token - What's in your wallet today? (SMP, POAS, or ETH)
 * @param sendValue - Are you paying with ETH? (true means yes, false means no)
 */
async function purchaseWith(token: Address, sendValue = false) {
  const chainId = Number(await hre.network.provider.send("eth_chainId"))
  const publicClient = await hre.viem.getPublicClient({
    chain: getChain(chainId),
  });
  // Let's get your account ready - this is like showing your ID at the store
  const [walletClient] = await hre.viem.getWalletClients({
    chain: getChain(chainId),
  });
  const account = walletClient.account.address;

  // Let's get all our shopping tools ready! 🛍️
  // It's like getting your credit cards, cash, and shopping bags before you start
  // The shop
  const sbtSale = await hre.viem.getContractAt("ISBTSale", SBTSALE_ADDRESS, {
    client: { public: publicClient, wallet: walletClient }
  });
   // The thing we're buying
  const sbt = await hre.viem.getContractAt("ISBTSaleERC721", SBT_ADDRESS, {
    client: { public: publicClient, wallet: walletClient }
  });
  // Your SMP wallet
  const smp = await hre.viem.getContractAt("IMockSMP", SMP_ADDRESS, {
    client: { public: publicClient, wallet: walletClient }
  });
  // Your POAS wallet
  const poas = await hre.viem.getContractAt("IPOAS", POAS_ADDRESS, {
    client: { public: publicClient, wallet: walletClient }
  });

  // 💲 First things first - let's see how much this is going to cost us!
  const price = await sbtSale.read.queryPrice([[SBT_ADDRESS], token]);
  console.log(`💰 Great news! The price for this SBT is: ${price} tokens`);

  // 🔐 If you're paying with tokens (not ETH), we need to give the shop permission
  // It's like signing a form that says "Yes, you can take money from my account"
  let approveHash;

  if (token === SMP_ADDRESS) {
    console.log("🤝 Giving the shop permission to take your SMP tokens...");
    approveHash = await smp.write.approve([SBTSALE_ADDRESS, price], { account });
  } else if (token === POAS_ADDRESS) {
    console.log("🤝 Giving the shop permission to take your POAS tokens...");
    approveHash = await poas.write.approve([SBTSALE_ADDRESS, price], { account });
  }

  if (approveHash) {
    const approveReceipt = await publicClient.waitForTransactionReceipt({ hash: approveHash });
    console.log((approveReceipt.status == "success" ? "✅️" : "❌") + " approve: " + approveReceipt.status);
  }

  // 🎯 Here we go! Time to make the actual purchase!
  // This is like walking up to the cashier and saying "I'll take it!"
  const paymentMethod = token === zeroAddress ? 'ETH 💎' : 'tokens 🪙';
  console.log(`🛒 Alright, let's buy this SBT with ${paymentMethod}...`);

  const purchaseHash = await sbtSale.write.purchase(
    [[SBT_ADDRESS], token, price],
    sendValue ? { account, value: price } : { account } // If paying with ETH, we include the money here
  );
  const purchaseReceipt = await publicClient.waitForTransactionReceipt({ hash: purchaseHash });
  console.log((purchaseReceipt.status == "success" ? "✅️" : "❌") + " purchase: " + purchaseReceipt.status);

  // 🎉 Let's check if our purchase worked!
  // It's like looking in your shopping bag to make sure you got what you paid for
  const balance = await sbt.read.balanceOf([account]);
  console.log(`🎊 Awesome! You now own ${balance} SBT(s)! Welcome to the club! 🎉`);
}

/**
 * 🌟 The main show! Let's try buying SBTs with all three payment methods!
 * Think of this as a fun shopping spree where we try different ways to pay
 */
async function main() {
  console.log("🎬 === Welcome to the SBT Shopping Adventure! === 🎬\n");
  console.log("We're going to buy SBTs three different ways. Ready? Let's go! 🚀\n");

  console.log("🥇 Round 1: Let's try paying with SMP tokens!");
  console.log("(This is like using your store credit card)\n");
  await purchaseWith(SMP_ADDRESS);

  console.log("\n" + "=".repeat(50));
  console.log("🥈 Round 2: Now let's try POAS tokens!");
  console.log("(This is like using a different credit card)\n");
  await purchaseWith(POAS_ADDRESS);

  console.log("\n" + "=".repeat(50));
  console.log("🥉 Round 3: Finally, let's pay with good old ETH!");
  console.log("(This is like paying with cash - the classic way!)\n");
  await purchaseWith(zeroAddress, true); // true = "Yes, I'm sending ETH!"

  console.log("\n" + "🎊".repeat(20));
  console.log("🎉 CONGRATULATIONS! You've successfully bought SBTs three different ways!");
  console.log("You're now a certified SBT shopping expert! 🏆");
  console.log("🎊".repeat(20));
}

// 🎬 Lights, camera, action! Let's start this show!
// (Don't worry - if anything goes wrong, we'll let you know what happened)
main().catch((e) => {
  console.error("😅 Oops! Something went wrong during our shopping adventure:");
  console.error("❌", e.message || e);
  console.error("\n💡 Don't worry! Check your .env file and try again!");
  process.exit(1);
});
