use core::result::ResultTrait;
use starknet::{ContractAddress};
use timepa::types::{Call};
use timepa::types::CallTrait;
use core::array::ArrayTrait;
use starknet::{SyscallResult, syscalls::call_contract_syscall};
use serde::Serde;

#[starknet::interface]
trait IERC20DispatcherTrait<T> {
    fn balance_of(self: T, call: Call) -> Span::<felt252>;
    fn transfer_from(self: T, call: Call) -> Span::<felt252>;
    fn approve(self: T, call: Call) -> Span::<felt252>;
}

#[derive(Copy, Drop, storage_access::StorageAccess, Serde)]
struct IERC20Dispatcher {
    contract_address: ContractAddress, 
}

impl IERC20DispatcherImpl of IERC20DispatcherTrait<IERC20Dispatcher> {
    fn balance_of(self: IERC20Dispatcher, call: Call) -> Span::<felt252> {
        call.execute()
    }
    fn transfer_from(self: IERC20Dispatcher, call: Call) -> Span::<felt252> {
        call.execute()
    }
    fn approve(self: IERC20Dispatcher, call: Call) -> Span::<felt252> {
        call.execute()
    }
}

#[starknet::interface]
trait ITask<TStorage> {
    // Queue a list of calls to be executed after the delay. Only the owner may call this.
    fn queue(ref self: TStorage, calls: Array<Call>, input_user_spend: u256) -> felt252;

    // Cancel a queued proposal before it is executed. Only the owner may call this.
    fn cancel(ref self: TStorage, id: felt252);

    // Execute a list of calls that have previously been queued. Anyone may call this.
    fn execute(ref self: TStorage, calls: Array<Call>) -> Array<Span<felt252>>;

    // Return the execution window, i.e. the start and end timestamp in which the call can be executed
    fn get_execution_window(self: @TStorage, id: felt252) -> (u64, u64);

    // Get the current owner
    fn get_owner(self: @TStorage) -> ContractAddress;
}

#[starknet::contract]
mod Task {
    use super::{ITask, Call, ContractAddress, IERC20Dispatcher, IERC20DispatcherTrait};
    use timepa::types::{CallTrait};
    use array::{ArrayTrait, SpanTrait};
    use option::{OptionTrait};
    use hash::LegacyHash;
    use starknet::{get_caller_address, get_block_timestamp, get_contract_address};
    use zeroable::{Zeroable};
    use traits::{Into};
    use result::{ResultTrait};

    #[storage]
    struct Storage {
        owner: ContractAddress,
        alloed_token_address: ContractAddress,
        window: u64,
        delay: u64,
        execution_started: LegacyMap<felt252, u64>,
        executed: LegacyMap<felt252, u64>
    }

    #[derive(Serde, Drop)]
    struct UserBalance {
        balance: u256
    }

