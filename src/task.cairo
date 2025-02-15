use core::traits::TryInto;
use core::starknet::SyscallResultTrait;
use core::result::ResultTrait;
use option::{OptionTrait};
use starknet::{ContractAddress};
use timepa::types::{Call};
use timepa::types::CallTrait;
use core::array::ArrayTrait;
use starknet::{SyscallResult, syscalls::call_contract_syscall};
use serde::Serde;

#[derive(Drop, Copy, Serde, storage_access::StorageAccess)]
struct TaskTimeDetails {
    window: u64,
    delay: u64,
}

#[starknet::interface]
trait ITask<TStorage> {
    // Queue a list of calls to be executed after the delay. 
    fn queue(
        ref self: TStorage,
        calls: Array<Call>,
        task_time_detail: TaskTimeDetails,
        input_user_spend: u256
    ) -> felt252;

    // Cancel a queued proposal before it is. Only the owner may call this.
    fn cancel(ref self: TStorage, id: felt252);

    // Execute a list of calls that have previously been queued. Anyone may call this.
    fn execute(ref self: TStorage, calls: Array<Call>) -> bool;

    // Return the execution window, i.e. the start and end timestamp in which the call can be executed
    fn get_execution_window(self: @TStorage, id: felt252) -> (u64, u64);

    //Get task owner
    fn get_task_owner(self: @TStorage, id: felt252) -> ContractAddress;

    fn name(self: @TStorage) -> felt252;
    fn total_supply(self: @TStorage) -> u256;
    fn balance_of(self: @TStorage, account: ContractAddress) -> u256;
    fn mint_me(ref self: TStorage, your_address: ContractAddress) -> bool;
    fn transfer(ref self: TStorage, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TStorage, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
}

#[starknet::contract]
mod Task {
    use super::{ITask, Call, ContractAddress, TaskTimeDetails};
    use timepa::types::{CallTrait};
    use array::{ArrayTrait, SpanTrait};
    use option::{OptionTrait};
    use hash::LegacyHash;
    use starknet::{
        get_caller_address, get_block_timestamp, get_contract_address, contract_address_const,
        call_contract_syscall,
    };
    use zeroable::{Zeroable};
    use traits::{Into};
    use result::{ResultTrait};

    #[derive(Copy, Drop, storage_access::StorageAccess)]
    struct UserTaskDetails {
        window: u64,
        delay: u64,
        user_address: ContractAddress,
        execution_started: u64,
        pre_user_spend: u256,
    }

    #[derive(Copy, Drop, storage_access::StorageAccess)]
    struct CallDetails {
        from: ContractAddress,
        to: ContractAddress,
        amount: u256
    }

    #[derive(Copy, Drop, storage_access::StorageAccess)]
    struct UserPostTaskDetails {
        executed: u64, 
    // payback_amount: u256, // for v2 post transaction if possible, else open to user to claim at anytime
    // post_task_user_spend: u256, // for v2
    }


    #[storage]
    struct Storage {
        id_to_user_details: LegacyMap<felt252, UserTaskDetails>,
        id_to_post_task_details: LegacyMap<felt252, UserPostTaskDetails>,
        total_supply: u256,
        name: felt252,
        balances: LegacyMap<ContractAddress, u256>,
        mint_list: LegacyMap<ContractAddress, bool>
    }

    #[derive(Serde, Drop, storage_access::StorageAccess)]
    struct UserBalance {
        balance: u256
    }

    #[constructor]
    fn constructor(ref self: ContractState, name: felt252) {
        self.name.write(name);
        self.total_supply.write(1000000);
        self.balances.write(get_contract_address(), 1000000);
    }


    fn to_id(calls: @Array<Call>) -> felt252 {
        let mut state = 0;
        let mut span = calls.span();
        loop {
            match span.pop_front() {
                Option::Some(call) => {
                    state = pedersen(state, call.hash())
                },
                Option::None(_) => {
                    break state;
                },
            };
        }
    }


