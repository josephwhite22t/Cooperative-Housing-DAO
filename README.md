# 🏠 Cooperative Housing DAO

A decentralized autonomous organization for managing shared housing projects on the Stacks blockchain. Token holders collectively make decisions about repairs, improvements, and profit distribution through transparent voting mechanisms.

## 🌟 Features

- 🪙 **Token-based Governance**: Housing tokens represent voting power and ownership stake
- 🗳️ **Democratic Voting**: Create and vote on proposals for housing decisions
- 💰 **Treasury Management**: Collective fund management for repairs and improvements
- 📊 **Transparent Operations**: All decisions and transactions recorded on-chain
- 💸 **Profit Distribution**: Automatic profit sharing based on token ownership
- 🔧 **Repair & Improvement Proposals**: Structured proposal system for housing maintenance

## 🚀 Getting Started

### Prerequisites

- Clarinet CLI installed
- Stacks wallet for testing

### Installation

1. Clone the repository
2. Navigate to the project directory
3. Deploy the contract using Clarinet

```bash
clarinet deploy
```

## 📋 Usage

### Initialize the DAO

```clarity
(contract-call? .Cooperative-Housing-DAO initialize-dao u1000000)
```

### Contribute to Treasury

```clarity
(contract-call? .Cooperative-Housing-DAO contribute-to-treasury u50000)
```

### Create a Proposal

```clarity
(contract-call? .Cooperative-Housing-DAO create-proposal 
  "Roof Repair" 
  "Fix leaking roof in building A" 
  u25000 
  "repair")
```

### Vote on Proposals

```clarity
(contract-call? .Cooperative-Housing-DAO vote-on-proposal u1 true)
```

### Execute Approved Proposals

```clarity
(contract-call? .Cooperative-Housing-DAO finalize-proposal u1)
(contract-call? .Cooperative-Housing-DAO execute-proposal u1)
```

## 🔍 Read-Only Functions

- `get-token-balance`: Check user's token balance
- `get-proposal`: Retrieve proposal details
- `get-treasury-balance`: View current treasury funds
- `calculate-voting-power`: Calculate user's voting percentage

## 🏗️ Contract Structure

### Core Components

- **Token System**: Fungible tokens representing ownership stakes
- **Proposal System**: Structured voting on housing decisions
- **Treasury**: Collective fund for expenses and improvements
- **Voting Mechanism**: Token-weighted democratic decision making

### Proposal Types

- `repair`: Emergency repairs and maintenance
- `improvement`: Property upgrades and enhancements
- `general`: Other housing-related decisions

## 🔐 Security Features

- Owner-only emergency functions
- Vote validation and duplicate prevention
- Treasury balance checks
- Proposal execution safeguards

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is open source and available under the MIT License.

---

*Built with ❤️ for decentralized housing communities*
```

**Git Commit Message:**
```
feat: implement cooperative housing DAO with token governance and treasury management
```

**GitHub Pull Request Title:**
```
🏠 Add Cooperative Housing DAO Smart Contract
```

**GitHub Pull Request Description:**
```
## 🏠 Cooperative Housing DAO Implementation

This PR introduces a comprehensive smart contract for managing cooperative housing projects through decentralized governance.

### ✨ Features Added

- **Token-based Governance System**: Housing tokens for voting and ownership representation
- **Proposal Management**: Create, vote on, and execute housing-related proposals
- **Treasury Operations**: Collective fund management with contribution tracking
- **Democratic Voting**: Token-weighted voting mechanism with time-bound proposals
- **Profit Distribution**: Automatic profit sharing based on token ownership
- **Emergency Controls**: Owner-only emergency functions for critical situations

### 🔧 Technical Implementation

- Built with Clarity smart contract language for Stacks blockchain
- Implements fungible token standard for governance tokens
- Comprehensive error handling and validation
- Read-only functions for transparency and data access
- Secure treasury management with balance checks

### 📊 Contract Capabilities

- Initialize DAO with token distribution
- Contribute funds to shared treasury
- Create proposals for repairs, improvements, and general decisions
- Vote on proposals with token-weighted influence
- Execute approved proposals automatically
- Distribute profits proportionally to token holders

### 🧪 Testing

- All core functions tested and validated
- Error conditions properly handled
- Security measures implemented and verified

Ready for deployment and community use! 🚀
