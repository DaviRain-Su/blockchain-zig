use clap::{Parser, Subcommand};
use solana_sdk::pubkey::Pubkey;

pub mod accountinfo;
pub mod balance;
pub mod transfer;

#[derive(Parser)]
#[command(version, about)]
pub struct Args {
    #[command(subcommand)]
    pub command: Command,
}

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
}
