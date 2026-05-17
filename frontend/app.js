const ADDRESSES = {
  governanceToken: "0x9Dc80829f5D95b8aBC89e2b2711Ce75Bfa6dDc67",
  mockAsset: "0xa0CC573865B6800f9E9577b39B289FFe0cB7F8C9",
  yieldVault: "0x10C38C37455084Bb060d7c385145b6039F99bb6b",
  gameItems: "0x20a91c4E223f3670aCD6863B60c6aC9bFAa52de8",
  governor: "0x320E10Ab8531908dEb19927612EDD82fff3E9A79",
  ammFactory: "0xFD24fd97BD869819Dc77bc4bB92F28E8C3687353",
  tokenA: "0x11A8E2B59f5a8E7C5C5b9A1698d860Bb42Dceb34",
  tokenB: "0xe1c5c42fe18f2B96Ec22C5c02a8a900d6f16Be45"
};

const ARBITRUM_SEPOLIA_CHAIN_ID = "0x66eee";
const EXPLORER = "https://sepolia.arbiscan.io/tx/";

const erc20Abi = [
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address,address) view returns (uint256)",
  "function approve(address,uint256) returns (bool)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)"
];

const govTokenAbi = [
  "function balanceOf(address) view returns (uint256)",
  "function getVotes(address) view returns (uint256)",
  "function delegate(address)"
];

const vaultAbi = [
  "function asset() view returns (address)",
  "function totalAssets() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function deposit(uint256,address) returns (uint256)",
  "function withdraw(uint256,address,address) returns (uint256)"
];

const erc1155Abi = [
  "function balanceOf(address,uint256) view returns (uint256)",
  "function craft(uint256)"
];

const governorAbi = [
  "function votingDelay() view returns (uint256)",
  "function votingPeriod() view returns (uint256)",
  "function proposalThreshold() view returns (uint256)",
  "function state(uint256) view returns (uint8)",
  "function castVote(uint256,uint8) returns (uint256)",
  "function hasVoted(uint256,address) view returns (bool)"
];

const factoryAbi = [
  "function owner() view returns (address)",
  "function allPairs(uint256) view returns (address)",
  "function createPair(address,address) returns (address)"
];

let provider;
let signer;
let userAddress;

function $(id) {
  return document.getElementById(id);
}

function setStatus(message, type = "pending") {
  $("status").innerHTML = `Status: <span class="${type}">${message}</span>`;
}

function addLog(message, hash = null, type = "pending") {
  const div = document.createElement("div");
  div.className = "tx-item";
  div.innerHTML = hash
    ? `<span class="${type}">${message}</span><br><a href="${EXPLORER + hash}" target="_blank">${hash}</a>`
    : `<span class="${type}">${message}</span>`;
  $("txLog").prepend(div);
}

async function connectWallet() {
  try {
    if (!window.ethereum) {
      alert("MetaMask not found");
      return;
    }

    provider = new ethers.BrowserProvider(window.ethereum);
    await provider.send("eth_requestAccounts", []);

    const network = await provider.getNetwork();

    if (Number(network.chainId) !== 421614) {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: ARBITRUM_SEPOLIA_CHAIN_ID }]
      });
      provider = new ethers.BrowserProvider(window.ethereum);
    }

    signer = await provider.getSigner();
    userAddress = await signer.getAddress();

    $("wallet").innerText = `Wallet: ${userAddress}`;
    $("network").innerText = "Network: Arbitrum Sepolia";

    setStatus("Wallet connected", "success");
    await refreshDashboard();
  } catch (err) {
    handleError(err);
  }
}

async function ensureConnected() {
  if (!signer || !userAddress) {
    await connectWallet();
  }
}

