use solana_client::nonblocking::rpc_client::RpcClient;
use solana_sdk::pubkey::Pubkey;

pub async fn account_info(address: &Pubkey, rpc_client: &RpcClient) -> anyhow::Result<()> {
    let account_info = rpc_client.get_account(&address).await?;
    println!("{}: {:#?}", address, account_info);

    Ok(())
}
