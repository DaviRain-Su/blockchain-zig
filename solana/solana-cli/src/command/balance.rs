use solana_client::nonblocking::rpc_client::RpcClient;
use solana_sdk::{native_token::Sol, pubkey::Pubkey};

pub async fn balance(address: &Pubkey, rpc_client: &RpcClient) -> anyhow::Result<()> {
    let balance = rpc_client.get_balance(&address).await?;
    println!("{}: {}", address, Sol(balance));

    Ok(())
}