function handleError(err) {
  console.error(err);

  let msg = err?.reason || err?.shortMessage || err?.message || "Unknown error";

  if (msg.includes("user rejected")) msg = "Transaction rejected by user";
  if (msg.includes("insufficient funds")) msg = "Insufficient ETH for gas";
  if (msg.includes("InsufficientResources")) msg = "Not enough ERC1155 resources for crafting";
  if (msg.includes("ERC20InsufficientAllowance")) msg = "Approve tokens first";
  if (msg.includes("ERC20InsufficientBalance")) msg = "Not enough token balance";

  setStatus(msg, "error");
  addLog(msg, null, "error");
}

async function waitTx(tx, label) {
  setStatus(`${label} pending...`);
  addLog(`${label} submitted`, tx.hash, "pending");
  await tx.wait();
  setStatus(`${label} confirmed`, "success");
  addLog(`${label} confirmed`, tx.hash, "success");
}

async function loadGovernanceData() {
  await ensureConnected();

  const token = new ethers.Contract(ADDRESSES.governanceToken, govTokenAbi, provider);

  const balance = await token.balanceOf(userAddress);
  const votes = await token.getVotes(userAddress);

  const b = ethers.formatEther(balance);
  const v = ethers.formatEther(votes);

  $("govBalance").innerText = `Balance: ${b}`;
  $("votingPower").innerText = `Voting Power: ${v}`;
  $("statGovBalance").innerText = b;
  $("statVotingPower").innerText = v;

  setStatus("Governance token data loaded", "success");
}

async function delegateVotes() {
  try {
    await ensureConnected();

    const token = new ethers.Contract(ADDRESSES.governanceToken, govTokenAbi, signer);
    const tx = await token.delegate(userAddress);

    await waitTx(tx, "Delegate votes");
    await loadGovernanceData();
  } catch (err) {
    handleError(err);
  }
}

async function loadVaultData() {
  await ensureConnected();

  const vault = new ethers.Contract(ADDRESSES.yieldVault, vaultAbi, provider);
  const assetAddress = await vault.asset();

  const asset = new ethers.Contract(assetAddress, erc20Abi, provider);

  const assetBalance = await asset.balanceOf(userAddress);
  const totalAssets = await vault.totalAssets();
  const shares = await vault.balanceOf(userAddress);

  $("vaultAsset").innerText = `Asset: ${assetAddress}`;
  $("assetBalance").innerText = `My Asset Balance: ${ethers.formatEther(assetBalance)}`;
  $("totalAssets").innerText = `Vault Total Assets: ${ethers.formatEther(totalAssets)}`;
  $("shareBalance").innerText = `My Shares: ${ethers.formatEther(shares)}`;
  $("statVaultAssets").innerText = ethers.formatEther(totalAssets);

  setStatus("Vault data loaded", "success");
}

async function approveVault() {
  try {
    await ensureConnected();

    const amountText = $("vaultAmount").value;
    if (!amountText) return alert("Enter amount first");

    const amount = ethers.parseEther(amountText);
    const asset = new ethers.Contract(ADDRESSES.mockAsset, erc20Abi, signer);

    const balance = await asset.balanceOf(userAddress);
    if (balance < amount) {
      setStatus("Not enough mUSD balance. Deposit cannot be executed.", "error");
      return;
    }

    const tx = await asset.approve(ADDRESSES.yieldVault, amount);
    await waitTx(tx, "Approve vault");
  } catch (err) {
    handleError(err);
  }
}

async function depositVault() {
  try {
    await ensureConnected();

    const amountText = $("vaultAmount").value;
    if (!amountText) return alert("Enter amount first");

    const amount = ethers.parseEther(amountText);

    const asset = new ethers.Contract(ADDRESSES.mockAsset, erc20Abi, provider);
    const balance = await asset.balanceOf(userAddress);
    const allowance = await asset.allowance(userAddress, ADDRESSES.yieldVault);

    if (balance < amount) {
      setStatus("Not enough mUSD balance for deposit", "error");
      return;
    }

    if (allowance < amount) {
      setStatus("Approve vault first", "error");
      return;
    }

    const vault = new ethers.Contract(ADDRESSES.yieldVault, vaultAbi, signer);
    const tx = await vault.deposit(amount, userAddress);

    await waitTx(tx, "Vault deposit");
    await loadVaultData();
  } catch (err) {
    handleError(err);
  }
}

