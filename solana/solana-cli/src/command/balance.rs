use solana_client::nonblocking::rpc_client::RpcClient;
use solana_commitment_config::CommitmentConfig;
use solana_sdk::{native_token::Sol, pubkey::Pubkey};

pub async fn balance(address: &Pubkey) -> anyhow::Result<()> {
    let client = RpcClient::new_with_commitment(
        "http://localhost:8899".to_string(),
        CommitmentConfig::confirmed(),
    );

    let balance = client.get_balance(&address).await?;
    println!("{}: {}", address, Sol(balance));

    Ok(())
}
