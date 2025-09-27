use clap::Parser;
use solana_cli_config::{CONFIG_FILE, Config};
use solana_sdk::signer::keypair::read_keypair_file;

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
    };

    Ok(())
}
