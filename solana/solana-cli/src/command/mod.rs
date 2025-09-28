use clap::{Parser, Subcommand};
use solana_sdk::pubkey::Pubkey;

pub mod accountinfo;
pub mod balance;
pub mod mint_token;
pub mod token_analysis;
pub mod transfer;

#[derive(Parser)]
#[command(version, about)]
pub struct Args {
    #[command(subcommand)]
    pub command: Command,
}

// Use patten: https://github.com/clap-rs/clap/blob/8e3d03639756241aa2b7dd624a7f5852bef76f31/examples/git-derive.rs
#[derive(Subcommand)]
pub enum Command {
    /// 目前只能使用默认配置文件(～/.config/solana/cli/config.yml)中的账户作为发送账户转移SOL
    Transfer {
        /// 目标账户的公钥
        to: Pubkey,
        /// 转移的SOL数量
        amount: u64,
    },
    /// 获取账户的信息
    Account {
        /// 账户的公钥
        address: Pubkey,
    },
    /// 获取账户的SOL的余额
    Balance {
        /// 账户的公钥
        address: Pubkey,
    },
    /// 创建一个新账户并初始化为一个代币账户
    MintToken,
    /// 使用 Helius Rust SDK (RPC) 分析 SPL 代币持有人分布
    TokenAnalysis {
        /// 代币铸造地址 (Mint)
        mint: String,
        /// Helius API Key，默认读取环境变量 HELIUS_API_KEY
        #[arg(long, env = "HELIUS_API_KEY")]
        api_key: Option<String>,
        /// 请求的分页页码 (默认 1)
        #[arg(long, default_value_t = 1)]
        page: u64,
        /// 每页请求的持有人数量 (默认 100)
        #[arg(long = "page-size", default_value_t = 100)]
        page_size: u64,
        /// 输出前 N 名持有人 (默认 10)
        #[arg(long = "top-holders", default_value_t = 10)]
        top_holders: usize,
        /// 对每位持有人统计的其它代币数量 (默认 5)
        #[arg(long = "top-other-tokens", default_value_t = 5)]
        top_other_tokens: usize,
        /// 展示的交易签名数量 (默认 25，设置为 0 则跳过)
        #[arg(long = "transfer-limit", default_value_t = 25)]
        transfer_limit: usize,
        /// 仅展示持有人清单
        #[arg(long = "holders-only")]
        holders_only: bool,
    },
}
