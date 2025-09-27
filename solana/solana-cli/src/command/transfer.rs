use solana_client::nonblocking::rpc_client::RpcClient;
use solana_commitment_config::CommitmentConfig;
use solana_sdk::native_token::sol_str_to_lamports;
use solana_sdk::pubkey::Pubkey;
use solana_sdk::signature::Keypair;
use solana_sdk::signer::Signer;
use solana_sdk::transaction::Transaction;
use solana_system_interface::instruction as system_instruction;

pub async fn transfer(from: &Keypair, to: &Pubkey, amount: u64) -> anyhow::Result<()> {
    println!(
        "Transferring {} SOL from {} to {}",
        amount,
        from.pubkey(),
        to
    );
    let client = RpcClient::new_with_commitment(
        "http://localhost:8899".to_string(),
        CommitmentConfig::confirmed(),
    );

    let amount = sol_str_to_lamports(&amount.to_string()).unwrap();
    let transfer_ix = system_instruction::transfer(&from.pubkey(), to, amount);
    let mut transaction = Transaction::new_with_payer(&[transfer_ix], Some(&from.pubkey()));
    transaction.sign(&[&from], client.get_latest_blockhash().await?);

    match client.send_and_confirm_transaction(&transaction).await {
        Ok(signature) => println!("Transaction Signature: {}", signature),
        Err(err) => eprintln!("Error sending transaction: {}", err),
    }

    Ok(())
}
