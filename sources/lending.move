module qiro::lending_vault{
    use std::signer;
    use aptos_framework::account;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
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
    const EALREADY_HAS_BALANCE: u64 = 7;
    const EEQUAL_ADDR: u64 = 8;

    // Resources
    struct UserPool has store, drop{
        pool_address: address,
        total_deposit: u64,
        timestamp: u64, 
    }
    struct Whitelist has key, store, drop {
        whitelist: vector<address>,
    }

    struct UserPools has key, store{
        pools: vector<UserPool>,
    }

    struct LiquidityPool has key, store {
        coin_type: address,
        fee: u64,
    }

    struct LiquidityPools has key, store {
        pools: vector<LiquidityPool>
    }

    struct LiquidityPoolMap has key {
        liquidity_pool_map: SimpleMap< vector<u8>,address>,
    }

    struct LiquidityPoolCap has key{
        liquidity_pool_cap: account::SignerCapability,
    }

    struct LPCoin has store, drop {
        value: u64,
        pool_address: address,
    }

    fun coin_address<CoinType>(): address {
        let type_info = type_info::type_of<CoinType>();
        type_info::account_address(&type_info)
    }

    // Entry functions
    public entry fun deploy_pool<CoinType>(account: &signer, fee:u64, seeds: vector<u8>, funds:u64) acquires LiquidityPoolMap , LiquidityPools{
        let account_addr = signer::address_of(account);

        let (liquidity_pool, liquidity_pool_cap) = account::create_resource_account(account, seeds); //resource account
        coin::register<CoinType>(&liquidity_pool);
        coin::transfer<CoinType>(account, signer::address_of(&liquidity_pool), funds);
        let liquidity_pool_address = signer::address_of(&liquidity_pool);

        if (!exists<LiquidityPoolMap>(account_addr)) {
            move_to(account, LiquidityPoolMap {liquidity_pool_map: simple_map::create()})
        };

        let maps = borrow_global_mut<LiquidityPoolMap>(account_addr);
        simple_map::add(&mut maps.liquidity_pool_map, seeds,liquidity_pool_address);

        let pool_signer_from_cap = account::create_signer_with_capability(&liquidity_pool_cap);
        let coin_address = coin_address<CoinType>();

        let whitelist = Whitelist {
            whitelist: vector::empty(),
        };

        if(!exists<Whitelist>(account_addr)){
            move_to<Whitelist>(account, whitelist);
        };

        let liquidity_pool = LiquidityPool {
            coin_type: coin_address,
            fee: fee
        };

        if(!exists<LiquidityPools>(account_addr))
        {
            let pools = vector[];
            vector::push_back(&mut pools, liquidity_pool);
            move_to<LiquidityPools>(account, LiquidityPools{pools});
        } else {
            let pools = borrow_global_mut<LiquidityPools>(account_addr);
            vector::push_back(&mut pools.pools, liquidity_pool);
        };
        move_to<LiquidityPoolCap>(&pool_signer_from_cap, LiquidityPoolCap{
            liquidity_pool_cap: liquidity_pool_cap
        });
        managed_coin::register<CoinType>(&pool_signer_from_cap); 
    }

    public entry fun add_to_whitelist(account: &signer, addresses: vector<address>) acquires Whitelist {
        let whitelist = borrow_global_mut<Whitelist>(signer::address_of(account));
        let i = 0;
        let len = vector::length(&addresses);
        while (i < len) {
            let addr = vector::borrow(&addresses, i);
            vector::push_back(&mut whitelist.whitelist, *addr);
            i = i + 1;
        };
    }
    //To check if the user is whitelisted
    #[view]
    public fun is_whitelisted(user_address: address): bool acquires Whitelist {
        let whitelist = borrow_global<Whitelist>(user_address);
        let i = 0;
        let len = vector::length(&whitelist.whitelist);
        while (i < len) {
            let addr = vector::borrow(&whitelist.whitelist, i);
            if (*addr == user_address) {
                return true
            };
            i = i + 1;
        };
        return false
    }
    
    public entry fun deposit<CoinType>(account: &signer, pool_address: address, amount: u64) acquires UserPools{
        
        let signer_address = signer::address_of(account);
        //To check if the user is whitelisted
        if(!exists<UserPools>(signer_address))
        {
           managed_coin::register<CoinType>(account);    
            let pool = UserPool {
               pool_address,
               total_deposit: amount,
               timestamp: timestamp::now_seconds(),
            };          
            let pools = vector[];
            vector::push_back(&mut pools, pool);            
            move_to<UserPools>(account, UserPools{pools});
        } 
        else {
            let pool = borrow_global_mut<UserPools>(signer_address); 
            let count = 0;
            let pool_length = vector::length(&pool.pools);
            while(count < pool_length) {
                let pool = vector::borrow_mut(&mut pool.pools, count);
                if(pool.pool_address == pool_address) {
                    pool.total_deposit = pool.total_deposit + amount;
                    break
                };   
                count = count + 1;
            }           
        };
        //mint a coin
        //managed_coin::mint<LPCoin>(account,signer_address, amount);
        coin::transfer<CoinType>(account, pool_address, amount);
        
    }

    public entry fun withdraw<CoinType>( account: &signer, pool_address: address, amount: u64) acquires UserPools, LiquidityPoolCap {
        let account_addr= signer::address_of(account);
        let pool = borrow_global_mut<LiquidityPoolCap>(pool_address);
        let pool_signer_from_cap = account::create_signer_with_capability(&pool.liquidity_pool_cap);

        let user_pools = borrow_global_mut<UserPools>(account_addr); 
            let count = 0;
            let pool_length =  vector::length(&user_pools.pools);
            while(count < pool_length) {
                let pool = vector::borrow_mut(&mut user_pools.pools, count);
                if(pool.pool_address == pool_address) {
                    //calculate the interest
                    let time= timestamp::now_seconds() - pool.timestamp;
                    let interest_amount = (pool.total_deposit * INTEREST_RATE * time) / (100 * 365 * 24 * 60 * 60);
                    pool.total_deposit = pool.total_deposit - amount - interest_amount;
                    amount = amount + interest_amount;
                    break
                };
                count = count + 1;
            };  
            
        coin::transfer<CoinType>(&pool_signer_from_cap, account_addr, amount);
        //managed_coin::burn<LPCoin>(account, amount);
    }
    
}