#### Local Setup

- Install Scarb [Scarb Install](https://docs.swmansion.com/scarb/download)
- Run `scarb build`
- If VS Code User, just install a cairo 1 extension
- Replace `timepa` inside task.cairo to our project name `autostark`

### How It Works ?

Built for MVP. Very high level overview of how to create a task and execute it. There are others which are self-explanatory like cancel the job, get configs etc

#### Task Creation

For instance Alice wants to send xyz amount of eth to User1 and abc amount of eth to user2 after 20 days at some fixed time.

First Alice creates a task by calling a queue function where his intended calls are hashed and unique id is generated. His calls(in this case, transfer calls) total expenditure is calculated, assertion is made wether he holds the token to cover the expenditure or not. If he holds then we make a ERC20 approval to our contract(as spender). Now his id is stored. (only id not calls).

#### Task Execution

Task execution part is open to all, any one can call this function with exact set of calls of Alice. This approach sort of relax the part of relayers and necessity of maintaing network of bots. When execute function is called again id is generated from the supplied calls and checked against the id of Alice or other stored one's. If the id matches then time constrains are checked. Before execution of Alice calls ERC20 transferFrom is done to move the required assets from Alice to our contract as our contract would pay the fees and required token amounts. At last Alice calls would be executed and it's array of result would be returned.

### Todo

#### Contract

- Testing: At least one e2e test
- Could move the `transferFrom` execution to separate function which can be called by only us(contract owner) just before time of exe
- **Help** Had mentioned in comments with todo and WIP. One real pain is to have a work around for `felt252` to `bool` (mentioned in queue and execute function, task.cairo)
- **Help** Calculating the gas fees. How to get gasLimit and maxGasLimit(like in ethereum), in starknet. Needs this functionality to speculate how much gas would be required in the future for txn
- Introduce mapping of id to struct with single user as owner unlike currently where deployer is owner.(I would do it)
- Deploy to testnet

#### Application (Front end and other)

- DB to store the serialized calls of the user.

  - Since at the time of creation, we don't store the calls (we store id). Have to store the actual calls(serialized) and make it accessible via the Frontend. So that everybody can call it. No need to show the actual calls but only the id of it would be enough.In future it can converted into sort of bot race and reward.

- Cron Job which keeps time and calls execute with above stored calls

- User Utility: connect to wallet, starknet js ...

- User Interface: Landing page, forms to create a task ...
