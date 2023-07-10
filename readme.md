#### Local Setup

- Install Scarb [Scarb Install](https://docs.swmansion.com/scarb/download)

#### Done

- Task creation and execution
  - Only owner can create a task and put it in the queue and any body can call the execute function to execute the already queued task. Only owner can cancel the task. Implementation: task.cairo for task(create, read, cancel) and types.cairo for external sys calls

#### Todo

1. Replacing the relayers(mostly centralized,off-chain computation). What relayers do? In our case, they capture our transaction without chargin any fees(most times) and save them (no immediate execution) in their own off-chain set of networks and when our predefined rules gets fullfilled they submit our transaction or desired behaviour.

How to replace relayers?

Still thinking...
Currently I could think of is approving our contract (erc20 approve),then during the time of execution doing transferFrom user balance to our contract and our contract would bear the gas fees and other required things.
But this approach is perfect if the time is known before hand lets say perodic execution. What about instant or event based, (for event based also packing the transaction as of multicall could be option)

2. Monitoring.
