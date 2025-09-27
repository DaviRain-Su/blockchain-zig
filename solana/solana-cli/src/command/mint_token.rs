use std::str::FromStr;

use solana_client::nonblocking::rpc_client::RpcClient;
use solana_commitment_config::CommitmentConfig;
use solana_pubkey::Pubkey;
use solana_sdk::instruction::{AccountMeta, Instruction};
use solana_sdk::signature::Keypair;
use solana_sdk::signer::Signer;
use solana_sdk::transaction::Transaction;
use solana_system_interface::instruction as system_instruction;
use spl_token::solana_program::program_pack::Pack;
use spl_token::{ID as TOKEN_PROGRAM_ID, instruction::initialize_mint2, state::Mint};

pub async fn mint_token(mint_account: &Keypair, funding_account: &Keypair) -> anyhow::Result<()> {
    let client = RpcClient::new_with_commitment(
        "http://localhost:8899".to_string(),
        CommitmentConfig::confirmed(),
    );
    let mint_account_len = Mint::LEN;
    let mint_account_rent = client
        .get_minimum_balance_for_rent_exemption(mint_account_len)
        .await?;
    let token_program_id = Pubkey::from_str(&TOKEN_PROGRAM_ID.to_string()).unwrap();
    let create_mint_account_ix = system_instruction::create_account(
        &funding_account.pubkey(),
        &mint_account.pubkey(),
        mint_account_rent,
        mint_account_len as u64,
        &token_program_id,
    );

    let initialize_mint_ix = initialize_mint2(
        &TOKEN_PROGRAM_ID.to_bytes().into(),
        &mint_account.pubkey().to_bytes().into(),
        &mint_account.pubkey().to_bytes().into(),
        Some(&mint_account.pubkey().to_bytes().into()),
        9,
    )?;

    let wrap_initialize_mint_ix = Instruction {
        program_id: initialize_mint_ix.program_id.to_bytes().into(),
        accounts: initialize_mint_ix
            .accounts
            .into_iter()
            .map(|account| AccountMeta {
                pubkey: account.pubkey.to_bytes().into(),
                is_signer: account.is_signer,
                is_writable: account.is_writable,
            })
            .collect(),
        data: initialize_mint_ix.data,
    };

    let mut transaction = Transaction::new_with_payer(
        &[create_mint_account_ix, wrap_initialize_mint_ix],
        Some(&funding_account.pubkey()),
    );

    transaction.sign(
        &[&funding_account, &mint_account],
        client.get_latest_blockhash().await?,
    );

    match client.send_and_confirm_transaction(&transaction).await {
        Ok(signature) => println!("Transaction Signature: {}", signature),
        Err(err) => eprintln!("Error sending transaction: {}", err),
    }

    Ok(())
}
