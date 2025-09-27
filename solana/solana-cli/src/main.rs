use solana_cli_config::{CONFIG_FILE, Config};
use solana_client::nonblocking::rpc_client::RpcClient;
use solana_commitment_config::CommitmentConfig;
use solana_sdk::native_token::Sol;
use solana_sdk::signature::Signer;
use solana_sdk::signer::keypair::read_keypair_file;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // read solana config file to load default rpc url and commitment config
    let config = Config::load(CONFIG_FILE.as_ref().unwrap())?;

    let client = RpcClient::new_with_commitment(
        "http://localhost:8899".to_string(),
        CommitmentConfig::confirmed(),
    );

    let key = read_keypair_file(config.keypair_path)
        .map_err(|err| anyhow::Error::msg(format!("Failed to read keypair file: {}", err)))?;

    let balance = client.get_balance(&key.pubkey()).await?;

    println!("Address: {}, Balance: {}", key.pubkey(), Sol(balance));

    // get AccountInfo
    let account_info = client.get_account(&key.pubkey()).await?;
    println!("{:#?}", account_info);

    Ok(())
}
