module qiro::lending_vault{
    use std::signer;
    use aptos_framework::account;
    use std::vector;
    use aptos_framework::coin::{Self, BurnCapability, MintCapability};
    use aptos_framework::timestamp;

    // Errors
    const EALREADY_VAULT: u64 = 1;
    const ENOT_ADMIN: u64 = 2;

    struct Deposit has key, store {
        id: u64, 
        amount: u64, 
        timestamp: u64, 
    }
    struct Vault has key {
        admin: address,
        whitelist: vector<address>, 
        deposits: vector<Deposit>,
        prefilled: u64,
    }
    public entry fun new_vault(account: &signer, prefilled: u64) {
        assert!(!exists<Vault>(signer::address_of(account)), EALREADY_VAULT);
        let vault = Vault {
            admin: signer::address_of(account),
            whitelist: vector::empty(),
            deposits: vector::empty(),
            prefilled,
        };
        move_to(account, vault);
    }

    public entry fun add_to_whitelist(account: &signer, addresses: vector<address>) acquires Vault {
        let vault = borrow_global_mut<Vault>(signer::address_of(account));
        assert!(vault.admin == signer::address_of(account), ENOT_ADMIN);
        let i = 0;
        let len = vector::length(&addresses);
        while (i < len) {
            let addr = vector::borrow(&addresses, i);
            vector::push_back(&mut vault.whitelist, *addr);
            i = i + 1;
        };
    }        
}