    #[generate_trait]
    impl TaskInternal of TaskInternalTrait {
        fn check_if_task_owner_call(self: @ContractState, id: felt252) {
            assert(
                get_caller_address() == self.id_to_user_details.read(id).user_address,
                'TASK_OWNER_CAN_CALL'
            )
        }
    }
    #[external(v0)]
    impl TaskImpl of ITask<ContractState> {
        fn queue(
            ref self: ContractState,
            calls: Array<Call>,
            task_time_detail: TaskTimeDetails,
            input_user_spend: u256
        ) -> felt252 {
            let id = to_id(@calls);

            let user_total_spend_gas_inc = input_user_spend + 0;

            assert(user_total_spend_gas_inc == input_user_spend, 'USER_SPEND_AMOUNT_INVALID');

            let user_balance = self.balances.read(get_caller_address());
            assert(user_balance >= user_total_spend_gas_inc, 'NOT ENOUGH TOKENS');

            // pre-transfer
            self.balances.write(get_caller_address(), user_total_spend_gas_inc);
            self
                .id_to_user_details
                .write(
                    id,
                    UserTaskDetails {
                        window: task_time_detail.window,
                        delay: task_time_detail.delay,
                        execution_started: get_block_timestamp(),
                        pre_user_spend: user_total_spend_gas_inc,
                        user_address: get_caller_address()
                    }
                );
            id
        }

        fn execute(ref self: ContractState, calls: Array<Call>) -> bool {
            let id = to_id(@calls);

            assert(self.id_to_post_task_details.read(id).executed.is_zero(), 'ALREADY_STARTED');

            let (earliest, latest) = self.get_execution_window(id);
            let current_time = get_block_timestamp();

            assert(current_time >= earliest, 'EARLY');
            assert(current_time < latest, 'LATE');

            self.id_to_post_task_details.write(id, UserPostTaskDetails { executed: current_time });
            let mut arr = calls;
            let arr_res = arr.pop_front().unwrap();
            self.transfer_from(arr_res.from, arr_res.to, arr_res.amount)
        }

        fn get_execution_window(self: @ContractState, id: felt252) -> (u64, u64) {
            let start_time = self.id_to_user_details.read(id).execution_started;

            assert(start_time.is_non_zero(), 'Does Not exits');

            let (delay, window) = (
                self.id_to_user_details.read(id).delay, self.id_to_user_details.read(id).window
            );
            let earliest = start_time + delay;
            let latest = earliest + window;
            (earliest, latest)
        }

        fn cancel(ref self: ContractState, id: felt252) {
            self.check_if_task_owner_call(id);
            assert(self.id_to_user_details.read(id).execution_started.is_non_zero(), 'NOT EXIST');
            let user_pre_spend = self.id_to_user_details.read(id).pre_user_spend;
            self
                .id_to_user_details
                .write(
                    id,
                    UserTaskDetails {
                        execution_started: 0,
                        window: 0,
                        delay: 0,
                        pre_user_spend: 0,
                        user_address: contract_address_const::<0>(),
                    }
                );
            self.transfer_from(get_contract_address(), get_caller_address(), user_pre_spend);
        }


        fn get_task_owner(self: @ContractState, id: felt252) -> ContractAddress {
            self.id_to_user_details.read(id).user_address
        }

        fn name(self: @ContractState) -> felt252 {
            self.name.read()
        }

        fn total_supply(self: @ContractState) -> u256 {
            self.total_supply.read()
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn mint_me(ref self: ContractState, your_address: ContractAddress) -> bool {
            self.transfer_from(get_contract_address(), your_address, 100)
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            self.transfer_from(get_caller_address(), recipient, amount)
        }

        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            let mut sender_bal = self.balances.read(sender);
            sender_bal = sender_bal - amount;
            self.balances.write(sender, sender_bal);

            let mut recipient_bal = self.balances.read(recipient);
            recipient_bal = recipient_bal + amount;
            self.balances.write(recipient, recipient_bal);
            true
        }
    }
}
