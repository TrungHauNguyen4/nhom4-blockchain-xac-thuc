import "@nomicfoundation/hardhat-toolbox";
import "dotenv/config";

const config = {
  solidity: {
    version: "0.8.24",
    settings: {
      evmVersion: "cancun"
    }
  },
  networks: {
    sepolia: {
      url: process.env.RPC_URL || 'https://ethereum-sepolia-rpc.publicnode.com',
      accounts: [process.env.MASTER_PRIVATE_KEY]
    }
  }
};

export default config;
