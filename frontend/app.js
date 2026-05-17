const ADDRESSES = {
  governanceToken: "0x9Dc80829f5D95b8aBC89e2b2711Ce75Bfa6dDc67",
  mockAsset: "0xa0CC573865B6800f9E9577b39B289FFe0cB7F8C9",
  yieldVault: "0x10C38C37455084Bb060d7c385145b6039F99bb6b",
  gameItems: "0x20a91c4E223f3670aCD6863B60c6aC9bFAa52de8",
  governor: "0x320E10Ab8531908dEb19927612EDD82fff3E9A79",
  ammFactory: "0xFD24fd97BD869819Dc77bc4bB92F28E8C3687353"
};

const ARBITRUM_SEPOLIA_CHAIN_ID = "0x66eee";

const erc20Abi = [
  "function balanceOf(address owner) view returns (uint256)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)"
];

const govTokenAbi = [
  "function balanceOf(address owner) view returns (uint256)",
  "function getVotes(address account) view returns (uint256)",
  "function delegate(address delegatee)"
];

const vaultAbi = [
  "function asset() view returns (address)",
  "function totalAssets() view returns (uint256)",
  "function balanceOf(address owner) view returns (uint256)",
  "function deposit(uint256 assets, address receiver) returns (uint256)"
];

const erc1155Abi = [
  "function balanceOf(address account, uint256 id) view returns (uint256)",
  "function craft(uint256 nftIdToMint)"
];

const governorAbi = [
  "function votingDelay() view returns (uint256)",
  "function votingPeriod() view returns (uint256)",
  "function proposalThreshold() view returns (uint256)"
];

const factoryAbi = [
  "function owner() view returns (address)",
  "function allPairs(uint256) view returns (address)",
  "function getPair(address,address) view returns (address)",
  "function createPair(address,address) returns (address)",
  "function createPairDeterministic(address,address,bytes32) returns (address)"
];

let provider;
let signer;
let userAddress;

function setStatus(message) {
  document.getElementById("status").innerText = `Status: ${message}`;
}

async function ensureConnected() {
  if (!signer || !userAddress) {
    await connectWallet();
  }
}

async function connectWallet() {
  if (!window.ethereum) {
    alert("MetaMask not found");
    return;
  }

  provider = new ethers.BrowserProvider(window.ethereum);
  await provider.send("eth_requestAccounts", []);

  const network = await provider.getNetwork();

  if (Number(network.chainId) !== 421614) {
    setStatus("Switching to Arbitrum Sepolia...");

    try {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: ARBITRUM_SEPOLIA_CHAIN_ID }]
      });
    } catch (error) {
      alert("Please add/switch to Arbitrum Sepolia in MetaMask.");
      console.error(error);
      return;
    }
  }

  signer = await provider.getSigner();
  userAddress = await signer.getAddress();

  document.getElementById("wallet").innerText = `Wallet: ${userAddress}`;
  document.getElementById("network").innerText = "Network: Arbitrum Sepolia";
  setStatus("Wallet connected");
}

async function loadGovernanceData() {
  await ensureConnected();

  const token = new ethers.Contract(
    ADDRESSES.governanceToken,
    govTokenAbi,
    provider
  );

  const balance = await token.balanceOf(userAddress);
  const votes = await token.getVotes(userAddress);

  document.getElementById("govBalance").innerText =
    `Balance: ${ethers.formatEther(balance)}`;

  document.getElementById("votingPower").innerText =
    `Voting Power: ${ethers.formatEther(votes)}`;

  setStatus("Governance token data loaded");
}

async function delegateVotes() {
  await ensureConnected();

  const token = new ethers.Contract(
    ADDRESSES.governanceToken,
    govTokenAbi,
    signer
  );

  setStatus("Delegating votes...");
  const tx = await token.delegate(userAddress);
  await tx.wait();

  setStatus(`Votes delegated. Tx: ${tx.hash}`);
  await loadGovernanceData();
}

async function loadVaultData() {
  await ensureConnected();

  const vault = new ethers.Contract(
    ADDRESSES.yieldVault,
    vaultAbi,
    provider
  );

  const asset = await vault.asset();
  const totalAssets = await vault.totalAssets();
  const shares = await vault.balanceOf(userAddress);

  const assetToken = new ethers.Contract(asset, erc20Abi, provider);
  const assetBalance = await assetToken.balanceOf(userAddress);

  document.getElementById("vaultAsset").innerText = `Asset: ${asset}`;
  document.getElementById("assetBalance").innerText =
    `My Asset Balance: ${ethers.formatEther(assetBalance)}`;
  document.getElementById("totalAssets").innerText =
    `Vault Total Assets: ${ethers.formatEther(totalAssets)}`;
  document.getElementById("shareBalance").innerText =
    `My Vault Shares: ${ethers.formatEther(shares)}`;

  setStatus("Vault data loaded");
}

