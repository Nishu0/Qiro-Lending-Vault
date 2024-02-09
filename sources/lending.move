module qiro::lending_vault{
    use std::signer;
    use aptos_framework::account;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::managed_coin;
    use aptos_std::type_info;
    use aptos_std::simple_map::{Self, SimpleMap};
    
    // Errors
    const EALREADY_VAULT: u64 = 1;
    const ENOT_ADMIN: u64 = 2;
    const ENOT_WHITELISTED: u64 = 3;
    const EINSUFFICIENT_BALANCE: u64 = 4;
    const INTEREST_RATE: u64 = 10;
    const EINVALID_ID: u64 = 5;
    const EINSUFFICIENT_PREFILLED: u64 = 6;


    struct UserPool has store, drop{
        pool_address: address,
        total_deposit: u64,
    }

    struct UserPools has key, store{
        pools: vector<UserPool>,
    }

    struct VaultPool has key, store{
        coin_type: address,
        fee: u64,
    }

    struct VaultPools has key, store{
        pools: vector<LiquidityPool>,
    }

    struct VaultPoolCap has key{
        liquidity_pool_cap: account::SignerCapability,
    }

    struct VaultPoolMap has key{
        liquidity_pool_map:SimpleMap<vector<u8>,address>,
    }

    fun coin_address<CoinType>(): address {
        let type_info = type_info::type_of<CoinType>();
        type_info::account_address(&type_info)
    }

    // Resources
    struct Deposit has key, store, drop, copy {
        id: u64, 
        amount: u64, 
        timestamp: u64,
        user: address, 
    }
    struct Vault has key {
        vault_address: address,
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
            vault_address: signer::address_of(account),
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
    #[view]
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
    // #[view]
    public fun calculate_interest(deposit: Deposit): u64 {
        let time = timestamp::now_seconds() - deposit.timestamp;
        let interest = (deposit.amount * INTEREST_RATE * time) / 100;
        interest
    }
    
    // Deposit function
    public entry fun deposit( user: &signer, vault_address: address, amount: u64) acquires Vault {
        assert!(is_whitelisted(vault_address, signer::address_of(user)), ENOT_WHITELISTED);
        let user_balance = coin::balance<AptosCoin>(signer::address_of(user));
        assert!(user_balance >= amount, EINSUFFICIENT_BALANCE);
        coin::transfer<AptosCoin>(user, vault_address, amount);
        let id = generate_id();
        let timestamp = timestamp::now_seconds();
        let deposit = Deposit {
            id,
            amount,
            timestamp,
            user: signer::address_of(user),
        };
        let vault = borrow_global_mut<Vault>(vault_address);
        vector::push_back(&mut vault.deposits, deposit);
    }

    //withdraw function with amount as parameter
    public entry fun withdraw_amount(vault_address: address, user: address, amount: u64) acquires Vault, VaultCap {
        let vaultcap = borrow_global_mut<VaultCap>(vault_address);
        let vault_signer_cap = account::create_signer_with_capability(&vaultcap.vault_cap);
        let vault = borrow_global_mut<Vault>(vault_address);
        let count = 0;
        let len = vector::length(&vault.deposits);
        while (count < len) {
            let deposit = vector::borrow_mut(&mut vault.deposits, count);
            if (deposit.user == user) {
                let interest = calculate_interest(*deposit);
                let total_amount = deposit.amount + interest;
                if (total_amount >= amount) {
                    // coin::transfer<AptosCoin>(&vault_signer_cap, user, amount);
                    deposit.amount = deposit.amount - amount;
                    //vector::replace(&mut vault.deposits, count, *deposit);
                };
            };
            count = count + 1;
        };
        coin::transfer<AptosCoin>(&vault_signer_cap, user, amount);
    }
    
}