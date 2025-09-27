use clap::Parser;
use solana_cli_config::{CONFIG_FILE, Config};
use solana_sdk::signature::Signer;
use solana_sdk::{signature::Keypair, signer::keypair::read_keypair_file};

pub mod command;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args = command::Args::parse();
    match args.command {
        command::Command::Transfer { to, amount } => {
            let config = Config::load(CONFIG_FILE.as_ref().unwrap())?;
            let from = read_keypair_file(config.keypair_path)
                .map_err(|err| anyhow::anyhow!("Failed to read keypair file: {}", err))?;
            command::transfer::transfer(&from, &to, amount).await?;
        }
        command::Command::Account { address } => {
            { command::accountinfo::account_info(&address).await }?
        }
        command::Command::Balance { address } => command::balance::balance(&address).await?,
        command::Command::MintToken => {
            let config = Config::load(CONFIG_FILE.as_ref().unwrap())?;
            let funding_account = read_keypair_file(config.keypair_path)
                .map_err(|err| anyhow::anyhow!("Failed to read keypair file: {}", err))?;
            let mint_account = Keypair::new();
            println!(
                "Mint account({:?}) private key: {:?}",
                mint_account.pubkey(),
                mint_account.to_base58_string()
            );
            command::mint_token::mint_token(&mint_account, &funding_account).await?;
        }
    };

    Ok(())
}