async function approveVault() {
  await ensureConnected();

  const amountInput = document.getElementById("depositAmount").value;
  if (!amountInput) {
    alert("Enter deposit amount");
    return;
  }

  const amount = ethers.parseEther(amountInput);

  const asset = new ethers.Contract(
    ADDRESSES.mockAsset,
    erc20Abi,
    signer
  );

  setStatus("Approving vault...");
  const tx = await asset.approve(ADDRESSES.yieldVault, amount);
  await tx.wait();

  setStatus(`Vault approved. Tx: ${tx.hash}`);
}

async function depositToVault() {
  await ensureConnected();

  const amountInput = document.getElementById("depositAmount").value;
  if (!amountInput) {
    alert("Enter deposit amount");
    return;
  }

  const amount = ethers.parseEther(amountInput);

  const vault = new ethers.Contract(
    ADDRESSES.yieldVault,
    vaultAbi,
    signer
  );

  setStatus("Depositing to vault...");
  const tx = await vault.deposit(amount, userAddress);
  await tx.wait();

  setStatus(`Deposit completed. Tx: ${tx.hash}`);
  await loadVaultData();
}

async function loadItems() {
  await ensureConnected();

  const items = new ethers.Contract(
    ADDRESSES.gameItems,
    erc1155Abi,
    provider
  );

  const gold = await items.balanceOf(userAddress, 1);
  const wood = await items.balanceOf(userAddress, 2);
  const iron = await items.balanceOf(userAddress, 3);
  const sword = await items.balanceOf(userAddress, 100);
  const shield = await items.balanceOf(userAddress, 101);

  document.getElementById("goldBalance").innerText = `Gold ID 1: ${gold}`;
  document.getElementById("woodBalance").innerText = `Wood ID 2: ${wood}`;
  document.getElementById("ironBalance").innerText = `Iron ID 3: ${iron}`;
  document.getElementById("swordBalance").innerText =
    `Legendary Sword ID 100: ${sword}`;
  document.getElementById("shieldBalance").innerText =
    `Dragon Shield ID 101: ${shield}`;

  setStatus("Game items loaded");
}

async function craftSword() {
  await ensureConnected();

  const items = new ethers.Contract(
    ADDRESSES.gameItems,
    erc1155Abi,
    signer
  );

  setStatus("Crafting Legendary Sword...");
  const tx = await items.craft(100);
  await tx.wait();

  setStatus(`Legendary Sword crafted. Tx: ${tx.hash}`);
  await loadItems();
}

async function craftShield() {
  await ensureConnected();

  const items = new ethers.Contract(
    ADDRESSES.gameItems,
    erc1155Abi,
    signer
  );

  setStatus("Crafting Dragon Shield...");
  const tx = await items.craft(101);
  await tx.wait();

  setStatus(`Dragon Shield crafted. Tx: ${tx.hash}`);
  await loadItems();
}

async function loadGovernorData() {
  await ensureConnected();

  const governor = new ethers.Contract(
    ADDRESSES.governor,
    governorAbi,
    provider
  );

  const votingDelay = await governor.votingDelay();
  const votingPeriod = await governor.votingPeriod();
  const proposalThreshold = await governor.proposalThreshold();

  document.getElementById("votingDelay").innerText =
    `Voting Delay: ${votingDelay}`;
  document.getElementById("votingPeriod").innerText =
    `Voting Period: ${votingPeriod}`;
  document.getElementById("proposalThreshold").innerText =
    `Proposal Threshold: ${ethers.formatEther(proposalThreshold)}`;

  setStatus("Governor data loaded");
}

async function loadFactoryData() {
  await ensureConnected();

  const factory = new ethers.Contract(
    ADDRESSES.ammFactory,
    factoryAbi,
    provider
  );

  const owner = await factory.owner();

  let firstPair = "-";
  try {
    firstPair = await factory.allPairs(0);
  } catch (error) {
    firstPair = "No pairs created yet";
  }

  document.getElementById("factoryOwner").innerText = `Owner: ${owner}`;
  document.getElementById("pairCount").innerText = `First Pair: ${firstPair}`;

  setStatus("AMM factory data loaded");
}
document.getElementById("connectBtn").addEventListener("click", connectWallet);
document.getElementById("loadGovBtn").addEventListener("click", loadGovernanceData);
document.getElementById("delegateBtn").addEventListener("click", delegateVotes);
document.getElementById("loadVaultBtn").addEventListener("click", loadVaultData);
document.getElementById("approveVaultBtn").addEventListener("click", approveVault);
document.getElementById("depositVaultBtn").addEventListener("click", depositToVault);
document.getElementById("loadItemsBtn").addEventListener("click", loadItems);
document.getElementById("craftSwordBtn").addEventListener("click", craftSword);
document.getElementById("craftShieldBtn").addEventListener("click", craftShield);
document.getElementById("loadGovernorBtn").addEventListener("click", loadGovernorData);
document.getElementById("loadFactoryBtn").addEventListener("click", loadFactoryData);