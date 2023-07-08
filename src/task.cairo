use core::result::ResultTrait;
use starknet::{ContractAddress};
use timepa::types::{Call};

#[starknet::interface]
trait ITask<TStorage> {
    // Queue a list of calls to be executed after the delay. Only the owner may call this.
    fn queue(ref self: TStorage, calls: Array<Call>) -> felt252;

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
    use super::{ITask, Call, ContractAddress};
    use timepa::types::{CallTrait};
    use array::{ArrayTrait, SpanTrait};
    use hash::LegacyHash;
    use starknet::{get_caller_address, get_block_timestamp};
    use zeroable::{Zeroable};
    use traits::{Into};
    use result::{ResultTrait};

    #[storage]
    struct Storage {
        owner: ContractAddress,
        window: u64,
        delay: u64,
        execution_started: LegacyMap<felt252, u64>,
        executed: LegacyMap<felt252, u64>
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, window: u64, delay: u64) {
        self.owner.write(owner);
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
        fn queue(ref self: ContractState, calls: Array<Call>) -> felt252 {
            self.check_if_owner();
            let id = to_id(@calls);
            assert(self.execution_started.read(id).is_zero(), 'ALREADY_STACK');
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
