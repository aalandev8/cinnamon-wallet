import {
  type Address,
  type Chain,
  type PublicClient,
  type Transport,
  type Hex,
  concat,
  encodeAbiParameters,
  encodeFunctionData,
  encodePacked,
  pad,
  parseAbi,
  zeroHash,
} from "viem";
import { entryPoint08Abi, getUserOperationHash, toSmartAccount } from "viem/account-abstraction";
import { readContract } from "viem/actions";
import type { PrivateKeyAccount } from "viem/accounts";

export const MODULE_TYPE_HOOK = 4n;

export const walletAbi = parseAbi([
  "function execute(bytes32 mode, bytes executionCalldata) payable",
  "function rootValidator() view returns (address)",
  "function isModuleInstalled(uint256 moduleTypeId, address module, bytes additionalContext) view returns (bool)",
]);

export const factoryAbi = parseAbi([
  "struct Module { uint256 moduleType; address moduleAddress; bytes initData; }",
  "function createAccount(address rootValidator, bytes rootInitData, Module[] extraModules, bytes32 salt) returns (address)",
  "function getAddress(address rootValidator, bytes rootInitData, Module[] extraModules, bytes32 salt) view returns (address)",
]);

const CALLTYPE_SINGLE_MODE = pad("0x00", { dir: "right", size: 32 });
const CALLTYPE_BATCH_MODE = pad("0x01", { dir: "right", size: 32 });

export type Module = { moduleType: bigint; moduleAddress: Address; initData: Hex };

export type CinnamonAccountParams = {
  client: PublicClient<Transport, Chain>;
  owner: PrivateKeyAccount;
  entryPoint: Address;
  factory: Address;
  rootValidator: Address;
  extraModules?: Module[];
  salt?: Hex;
};

export async function toCinnamonAccount(params: CinnamonAccountParams) {
  const { client, owner, factory, rootValidator, extraModules = [], salt = zeroHash } = params;
  const rootInitData = encodeAbiParameters([{ type: "address" }], [owner.address]);
  const entryPoint = { abi: entryPoint08Abi, address: params.entryPoint, version: "0.8" } as const;
  const factoryArgs = [rootValidator, rootInitData, extraModules, salt] as const;

  const address = await readContract(client, {
    address: factory,
    abi: factoryAbi,
    functionName: "getAddress",
    args: factoryArgs,
  });

  return toSmartAccount({
    client,
    entryPoint,

    async getAddress() {
      return address;
    },

    async getFactoryArgs() {
      return {
        factory,
        factoryData: encodeFunctionData({ abi: factoryAbi, functionName: "createAccount", args: factoryArgs }),
      };
    },

    async getNonce() {
      return readContract(client, {
        address: entryPoint.address,
        abi: entryPoint08Abi,
        functionName: "getNonce",
        args: [address, 0n],
      });
    },

    async encodeCalls(calls) {
      if (calls.length === 1) {
        const { to, value = 0n, data = "0x" } = calls[0];
        return encodeFunctionData({
          abi: walletAbi,
          functionName: "execute",
          args: [CALLTYPE_SINGLE_MODE, encodePacked(["address", "uint256", "bytes"], [to, value, data])],
        });
      }
      const executions = calls.map(({ to, value = 0n, data = "0x" }) => ({ target: to, value, callData: data }));
      return encodeFunctionData({
        abi: walletAbi,
        functionName: "execute",
        args: [
          CALLTYPE_BATCH_MODE,
          encodeAbiParameters(
            [
              {
                type: "tuple[]",
                components: [
                  { name: "target", type: "address" },
                  { name: "value", type: "uint256" },
                  { name: "callData", type: "bytes" },
                ],
              },
            ],
            [executions],
          ),
        ],
      });
    },

    async getStubSignature() {
      return concat([pad("0x01", { size: 32 }), pad("0x01", { size: 32 }), "0x1b"]);
    },

    async signUserOperation(userOperation) {
      const hash = getUserOperationHash({
        chainId: client.chain.id,
        entryPointAddress: entryPoint.address,
        entryPointVersion: entryPoint.version,
        userOperation: { ...userOperation, sender: address },
      });
      return owner.sign({ hash });
    },

    async signMessage() {
      throw new Error("ERC-1271 is not supported in the MVP");
    },

    async signTypedData() {
      throw new Error("ERC-1271 is not supported in the MVP");
    },
  });
}