async function withdrawVault() {
  try {
    await ensureConnected();

    const amountText = $("vaultAmount").value;
    if (!amountText) return alert("Enter amount first");

    const amount = ethers.parseEther(amountText);

    const vault = new ethers.Contract(ADDRESSES.yieldVault, vaultAbi, provider);
    const shares = await vault.balanceOf(userAddress);

    if (shares <= 0n) {
      setStatus("No vault shares to withdraw", "error");
      return;
    }

    const vaultWithSigner = new ethers.Contract(ADDRESSES.yieldVault, vaultAbi, signer);
    const tx = await vaultWithSigner.withdraw(amount, userAddress, userAddress);

    await waitTx(tx, "Vault withdraw");
    await loadVaultData();
  } catch (err) {
    handleError(err);
  }
}

async function loadItems() {
  await ensureConnected();

  const items = new ethers.Contract(ADDRESSES.gameItems, erc1155Abi, provider);

  const gold = await items.balanceOf(userAddress, 1);
  const wood = await items.balanceOf(userAddress, 2);
  const iron = await items.balanceOf(userAddress, 3);
  const sword = await items.balanceOf(userAddress, 100);
  const shield = await items.balanceOf(userAddress, 101);

  $("goldBalance").innerText = `Gold ID 1: ${gold}`;
  $("woodBalance").innerText = `Wood ID 2: ${wood}`;
  $("ironBalance").innerText = `Iron ID 3: ${iron}`;
  $("swordBalance").innerText = `Sword ID 100: ${sword}`;
  $("shieldBalance").innerText = `Shield ID 101: ${shield}`;

  setStatus("Game items loaded", "success");
}

async function craftSword() {
  try {
    await ensureConnected();

    const itemsRead = new ethers.Contract(ADDRESSES.gameItems, erc1155Abi, provider);
    const gold = await itemsRead.balanceOf(userAddress, 1);
    const iron = await itemsRead.balanceOf(userAddress, 3);

    if (gold < 10n || iron < 5n) {
      setStatus("Cannot craft Sword: need 10 GOLD + 5 IRON", "error");
      return;
    }

    const items = new ethers.Contract(ADDRESSES.gameItems, erc1155Abi, signer);
    const tx = await items.craft(100);

    await waitTx(tx, "Craft Sword");
    await loadItems();
  } catch (err) {
    handleError(err);
  }
}

async function craftShield() {
  try {
    await ensureConnected();

    const itemsRead = new ethers.Contract(ADDRESSES.gameItems, erc1155Abi, provider);
    const wood = await itemsRead.balanceOf(userAddress, 2);
    const iron = await itemsRead.balanceOf(userAddress, 3);

    if (wood < 15n || iron < 5n) {
      setStatus("Cannot craft Shield: need 15 WOOD + 5 IRON", "error");
      return;
    }

    const items = new ethers.Contract(ADDRESSES.gameItems, erc1155Abi, signer);
    const tx = await items.craft(101);

    await waitTx(tx, "Craft Shield");
    await loadItems();
  } catch (err) {
    handleError(err);
  }
}

async function loadGovernorData() {
  await ensureConnected();

  const governor = new ethers.Contract(ADDRESSES.governor, governorAbi, provider);

  const delay = await governor.votingDelay();
  const period = await governor.votingPeriod();
  const threshold = await governor.proposalThreshold();

  $("votingDelay").innerText = `Voting Delay: ${delay}`;
  $("votingPeriod").innerText = `Voting Period: ${period}`;
  $("proposalThreshold").innerText = `Proposal Threshold: ${ethers.formatEther(threshold)}`;

  setStatus("Governor data loaded", "success");
}

