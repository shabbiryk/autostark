Only Scarb is used. To run locally install Scarb

#### Almost Done ?

Only owner can create task. Task (i.e. externall calls or any external contract interactions). For what kind of data see (src/types.cairo) call struct. Unlike only owner can create a task, everybody can call the execute(of already queued task).

#### Todo Now?

1. Replacing the relayers(mostly centralized,off-chain computation). What relayers do? In our case, they capture our transaction without chargin any fees(most times) and save them (no immediate execution) in their own off-chain set of networks and when our predefined rules gets fullfilled they submit our transaction or desired behaviour.

How to replace relayers?

Still thinking...
Currently I could think of is approving our contract (erc20 approve),then during the time of execution doing transferFrom user balance to our contract and our contract would bear the gas fees and other required things.
But this approach is perfect if the time is known before hand lets say perodic execution. What about instant or event based, (for event based also packing the transaction as of multicall could be option)

2. Monitoring.
