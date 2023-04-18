# Staking-Upgradable Hardhat Project


1. Install Libraries

```shell
npm i
```


2. Deploy Contracts

```shell
npx hardhat compile #compile contract

npx hardhat node #run local node

#open new terminal

npx hardhat run --network localhost scripts/deploy.js #deploy contracts
```

3. Upgrade using Proxy

```shell
npx hardhat run --network localhost scripts/upgrade.js

```