async function loadFactoryData() {
  await ensureConnected();

  const factory = new ethers.Contract(ADDRESSES.ammFactory, factoryAbi, provider);

  const owner = await factory.owner();

  let firstPair = "No pairs created yet";
  try {
    firstPair = await factory.allPairs(0);
  } catch (_) {}

  $("factoryOwner").innerText = `Owner: ${owner}`;
  $("firstPair").innerText = `First Pair: ${firstPair}`;

  setStatus("AMM factory data loaded", "success");
}

async function createPair() {
  try {
    await ensureConnected();

    const tokenA = $("tokenAInput").value || ADDRESSES.tokenA;
    const tokenB = $("tokenBInput").value || ADDRESSES.tokenB;

    if (!ethers.isAddress(tokenA) || !ethers.isAddress(tokenB)) {
      setStatus("Invalid token address", "error");
      return;
    }

    const factory = new ethers.Contract(ADDRESSES.ammFactory, factoryAbi, signer);
    const tx = await factory.createPair(tokenA, tokenB);

    await waitTx(tx, "Create AMM pair");
    await loadFactoryData();
  } catch (err) {
    handleError(err);
  }
}

async function refreshDashboard() {
  try {
    await ensureConnected();
    await loadGovernanceData();
    await loadVaultData();
    await loadItems();
    await loadGovernorData();
    await loadFactoryData();
  } catch (err) {
    handleError(err);
  }
}
const PROPOSAL_STATES = [
  "Pending", "Active", "Canceled", "Defeated",
  "Succeeded", "Queued", "Expired", "Executed"
];

async function loadProposalState() {
  try {
    await ensureConnected();
    const id = $("proposalIdInput").value;
    if (!id) return alert("Enter proposal ID");

    const governor = new ethers.Contract(ADDRESSES.governor, governorAbi, provider);
    const state = await governor.state(BigInt(id));
    const hasVoted = await governor.hasVoted(BigInt(id), userAddress);

    $("proposalState").innerText = `State: ${PROPOSAL_STATES[Number(state)] || state}`;
    $("proposalVoted").innerText = `You voted: ${hasVoted ? "Yes" : "No"}`;
    setStatus("Proposal loaded", "success");
  } catch (err) {
    handleError(err);
  }
}

async function castVote(support) {
  try {
    await ensureConnected();
    const id = $("proposalIdInput").value;
    if (!id) return alert("Enter proposal ID");

    const governor = new ethers.Contract(ADDRESSES.governor, governorAbi, signer);
    const tx = await governor.castVote(BigInt(id), support);
    await waitTx(tx, `Vote ${["Against","For","Abstain"][support]}`);
    await loadProposalState();
  } catch (err) {
    handleError(err);
  }
}

$("loadProposalBtn").addEventListener("click", loadProposalState);
$("voteForBtn").addEventListener("click", () => castVote(1));
$("voteAgainstBtn").addEventListener("click", () => castVote(0));
$("voteAbstainBtn").addEventListener("click", () => castVote(2));
$("connectBtn").addEventListener("click", connectWallet);
$("refreshBtn").addEventListener("click", refreshDashboard);
$("loadGovBtn").addEventListener("click", loadGovernanceData);
$("delegateBtn").addEventListener("click", delegateVotes);
$("loadVaultBtn").addEventListener("click", loadVaultData);
$("approveVaultBtn").addEventListener("click", approveVault);
$("depositVaultBtn").addEventListener("click", depositVault);
$("withdrawVaultBtn").addEventListener("click", withdrawVault);
$("loadItemsBtn").addEventListener("click", loadItems);
$("craftSwordBtn").addEventListener("click", craftSword);
$("craftShieldBtn").addEventListener("click", craftShield);
$("loadGovernorBtn").addEventListener("click", loadGovernorData);
$("loadFactoryBtn").addEventListener("click", loadFactoryData);
$("createPairBtn").addEventListener("click", createPair);