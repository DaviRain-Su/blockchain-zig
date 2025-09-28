use solana_client::nonblocking::rpc_client::RpcClient;
use solana_sdk::native_token::sol_str_to_lamports;
use solana_sdk::pubkey::Pubkey;
use solana_sdk::signature::Keypair;
use solana_sdk::signer::Signer;
use solana_sdk::transaction::Transaction;
use solana_system_interface::instruction as system_instruction;

pub async fn transfer(
    from: &Keypair,
    to: &Pubkey,
    amount: u64,
    rpc_client: &RpcClient,
) -> anyhow::Result<()> {
    println!(
        "Transferring {} SOL from {} to {}",
        amount,
        from.pubkey(),
        to
    );

    let amount = sol_str_to_lamports(&amount.to_string()).unwrap();
    // system_instruction.transfer() 方法创建一个指令，用于将 SOL 从 fromPubkey 账户转移到 toPubkey 账户，
    // 转移的金额为指定的 lamports。
    let transfer_ix = system_instruction::transfer(&from.pubkey(), to, amount);
    // 创建一个交易并将指令添加到交易中。
    //
    // 在此示例中，我们创建了一个包含单个指令的交易。然而，您可以向一个交易中添加多个指令。
    let mut transaction = Transaction::new_with_payer(&[transfer_ix], Some(&from.pubkey()));
    transaction.sign(&[&from], rpc_client.get_latest_blockhash().await?);

    match rpc_client.send_and_confirm_transaction(&transaction).await {
        //交易签名是一个唯一标识符，可用于在 Solana Explorer 上查询交易。
        Ok(signature) => println!("Transaction Signature: {}", signature),
        Err(err) => eprintln!("Error sending transaction: {}", err),
    }

    Ok(())
}
