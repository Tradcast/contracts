import type { ContractTransaction } from 'ethers';

export default async function exec(
  firstMessage: string,
  tx: ContractTransaction | Promise<ContractTransaction>,
  secondMessage?: string
) {
  tx = await Promise.resolve(tx);
  console.log(firstMessage, ' | hash =', tx.hash);
  const result = await tx.wait(2);
  if (secondMessage) {
    console.log(secondMessage);
  } else {
    console.log('Done.');
  }
  return result;
}

function wait(ms: number) {
  return new Promise<void>((resolve) => {
    setTimeout(() => resolve(), ms);
  });
}
