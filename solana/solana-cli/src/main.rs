use clap::Parser;
use solana_cli_config::{CONFIG_FILE, Config};
use solana_client::nonblocking::rpc_client::RpcClient;
use solana_commitment_config::CommitmentConfig;
use solana_sdk::signature::Signer;
use solana_sdk::{signature::Keypair, signer::keypair::read_keypair_file};

pub mod command;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let config = Config::load(CONFIG_FILE.as_ref().unwrap())?;
    let client = RpcClient::new_with_commitment(config.json_rpc_url, CommitmentConfig::confirmed());

    let args = command::Args::parse();

    match args.command {
        command::Command::Transfer { to, amount } => {
            let from = read_keypair_file(config.keypair_path)
                .map_err(|err| anyhow::anyhow!("Failed to read keypair file: {}", err))?;
            command::transfer::transfer(&from, &to, amount, &client).await?;
        }
        command::Command::Account { address } => {
            { command::accountinfo::account_info(&address, &client).await }?
        }
        command::Command::Balance { address } => {
            command::balance::balance(&address, &client).await?
        }
        command::Command::MintToken => {
            let funding_account = read_keypair_file(config.keypair_path)
                .map_err(|err| anyhow::anyhow!("Failed to read keypair file: {}", err))?;
            let mint_account = Keypair::new();
            println!(
                "Mint account({:?}) private key: {:?}",
                mint_account.pubkey(),
                mint_account.to_base58_string()
            );
            command::mint_token::mint_token(&mint_account, &funding_account, &client).await?;
        }
    };

    Ok(())
}
