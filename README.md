Pillar Protocol: The Next-Generation Leveraged Liquidity Protocol
![alt text](https://img.shields.io/badge/License-MIT-yellow.svg)

![alt text](https://img.shields.io/badge/Built%20on-Sonic%20Testnet-blue.svg)
1. Overview
Pillar Protocol is an innovative and decentralized finance (DeFi) platform engineered for Leveraged Liquidity Providing (LP). It empowers users to maximize their capital efficiency and yield by supplying liquidity on a scale that significantly exceeds their initial capital.
The protocol's cornerstone innovation is its ability to safely integrate not only blue-chip assets like WETH but also highly volatile Meme Tokens into its ecosystem. This is achieved through a sophisticated, multi-layered risk management framework, making leveraged strategies accessible and more secure for a broader range of digital assets. By doing so, Pillar Protocol aims to unlock new levels of liquidity, enhance capital efficiency across the DeFi landscape, and introduce a reliable financial infrastructure for the burgeoning meme token market.
2. The Problem We Solve
Pillar Protocol is designed to address three fundamental challenges prevalent in the current DeFi ecosystem:
The Capital Efficiency Hurdle: Traditional Automated Market Maker (AMM) liquidity provision often requires substantial capital to generate meaningful returns. This high barrier to entry limits participation from retail users and results in capital being underutilized across the ecosystem.
The Meme Token Dilemma: Meme tokens offer explosive growth potential but are plagued by extreme volatility, a lack of reliable on-chain data, and high risks of rug pulls. Consequently, established DeFi protocols have been reluctant to integrate them as a legitimate asset class, leaving a significant market segment underserved and prone to speculation.
The Complexity of LP Management & Impermanent Loss: Effective liquidity provision, especially for volatile pairs, demands constant monitoring and manual rebalancing of price ranges to remain profitable. This complexity, combined with the persistent risk of Impermanent Loss, creates a challenging environment for LPs.
3. The Pillar Protocol Solution
Pillar Protocol tackles these issues with a unique, multi-contract architecture that delivers a robust and comprehensive solution.
Maximizing Capital Efficiency via Leverage: By integrating the DynamicRangeVault with the PillarLendingVault, the protocol allows users to borrow funds and open LP positions up to 10x their initial collateral. This leverage magnifies their exposure to trading fees and yield, dramatically increasing potential returns on capital.
Systematic, Data-Driven Risk Management for Meme Tokens: Pillar introduces a groundbreaking two-pronged strategy to safely onboard meme tokens:
PumpFunOracle: This on-chain oracle gathers objective, real-time data for assets, tracking metrics like 24-hour trading volume, total liquidity, holder count, and market capitalization.
MemeTokenRegistry: Using the data from the oracle, this registry evaluates and classifies meme tokens into distinct tiers (Bronze, Silver, Gold). Each tier is assigned a different maximum leverage limit, applying conservative risk parameters to newer, more volatile tokens while allowing higher leverage for more established ones. This pioneering approach transforms meme tokens from purely speculative assets into a systematically managed class within DeFi.
Simplified LP Management with Dynamic Ranges: The DynamicRangeVault automates the complexity of range management. It leverages the RangeCalculator library to automatically compute and propose an optimal price range based on the user's selected leverage. This feature simplifies the user experience, minimizes the need for manual rebalancing, and mitigates the risk of a position becoming inactive, thereby reducing exposure to Impermanent Loss.
4. Core Architecture
The protocol's functionality is distributed across a suite of interoperable smart contracts that work in concert.
code
Code
[ User ]
   |
   | 1. openDynamicPosition()
   V
[ DynamicRangeVault ] (Core user-facing contract for position management)
   |
   | 2. Checks maxLeverageForToken()
   V
[ MemeTokenRegistry ] (Determines risk tier and leverage cap for assets)
   |
   | 3. Fetches getTokenMetrics()
   V
[ PumpFunOracle ] (Provides on-chain data for risk assessment)
   |
   | 4. Calls borrow() for leverage
   V
[ PillarLendingVault ] (The central lending pool and source of liquidity)
   |
   | 5. In case of risk, position is flagged for forceLiquidatePosition()
   V
[ PillarLiquidationEngine ] (Maintains protocol solvency by liquidating undercollateralized positions)
DynamicRangeVault (The Core Vault): This is the central hub of the protocol and the primary point of interaction for users. It orchestrates the creation, management, and closing of all leveraged LP positions.
PillarLendingVault (The Lending Vault): This contract serves as the protocol's liquidity engine. Users can deposit assets (like USDC) to earn passive yield, and this liquidity is in turn borrowed by the DynamicRangeVault to provide leverage for LP positions.
PumpFunOracle & MemeTokenRegistry (The Risk Management Layer): These two contracts function as the "brain" of the protocol. The Oracle gathers crucial on-chain data, and the Registry uses this data to assess risk, assign tiers, and enforce leverage limits, particularly for meme tokens.
PillarLiquidationEngine (The Liquidation Engine): This contract acts as the protocol's safety net. It monitors the health of all open positions and liquidates those that fall below the required collateralization ratio, ensuring the solvency of the PillarLendingVault and the overall stability of the protocol.
5. Deployed Contracts on Sonic Testnet
All protocol contracts have been successfully deployed and verified on the Sonic Testnet.
Contract Name	Deployed Address (Sonic Testnet)
Mock USDC (tUSDC)	0xE2df0182DB96A3Ea6Da40084D5A71b75cc3BEAaE
Mock WETH (tWETH)	0xaA4F9467f4c751Fc189Fa25E1ea49E80d0db3824
PumpFunOracle	0xAa069119d57686699E0CafFb8b88eF9099D423D5
MemeTokenRegistry	0x102290A5368faC477DD851838B3044Ada1Df3FB9
PillarLendingVault	0x0af14fAe78BA2C419b760474041D71012E371Dc7
DynamicRangeVault (Core)	0xc0994d3305a8A2b031E65ED7eC090277eAae7C85
PillarLiquidationEngine	0xBf78b232D5ac3443A8D0b106F8e9369Fd84Fbde4
PILLAR Token	0x93B4e90E276cFb48db7D2c79FA90C691EFe08806
6. Frontend Integration
To interact with the Pillar Protocol from a frontend application, use the following JavaScript configuration object.
code
JavaScript
// Replace the CONTRACTS object in your frontend JavaScript code with the following:
const CONTRACTS = {
  dynamicVault: "0xc0994d3305a8A2b031E65ED7eC090277eAae7C85",
  lendingVault: "0x0af14fAe78BA2C419b760474041D71012E371Dc7",
  usdc: "0xE2df0182DB96A3Ea6Da40084D5A71b75cc3BEAaE",
  weth: "0xaA4F9467f4c751Fc189Fa25E1ea49E80d0db3824",
  oracle: "0xAa069119d57686699E0CafFb8b88eF9099D423D5",
  registry: "0x102290A5368faC477DD851838B3044Ada1Df3FB9",
  liquidationEngine: "0xBf78b232D5ac3443A8D0b106F8e9369Fd84Fbde4"
};
7. Future Roadmap
The launch on Sonic Testnet is just the beginning. Our vision for Pillar Protocol includes:
Expanded Asset Support: Integrating a wider range of blue-chip assets, major altcoins, and promising new meme tokens.
Decentralized Governance: Transitioning protocol ownership to the community by implementing a DAO structure where PILLAR token holders can vote on key parameters, such as fees, leverage caps, and new asset listings.
Enhanced UI/UX: Developing an advanced user dashboard for intuitive position management, performance tracking, and profit/loss analysis.
L2 and Multi-Chain Expansion: Expanding the protocol to other Layer 2 solutions and EVM-compatible blockchains to reach a broader user base and tap into new liquidity sources.
8. License
This project is licensed under the MIT License. See the LICENSE file for details.
