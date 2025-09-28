# Solana CLI with Solana network


## Current Command

```
Usage: solana-cli <COMMAND>

Commands:
  transfer    目前只能使用默认配置文件(～/.config/solana/cli/config.yml)中的账户作为发送账户转移SOL
  account     获取账户的信息
  balance     获取账户的SOL的余额
  mint-token  创建一个新账户并初始化为一个代币账户
  token-analysis  使用 Helius Rust SDK 获取 SPL 代币持有人分布与常见持仓 (RPC)
  help        Print this message or the help of the given subcommand(s)

Options:
  -h, --help     Print help
  -V, --version  Print version
```

### 示例：查看 SPL 代币的持有人分布

```bash
export HELIUS_API_KEY=your_api_key_here

# 仅展示前 10 名持有人 (可通过 --top-holders 调整)
solana-cli token-analysis <代币Mint地址> --holders-only --top-holders 10

# 完整分析：展示持有人、其它持仓以及最近的交易签名
solana-cli token-analysis <代币Mint地址>
```

> 说明：目前通过 Solana RPC 的 `getTokenLargestAccounts` 聚合前 20 个代币账户，按持有人去重后最多展示 20 个地址；如需更多数据可调整 Helius Token APIs。Helius 公共接口暂无法直接提供成本或 USD 估值。
>
> “其它 SPL 代币持仓” 仅展示 Helius 返回 priceInfo 且可从 Jupiter 获得价格的代币，缺乏价格的资产会被跳过以避免噪音。
