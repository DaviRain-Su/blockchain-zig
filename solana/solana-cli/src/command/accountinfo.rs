use solana_client::nonblocking::rpc_client::RpcClient;
use solana_commitment_config::CommitmentConfig;
use solana_sdk::pubkey::Pubkey;

pub async fn account_info(address: &Pubkey) -> anyhow::Result<()> {
    let client = RpcClient::new_with_commitment(
        "http://localhost:8899".to_string(),
        CommitmentConfig::confirmed(),
    );

    let account_info = client.get_account(&address).await?;
    println!("{}: {:#?}", address, account_info);

    Ok(())
}
