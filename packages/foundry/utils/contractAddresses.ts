export const Tokens = {
  mainnet: {
    USDC: {
      address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
      decimals: 6,
    },
    USDT: {
      address: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
      decimals: 6,
    },
    WETH: {
      address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
      decimals: 18,
    },
  },
  sepolia: {
    USDC: {
      address: "0x07865c6E87B9F70255377e024ace6630C1Eaa37F",
      decimals: 6,
    },
    USDT: {
      // TODO: replace with the correct USDT address for Sepolia
      address: "0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0",
      decimals: 6,
    },
  },
  base: {
    USDC: {
      address: "0x94b008aA00579c1307B0EF2c499aD98a8ce58e58",
      decimals: 6,
    },
    USDT: {
      // TODO: replace with the correct USDT address for Base
      address: "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2",
      decimals: 6,
    },
  },
};


export const UniswapV4 = {
  mainnet: {
    UniversalRouterAddress: "0x66a9893cc07d91d95644aedd05d03f95e1dba8af",
    PoolManagerAddress: "0x000000000004444c5dc75cB358380D2e3dE08A90",
    PositionManagerAddress: "0xbd216513d74c8cf14cf4747e6aaa6420ff64ee9e",
  },
  sepolia: {
    UniversalRouterAddress: "0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b",
    PoolManagerAddress: "0xE03A1074c86CFeDd5C142C4F04F1a1536e203543",
    PositionManagerAddress: "0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4",
  },
  base: {
    UniversalRouterAddress: "0x6ff5693b99212da76ad316178a184ab56d299b43",
    PoolManagerAddress: "0x498581ff718922c3f8e6a244956af099b2652b2b",
    PositionManagerAddress: "0x7c5f5a4bbd8fd63184577525326123b519429bdc",
  },
};
