use starknet::{ContractAddress, ContractAddressIntoFelt252};
use array::{ArrayTrait, SpanTrait};
use traits::{Into};         
use hash::{LegacyHash};
use starknet::{SyscallResult, syscalls::call_contract_syscall};
use result::{ResultTrait};    //utilities 

#[derive(Drop, Serde)]
struct Call {                //definition of the struct called 'call'
    from: ContractAddress,
    to: ContractAddress,
    selector: felt252,         //felt252 is the datatype just like u256 but for ZK abstraction
    amount: u256,
    calldata: Array<felt252>    
}

#[generate_trait]
impl CallTraitImpl of CallTrait {              //just like objects in Java 
    fn hash(self: @Call) -> felt252 {           
        let mut data_hash = 0;
        let mut data_span = self.calldata.span();
        loop {
            match data_span.pop_front() {
                Option::Some(word) => {
                    data_hash = pedersen(data_hash, *word);
                },
                Option::None(_) => {
                    break;
                }
            };
        };

        pedersen(pedersen((*self.from).into(), *self.selector), data_hash)
    }
}

