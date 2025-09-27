use std::str::FromStr;

use solana_address::Address;
use solana_client::nonblocking::rpc_client::RpcClient;
use solana_commitment_config::CommitmentConfig;
use solana_sdk::native_token::Sol;

#[tokio::main]
async fn main() {
    let client = RpcClient::new_with_commitment(
        "http://localhost:8899".to_string(),
        CommitmentConfig::confirmed(),
    );

    let address = Address::from_str("8uAPC2UxiBjKmUksVVwUA6q4RctiXkgSAsovBR39cd1i").unwrap();
    let balance = client.get_balance(&address).await.unwrap();

    println!("Address: {}, Balance: {}", address, Sol(balance));
}