    #[derive(Serde, Drop)]
    struct SuccessFelt {
        success: felt252
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        alloed_token_address: ContractAddress,
        window: u64,
        delay: u64
    ) {
        self.owner.write(owner);
        self.alloed_token_address.write(alloed_token_address);
        self.window.write(window);
        self.delay.write(delay);
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

    fn generate_total_user_spend(usr_calls: @Array<Call>) -> felt252 {
        let mut amount: felt252 = 0;
        let mut span = usr_calls.span();
        loop {
            match span.pop_front() {
                Option::Some(call) => {
                    amount += call.metadata()
                },
                Option::None(_) => {
                    break amount;
                }
            };
        };
        amount
    }

    fn get_current_max_gas_fees() -> u256 {
        // todo: how to get the current gas fees, inside contract, corelib:TXInfo?
        1
    }


    fn get_balance_of(token_contract: ContractAddress, whose_balance: ContractAddress) -> u256 {
        let mut calldata: Array<felt252> = ArrayTrait::new();
        Serde::serialize(@whose_balance, ref calldata);
        let call = Call {
            address: token_contract,
            // entry_point_selector of balanceOf erc20 func testent
            entry_point_selector: 0x2e4263afad30923c891518314c3c95dbe830a16874e8abc5777a9a20b54c76e,
            calldata: calldata
        };
        let mut current_balance = IERC20Dispatcher {
            contract_address: token_contract
        }.balance_of(call);
        let final_balance: UserBalance = Serde::<UserBalance>::deserialize(ref current_balance)
            .unwrap(); // this kind of deserialize should work?
        final_balance.balance
    }

    fn approve_us_for_spend(
        spender: ContractAddress, token_contract: ContractAddress, amount: u256
    ) -> felt252 {
        let mut calldata: Array<felt252> = ArrayTrait::new();
        // notice: the order of args must be same as Interface of erc20
        Serde::serialize(@spender, ref calldata);
        Serde::serialize(@amount, ref calldata);
        let call = Call {
            address: token_contract,
            // entry_point_selector of approve erc20 func testnet
            entry_point_selector: 0x219209e083275171774dab1df80982e9df2096516f06319c5c6d71ae0a8480c,
            calldata: calldata
        };
        let mut result = IERC20Dispatcher { contract_address: token_contract }.approve(call);
        let destrt_result: SuccessFelt = Serde::<SuccessFelt>::deserialize(ref result)
            .unwrap(); // this kind of deserialize should work?
        destrt_result.success
    }

    fn transfer_from_to_us(
        token_contract: ContractAddress,
        sender: ContractAddress,
        recipient: ContractAddress,
        amount: u256
    ) -> felt252 {
        let mut calldata: Array<felt252> = ArrayTrait::new();
        // notice: the order of args must be same as Interface of erc20
        Serde::serialize(@sender, ref calldata);
        Serde::serialize(@recipient, ref calldata);
        Serde::serialize(@amount, ref calldata);
        let call = Call {
            address: token_contract,
            // entry_point_selector of transferFrom erc20 func testnet
            entry_point_selector: 0x41b033f4a31df8067c24d1e9b550a2ce75fd4a29e1147af9752174f0e6cb20,
            calldata: calldata
        };
        let mut result = IERC20Dispatcher { contract_address: token_contract }.transfer_from(call);
        let destrt_result: SuccessFelt = Serde::<SuccessFelt>::deserialize(ref result)
            .unwrap(); // this kind of deserialize should work?
        destrt_result.success
    }

    #[generate_trait]
    impl TaskInternal of TaskInternalTrait {
        fn check_if_owner(self: @ContractState) {
            assert(get_caller_address() == self.owner.read(), 'OWNER_CAN_CALL');
        }

        fn check_self_call(self: @ContractState) {
            assert(get_caller_address() == get_caller_address(), 'SELF_CALL');
        }
    }
    #[external(v0)]
    impl TaskImpl of ITask<ContractState> {
        fn queue(ref self: ContractState, calls: Array<Call>, input_user_spend: u256) -> felt252 {
            self.check_if_owner();
            let id = to_id(@calls);
            assert(self.execution_started.read(id).is_zero(), 'ALREADY_STACK');
            // todo get the total spending, current gas
            let user_spend_total: u256 = generate_total_user_spend(@calls).into();
            let user_total_spend_gas_inc = user_spend_total + get_current_max_gas_fees();
            assert(user_total_spend_gas_inc == input_user_spend, 'USER_SPEND_AMOUNT_INVALID');
            let user_balance = get_balance_of(
                self.alloed_token_address.read(), get_caller_address()
            );
            assert(user_balance >= user_total_spend_gas_inc, 'INSUFFICIENT_BALANCE_TO_SPEND');
            //WIP make approve to us change later to contract owner after converting to threads(task)
            approve_us_for_spend(
                get_contract_address(), self.alloed_token_address.read(), user_total_spend_gas_inc
            );
            // if this above approve... call passes i.e true then only forward. WIP currently due to reutrn type of felt
            self.execution_started.write(id, get_block_timestamp());
            id
        }

        fn execute(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            let id = to_id(@calls);
            assert(self.executed.read(id).is_zero(), 'ALREADY_STARTED');
            let (earliest, latest) = self.get_execution_window(id);
            let current_time = get_block_timestamp();
            assert(current_time >= earliest, 'EARLY');
            assert(current_time < latest, 'LATE');
            // WIP currently due to return type felt
            transfer_from_to_us(
                self.alloed_token_address.read(), self.owner.read(), get_contract_address(), 100
            );
            // if this transferFrom passes then only move forward
            self.executed.write(id, current_time);
            let mut results: Array<Span<felt252>> = ArrayTrait::new();
            let mut call_span = calls.span();
            loop {
                match call_span.pop_front() {
                    Option::Some(call) => {
                        results.append(call.execute())
                    },
                    Option::None(_) => {
                        break;
                    },
                };
            };
            results
        }

        fn get_execution_window(self: @ContractState, id: felt252) -> (u64, u64) {
            let start_time = self.execution_started.read(id);
            assert(start_time.is_non_zero(), 'Does Not exits');
            let (delay, window) = (self.delay.read(), self.window.read());
            let earliest = start_time + delay;
            let latest = earliest + window;
            (earliest, latest)
        }

        fn cancel(ref self: ContractState, id: felt252) {
            self.check_if_owner();
            assert(self.execution_started.read(id).is_non_zero(), 'NOT EXIST');
            assert(self.executed.read(id).is_zero(), 'ALREADY_EXECUTED');
            self.execution_started.write(id, 0);
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }
    }
}
