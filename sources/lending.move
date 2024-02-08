module qiro::lending_vault{
    use std::signer;
    use aptos_framework::account;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    


    // Errors
    const EALREADY_VAULT: u64 = 1;
    const ENOT_ADMIN: u64 = 2;
    const ENOT_WHITELISTED: u64 = 3;
    const EINSUFFICIENT_BALANCE: u64 = 4;
    const INTEREST_RATE: u64 = 10;
    const EINVALID_ID: u64 = 5;
    const EINSUFFICIENT_PREFILLED: u64 = 6;



    // Resources
    struct Deposit has key, store, drop {
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
    struct VaultCap has key{
        vault_cap: account::SignerCapability,
    }

    // Entry functions
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
    //To check if the user is whitelisted
    public fun is_whitelisted(vault_address: address, user_address: address): bool acquires Vault {
        let vault = borrow_global<Vault>(vault_address);
        let i = 0;
        let len = vector::length(&vault.whitelist);
        while (i < len) {
            let addr = vector::borrow(&vault.whitelist, i);
            if (*addr == user_address) {
                return true
            };
            i = i + 1;
        };
        return false
    }
    // To generate a unique id for each deposit
    public fun generate_id(): u64 {
        timestamp::now_seconds()
    }
    // To calculate the interest
    public fun calculate_interest(deposit: &Deposit): u64 {
        let current = timestamp::now_seconds();
        let elapsed = current - deposit.timestamp;
        let rate = INTEREST_RATE / (365 * 24 * 60 * 60);
        let interest = deposit.amount * rate * elapsed;
        interest
    }
    // Deposit function
    public entry fun deposit(vault_address: address, user: &signer, amount: u64) acquires Vault {
        assert!(is_whitelisted(vault_address, signer::address_of(user)), ENOT_WHITELISTED);
        coin::transfer<AptosCoin>(user, vault_address, amount);
        let id = generate_id();
        let timestamp = timestamp::now_seconds();
        let deposit = Deposit {
            id,
            amount,
            timestamp,
        };
        let vault = borrow_global_mut<Vault>(vault_address);
        vector::push_back(&mut vault.deposits, deposit);
    }
}